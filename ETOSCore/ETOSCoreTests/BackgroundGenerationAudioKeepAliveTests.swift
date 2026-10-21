import Foundation
import Testing
@testable import ETOSCore
#if canImport(AVFoundation)
import AVFoundation
#endif

@Suite("后台生成音频保活测试")
struct BackgroundGenerationAudioKeepAliveTests {
    @Test("音频保活默认关闭且音量限制在可听范围")
    func defaultsAndVolumeBounds() {
        #expect(AppConfigKey.backgroundGenerationAudioKeepAliveEnabled.defaultValue == .bool(false))
        #expect(
            AppConfigKey.backgroundGenerationAudioKeepAliveVolume.defaultValue
                == .real(BackgroundGenerationAudioKeepAliveSettings.defaultVolume)
        )
        #expect(
            BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(0)
                == BackgroundGenerationAudioKeepAliveSettings.minimumVolume
        )
        #expect(
            BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(2)
                == BackgroundGenerationAudioKeepAliveSettings.maximumVolume
        )
    }

    @Test("等待音数据包含完整的循环 WAV")
    func buildsLoopingWAVData() {
        let data = BackgroundGenerationWaitAudioFactory.makeWAVData()
        let expectedPCMByteCount = Int(
            Double(BackgroundGenerationWaitAudioFactory.sampleRate)
                * BackgroundGenerationWaitAudioFactory.duration
        ) * MemoryLayout<Int16>.size

        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE")
        #expect(data.count == 44 + expectedPCMByteCount)
    }
}

#if os(iOS) || os(watchOS)
@MainActor
@Suite("等待音实际播放状态")
struct BackgroundGenerationAudioPlaybackTests {
    @Test("播放失败会清除先前的播放状态")
    func failedRestartClearsPlayingState() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        #expect(fixture.manager.isPlaying)

        fixture.player.isPlaying = false
        fixture.player.canPlay = false
        fixture.manager.setGenerationActive(true)

        #expect(!fixture.manager.isPlaying)
        #expect(fixture.manager.hasPlaybackError)
        #expect(fixture.deactivationCount == 1)
    }

    @Test("播放接口返回成功但播放器未运行时不能报告保活")
    func successfulStartWithoutPlaybackIsInactive() async throws {
        let fixture = PlaybackFixture()
        fixture.player.startsWithoutPlayback = true
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        #expect(!fixture.manager.isPlaying)
        #expect(fixture.manager.hasPlaybackError)
    }

    @Test("准备或音频会话失败时不能报告正在播放", arguments: [false, true])
    func setupFailureStaysInactive(_ failPreparation: Bool) async throws {
        let fixture = PlaybackFixture()
        fixture.failPreparation = failPreparation
        fixture.failActivation = !failPreparation
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        #expect(!fixture.manager.isPlaying)
        #expect(fixture.manager.hasPlaybackError)
    }

    @Test("朗读暂停等待音，朗读结束后恢复实际播放")
    func speechHandoffReportsNoWaitingAudio() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()

        fixture.isSpeaking = true
        fixture.manager.setGenerationActive(true)
        #expect(!fixture.manager.isPlaying)
        #expect(!fixture.player.isPlaying)
        #expect(fixture.deactivationCount == 0)

        fixture.isSpeaking = false
        fixture.manager.setGenerationActive(true)
        #expect(fixture.manager.isPlaying)
        fixture.manager.setGenerationActive(false)
        #expect(!fixture.manager.isPlaying)
    }

    @Test("音频中断清除播放状态，系统允许后才自动恢复")
    func interruptionClearsPlayingState() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()

        fixture.manager.handleInterruption(.began, shouldResume: false)
        #expect(!fixture.manager.isPlaying)
        #expect(!fixture.player.isPlaying)
        #expect(fixture.deactivationCount == 0)
        fixture.manager.setGenerationActive(true)
        #expect(!fixture.manager.isPlaying)

        fixture.manager.handleInterruption(.ended, shouldResume: true)
        #expect(fixture.manager.isPlaying)
    }

    @Test("中断结束不允许自动恢复时保持停止")
    func interruptionWithoutResumePermissionStaysStopped() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        fixture.manager.handleInterruption(.began, shouldResume: false)
        fixture.manager.handleInterruption(.ended, shouldResume: false)
        #expect(!fixture.manager.isPlaying)
    }

    @Test("结束和解码错误都清除播放状态", arguments: [false, true])
    func completionClearsPlayingState(_ successful: Bool) async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        fixture.player.finish(successfully: successful)
        #expect(!fixture.manager.isPlaying)
        #expect(fixture.manager.hasPlaybackError == !successful)
    }

    @Test("重建播放器后忽略旧播放器的迟到回调")
    func mediaResetRebuildsAndIgnoresStaleCallback() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        let oldCompletion = try #require(fixture.player.onPlaybackEnded)
        let replacement = TestWaitingAudioPlayer()
        fixture.nextPlayer = replacement

        fixture.manager.handleMediaServicesReset()
        try await fixture.waitForPreparation()
        #expect(fixture.manager.isPlaying)
        #expect(replacement.isPlaying)

        oldCompletion(false)
        #expect(fixture.manager.isPlaying)
        #expect(!fixture.manager.hasPlaybackError)
    }

    @Test("媒体服务丢失时停止报告播放，重置后恢复仍被授权的等待音")
    func mediaServicesLossPreservesIntentUntilReset() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        let oldCompletion = try #require(fixture.player.onPlaybackEnded)
        let replacement = TestWaitingAudioPlayer()
        fixture.nextPlayer = replacement

        fixture.manager.handleMediaServicesLost()
        #expect(!fixture.manager.isPlaying)
        #expect(fixture.manager.isGenerationActive)
        #expect(fixture.deactivationCount == 0)
        fixture.manager.setGenerationActive(true)
        #expect(!fixture.manager.isPlaying)
        #expect(!replacement.isPlaying)

        fixture.manager.handleMediaServicesReset()
        try await fixture.waitForPreparation()
        #expect(fixture.manager.isPlaying)
        #expect(replacement.isPlaying)
        oldCompletion(false)
        #expect(fixture.manager.isPlaying)
        #expect(!fixture.manager.hasPlaybackError)
    }

    @Test("停止后忽略迟到的播放错误")
    func stopInvalidatesCallback() async throws {
        let fixture = PlaybackFixture()
        fixture.manager.setGenerationActive(true)
        try await fixture.waitForPreparation()
        let completion = try #require(fixture.player.onPlaybackEnded)
        fixture.manager.setGenerationActive(false)
        completion(false)
        #expect(!fixture.manager.isPlaying)
        #expect(!fixture.manager.hasPlaybackError)
    }
}

