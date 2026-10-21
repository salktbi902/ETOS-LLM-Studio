import Foundation
import AVFoundation
import Combine
import Testing
@testable import ETOSCore

@Suite("朗读后台播放器生命周期")
@MainActor
struct TTSPlaybackLifecycleTests {
    @Test("音频覆盖只发布状态变化，不重复发布进度轮询状态")
    func actualAudioPublishesOnlyTransitions() async {
        let manager = makeManager(TTSPlaybackStub())
        var values: [Bool] = []
        let observation = manager.$isAudioPlaying.sink { values.append($0) }
        manager.updateAudioPlaying(false)
        manager.updateAudioPlaying(true)
        manager.updateAudioPlaying(true)
        manager.updateAudioPlaying(false)
        manager.updateAudioPlaying(false)
        #expect(values == [false, true, false])
        observation.cancel()
        await manager.stopAndWait()
    }

    @Test("注入设置和空服务不会访问旧设置单例，播放参数取自调用方快照")
    func injectedConfiguration() async {
        var settings = TTSSettingsSnapshot.defaultValue
        settings.playbackSpeed = 1.7
        let manager = TTSManager(urlSession: .shared, settingsProvider: { settings }, serviceProvider: { nil })
        #expect(manager.settings.playbackSpeed == 1.7); #expect(manager.serviceProvider() == nil)
        await manager.stopAndWait(clearHistory: true)
        #expect(manager.playbackState.speed == 1.7)
    }

    @Test("后台准备尚未结束时停止，等待接口不会提前结束或重新开始播放")
    func stopWaitsForPreparation() async {
        let backend = TTSPlaybackStub(suspendsPreparation: true)
        let manager = makeManager(backend)
        let playback = start(manager)
        await backend.waitForPreparation()
        #expect(manager.isSpeaking)
        #expect(!manager.isAudioPlaying)
        var drained = false
        let stop = Task { await manager.stopAndWait(); drained = true }
        await backend.waitForStop()
        #expect(!drained); #expect(await backend.playCount == 0)
        await backend.releasePreparation()
        await stop.value
        #expect(drained); #expect(await playback.value)
        #expect(await backend.playCount == 0); #expect(manager.playbackState.status == .idle)
        #expect(!manager.isAudioPlaying)
    }

    @Test("实际音频仅在准备完成并成功播放后生效，结束时立即清除")
    func actualAudioTracksSuccessfulPlayback() async {
        let backend = TTSPlaybackStub(suspendsPreparation: true)
        let manager = makeManager(backend)
        let playback = start(manager)
        await backend.waitForPreparation()
        #expect(!manager.isAudioPlaying)
        await backend.releasePreparation()
        await backend.waitForPlay(count: 1)
        await manager.audioControlTask?.value
        #expect(manager.isAudioPlaying)
        await backend.finish()
        #expect(!manager.isAudioPlaying)
        #expect(!(await playback.value))
        await manager.stopAndWait()
    }

    @Test("播放启动失败不能提供后台音频覆盖")
    func failedPlaybackNeverReportsActiveAudio() async {
        let backend = TTSPlaybackStub(failsPlayback: true)
        let manager = makeManager(backend)
        let playback = start(manager)
        #expect(!(await playback.value))
        #expect(!manager.isAudioPlaying)
        #expect(await backend.stopCount > 0)
        await manager.stopAndWait()
    }

    @Test("暂停期间定位和调速不会启动播放，恢复沿用定位结果")
    func pausedSeekingDoesNotResume() async {
        let backend = TTSPlaybackStub()
        let manager = makeManager(backend)
        let playback = start(manager)
        await backend.waitForPlay(count: 1)
        await manager.audioControlTask?.value
        #expect(manager.isAudioPlaying)
        manager.pause(); await manager.audioControlTask?.value
        #expect(manager.isSpeaking)
        #expect(!manager.isAudioPlaying)
        manager.seekBy(seconds: 12); manager.setPlaybackSpeed(1.5)
        await manager.audioControlTask?.value
        #expect(await backend.playCount == 1); #expect(await backend.time == 12)
        #expect(await backend.speed == 1.5); #expect(manager.playbackState.status == .paused)
        manager.resume(); await backend.waitForPlay(count: 2)
        await manager.audioControlTask?.value
        #expect(manager.isAudioPlaying)
        #expect(await backend.time == 12)
        await manager.stopAndWait()
        #expect(await playback.value)
    }

