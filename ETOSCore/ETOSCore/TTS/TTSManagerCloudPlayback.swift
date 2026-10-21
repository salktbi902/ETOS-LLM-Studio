import Foundation

extension TTSManager {
    func playAudio(clip: AudioClip, speed: Float) async throws {
        try Task.checkCancellation()
        // 每个分段独占后端和回调标识，旧播放器的结束回调不会结束新分段。
        stopCloudPlayback()
        await audioControlTask?.value
        try Task.checkCancellation()
        let playback = makeAudioPlayback(), id = UUID()
        audioPlayback = playback; audioPlaybackID = id
        activeBackend = .cloud; playbackState.status = .buffering
        do {
            let duration = try await playback.prepare(clip: clip, speed: speed) { [weak self] succeeded in
                self?.finishCloudPlayback(id: id, error: succeeded ? nil : TTSCloudAudioError.decode)
            }
            try Task.checkCancellation()
            guard audioPlaybackID == id else { throw CancellationError() }
            playbackState.duration = duration; playbackState.position = 0; playbackState.speed = speed
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioContinuation = continuation
                if isPausedByUser { playbackState.status = .paused }
                else { resumeCloudPlayback() }
            }
        } catch {
            await playback.stop()
            if audioPlaybackID == id {
                updateAudioPlaying(false)
                audioProgressTask?.cancel(); audioProgressTask = nil
                audioPlayback = nil
            }
            throw error
        }
        await playback.stop()
        guard audioPlaybackID == id else { return }
        updateAudioPlaying(false)
        audioProgressTask?.cancel(); audioProgressTask = nil
        audioPlayback = nil
        playbackState.position = 0; playbackState.duration = 0
    }

    func enqueueAudioControl(_ operation: @escaping @Sendable () async throws -> Void) {
        let previous = audioControlTask, id = audioPlaybackID
        audioControlTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, audioPlaybackID == id else { return }
            do { try await operation() }
            catch {
                guard !Task.isCancelled else { return }
                finishCloudPlayback(id: id, error: error)
            }
        }
    }

    func pauseCloudPlayback() {
        audioPlaybackActivityRevision &+= 1
        updateAudioPlaying(false)
        audioProgressTask?.cancel(); audioProgressTask = nil
        guard let playback = audioPlayback else { return }
        enqueueAudioControl { await playback.pause() }
    }

    func resumeCloudPlayback() {
        guard let playback = audioPlayback, audioContinuation != nil else { return }
        audioPlaybackActivityRevision &+= 1
        playbackState.status = .playing
        let id = audioPlaybackID
        let revision = audioPlaybackActivityRevision
        enqueueAudioControl { [weak self] in
            guard await self?.isCurrentCloudPlayback(id: id, revision: revision) == true else { return }
            do {
                try await playback.play()
            } catch {
                await self?.finishCloudPlayback(id: id, error: error, revision: revision)
                return
            }
            let position = await playback.position()
            await self?.updateCloudPlaybackPosition(position, id: id, revision: revision)
        }
        audioProgressTask?.cancel()
        audioProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                guard let self else { return }
                let observationRevision = self.audioPlaybackActivityRevision
                let position = await playback.position()
                guard !Task.isCancelled, audioPlaybackID == id, !isPausedByUser else { return }
                updateCloudPlaybackPosition(position, id: id, revision: observationRevision)
            }
        }
    }

    private func isCurrentCloudPlayback(id: UUID, revision: UInt64) -> Bool {
        audioPlaybackID == id && audioPlaybackActivityRevision == revision
            && audioContinuation != nil && !isPausedByUser && !isAudioSessionInterrupted && audioMediaServicesAvailable
    }

    func updateCloudPlaybackPosition(_ position: TTSCloudAudioPosition, id: UUID, revision: UInt64) {
        guard isCurrentCloudPlayback(id: id, revision: revision) else { return }
        playbackState.position = position.time
        playbackState.duration = position.duration
        updateAudioPlaying(position.isPlaying)
    }

    func finishCloudPlayback(id: UUID, error: Error?, revision: UInt64? = nil) {
        guard audioPlaybackID == id,
              revision == nil || revision == audioPlaybackActivityRevision,
              let continuation = audioContinuation else { return }
        updateAudioPlaying(false)
        audioContinuation = nil
        audioProgressTask?.cancel(); audioProgressTask = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func stopCloudPlayback() {
        audioPlaybackActivityRevision &+= 1
        updateAudioPlaying(false)
        audioPlaybackID = UUID()
        let progress = audioProgressTask
        progress?.cancel(); audioProgressTask = nil
        let previous = audioControlTask, playback = audioPlayback
        previous?.cancel()
        audioControlTask = Task {
            await previous?.value
            await progress?.value
            await playback?.stop()
        }
        audioPlayback = nil
        if let continuation = audioContinuation {
            audioContinuation = nil; continuation.resume(throwing: CancellationError())
        }
    }
}