@MainActor
private final class PlaybackFixture {
    let player = TestWaitingAudioPlayer()
    let notifications = NotificationCenter()
    var nextPlayer: TestWaitingAudioPlayer?
    var isSpeaking = false
    var isEnabled = true
    var volume = 0.2
    var deactivationCount = 0
    var failPreparation = false
    var failActivation = false

    lazy var manager = BackgroundGenerationAudioKeepAliveManager(
        featureEnabled: { [unowned self] in isEnabled },
        updateFeatureEnabled: { [unowned self] in isEnabled = $0 },
        volume: { [unowned self] in volume },
        updateVolume: { [unowned self] in volume = $0 },
        isSpeechActive: { [unowned self] in isSpeaking },
        playerFactory: { [unowned self] _ in
            if failPreparation { throw TestPlaybackError.failure }
            return nextPlayer ?? player
        },
        activateSession: { [unowned self] in
            if failActivation { throw TestPlaybackError.failure }
        },
        deactivateSession: { [unowned self] in deactivationCount += 1 },
        notificationCenter: notifications
    )

    func waitForPreparation() async throws {
        let deadline = Date().addingTimeInterval(5)
        while manager.isPreparing && Date() < deadline {
            await Task.yield()
        }
        try #require(!manager.isPreparing)
    }

}

@MainActor
private final class TestWaitingAudioPlayer: BackgroundGenerationAudioPlayback {
    var isPlaying = false
    var canPlay = true
    var startsWithoutPlayback = false
    var volume: Float = 0
    var onPlaybackEnded: (@MainActor @Sendable (Bool) -> Void)?

    func play() -> Bool { isPlaying = canPlay && !startsWithoutPlayback; return canPlay }
    func pause() { isPlaying = false }
    func stop(resetPosition: Bool) { isPlaying = false }
    func finish(successfully: Bool) {
        isPlaying = false
        onPlaybackEnded?(successfully)
    }
}

private enum TestPlaybackError: Error { case failure }
#endif