    @Test("旧分段的延迟结束回调不得结束后续分段")
    func staleCompletionCannotFinishReplacement() async {
        let backend = TTSPlaybackStub()
        let manager = makeManager(backend)
        let first = start(manager)
        await backend.waitForPlay(count: 1)
        let oldCompletion = await backend.completion
        await manager.stopAndWait(); _ = await first.value
        let second = start(manager)
        await backend.waitForPlay(count: 2)
        await manager.audioControlTask?.value
        oldCompletion?(true)
        #expect(manager.audioContinuation != nil); #expect(manager.playbackState.status == .playing)
        #expect(manager.isAudioPlaying)
        await backend.finish()
        #expect(!(await second.value))
        await manager.stopAndWait()
    }

    @Test("系统语音事件按当前语句识别，中断与暂停不得留下假播放状态")
    func systemAudioEventsRejectStaleUtterances() async {
        let manager = makeManager(TTSPlaybackStub())
        let first = AVSpeechUtterance(string: "first")
        let current = AVSpeechUtterance(string: "current")
        manager.isSpeaking = true
        manager.activeSpeechUtterance = current
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(current), isPlaying: true)
        #expect(manager.isAudioPlaying)
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(first), isPlaying: false)
        #expect(manager.isAudioPlaying)

        manager.setAudioSessionInterrupted(true)
        #expect(!manager.isAudioPlaying)
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(current), isPlaying: true)
        #expect(!manager.isAudioPlaying)
        manager.setAudioMediaServicesAvailable(false)
        manager.setAudioMediaServicesAvailable(true)
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(current), isPlaying: true)
        #expect(!manager.isAudioPlaying)
        manager.setAudioSessionInterrupted(false)
        #expect(!manager.isAudioPlaying)
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(current), isPlaying: true)
        #expect(manager.isAudioPlaying)
        manager.handleSpeechPlaybackState(utteranceID: ObjectIdentifier(current), isPlaying: false)
        #expect(!manager.isAudioPlaying)
        // Only exercise event handling; no synthesizer or audio device is started.
        manager.activeSpeechUtterance = nil
        await manager.stopAndWait()
    }

    @Test("当前播放器停止的快照清除覆盖，旧播放器快照不影响新播放器")
    func actualAudioSnapshotRejectsStalePlayback() async {
        let backend = TTSPlaybackStub()
        let manager = makeManager(backend)
        let playback = start(manager)
        await backend.waitForPlay(count: 1)
        await manager.audioControlTask?.value
        let currentID = manager.audioPlaybackID
        let originalRevision = manager.audioPlaybackActivityRevision
        manager.updateCloudPlaybackPosition(
            .init(time: 1, duration: 30, isPlaying: false), id: UUID(), revision: originalRevision
        )
        #expect(manager.isAudioPlaying)
        manager.updateCloudPlaybackPosition(
            .init(time: 1, duration: 30, isPlaying: false), id: currentID, revision: originalRevision
        )
        #expect(!manager.isAudioPlaying)
        manager.pause()
        await manager.audioControlTask?.value
        manager.resume()
        await backend.waitForPlay(count: 2)
        await manager.audioControlTask?.value
        #expect(manager.isAudioPlaying)
        manager.updateCloudPlaybackPosition(
            .init(time: 1, duration: 30, isPlaying: false), id: currentID, revision: originalRevision
        )
        #expect(manager.isAudioPlaying)
        manager.finishCloudPlayback(id: currentID, error: TTSCloudAudioError.start, revision: originalRevision)
        #expect(manager.audioContinuation != nil)
        #expect(manager.isAudioPlaying)
        let preInterruptionRevision = manager.audioPlaybackActivityRevision
        manager.setAudioSessionInterrupted(true)
        manager.setAudioSessionInterrupted(false)
        manager.updateCloudPlaybackPosition(
            .init(time: 1, duration: 30, isPlaying: true), id: currentID, revision: preInterruptionRevision
        )
        #expect(!manager.isAudioPlaying)
        await manager.stopAndWait()
        #expect(await playback.value)
    }

    @Test("清除历史同时释放朗读请求和内存导出，普通停止保留重播请求")
    func explicitHistoryClearing() async {
        let manager = makeManager(TTSPlaybackStub())
        manager.lastReplayRequest = .init(messageID: UUID(), text: "待重播内容", playbackModeOverride: nil,
            serviceOverride: nil, settingsOverride: nil)
        manager.cachedNetworkAudioExport = TTSAudioExport(data: Data([1]), fileExtension: "wav")
        await manager.stopAndWait()
        #expect(manager.canReplayLastRequest); #expect(manager.canExportLastNetworkAudio)
        await manager.stopAndWait(clearHistory: true)
        #expect(!manager.canReplayLastRequest); #expect(!manager.canExportLastNetworkAudio)
    }

    @Test("取消预取后等待其真正返回，不能只清空任务字典就开始恢复数据库")
    func stopDrainsPrefetch() async {
        let manager = makeManager(TTSPlaybackStub()), gate = TTSPrefetchGate()
        let prefetch = Task<TTSManager.AudioClip, Error> {
            await withTaskCancellationHandler { await gate.wait() } onCancel: {
                Task { await gate.cancelled() }
            }
            return .init(data: Data([1]), format: "wav", sampleRate: nil)
        }
        manager.prefetchTasks[UUID()] = prefetch
        await gate.waitUntilStarted()
        var drained = false
        let stop = Task { await manager.stopAndWait(); drained = true }
        await gate.waitUntilCancelled()
        #expect(!drained); #expect(prefetch.isCancelled); #expect(manager.prefetchTasks.isEmpty)
        await gate.release()
        await stop.value
        #expect(drained)
    }

    private func makeManager(_ backend: TTSPlaybackStub) -> TTSManager {
        TTSManager(urlSession: .shared, settingsProvider: { .defaultValue }, serviceProvider: { nil }, makeAudioPlayback: { backend })
    }

    /// 直接使用假后端，测试不访问系统语音、音频设备、网络或真实配置数据库。
    private func start(_ manager: TTSManager) -> Task<Bool, Never> {
        manager.isSpeaking = true
        let playback = Task { () -> Bool in
            do {
                try await manager.playAudio(clip: .init(data: Data([1]), format: "wav", sampleRate: nil), speed: 1)
                return false
            } catch { return error is CancellationError }
        }
        // workerTask 的生产实现直接持有 processQueue；此处把取消也传递到假播放任务。
        manager.workerTask = Task {
            await withTaskCancellationHandler { _ = await playback.value } onCancel: { playback.cancel() }
        }
        return playback
    }
}

private actor TTSPrefetchGate {
    private var started = false
    private var didCancel = false
    private var gate: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var cancelWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true; startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { gate = $0 }
    }
    func cancelled() { didCancel = true; cancelWaiter?.resume(); cancelWaiter = nil }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { startWaiter = $0 } } }
    func waitUntilCancelled() async { if !didCancel { await withCheckedContinuation { cancelWaiter = $0 } } }
    func release() { gate?.resume(); gate = nil }
}

private actor TTSPlaybackStub: TTSCloudAudioPlayback {
    let suspendsPreparation: Bool
    let failsPlayback: Bool
    var completion: (@MainActor @Sendable (Bool) -> Void)?
    var playCount = 0
    var stopCount = 0
    var time: TimeInterval = 0
    var speed: Float = 1
    var isPlaying = false
    private var prepared = false
    private var preparationGate: CheckedContinuation<Void, Never>?
    private var preparationWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var playWaiter: (Int, CheckedContinuation<Void, Never>)?

    init(suspendsPreparation: Bool = false, failsPlayback: Bool = false) {
        self.suspendsPreparation = suspendsPreparation
        self.failsPlayback = failsPlayback
    }

    func prepare(clip: TTSManager.AudioClip, speed: Float, onFinish: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> TimeInterval {
        completion = onFinish; self.speed = speed; prepared = true
        preparationWaiter?.resume(); preparationWaiter = nil
        if suspendsPreparation { await withCheckedContinuation { preparationGate = $0 } }
        return 30
    }
    func play() throws {
        try Task.checkCancellation()
        if failsPlayback { throw TTSCloudAudioError.start }
        isPlaying = true
        playCount += 1
        if let (count, waiter) = playWaiter, playCount >= count { playWaiter = nil; waiter.resume() }
    }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) { self.time = time }
    func setSpeed(_ speed: Float) { self.speed = speed }
    func position() -> TTSCloudAudioPosition { .init(time: time, duration: 30, isPlaying: isPlaying) }
    func stop() { isPlaying = false; stopCount += 1; stopWaiter?.resume(); stopWaiter = nil }
    func finish() async { isPlaying = false; await completion?(true) }
    func waitForPreparation() async {
        if !prepared { await withCheckedContinuation { preparationWaiter = $0 } }
    }
    func releasePreparation() { preparationGate?.resume(); preparationGate = nil }
    func waitForStop() async {
        if stopCount == 0 { await withCheckedContinuation { stopWaiter = $0 } }
    }
    func waitForPlay(count: Int) async {
        if playCount < count { await withCheckedContinuation { playWaiter = (count, $0) } }
    }
}
