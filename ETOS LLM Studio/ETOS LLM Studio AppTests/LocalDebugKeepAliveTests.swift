import AVFoundation
import Combine
import ETOSCore
import Testing
@testable import ETOS_LLM_Studio_App

@Suite("远程文件访问后台音频保活")
@MainActor
struct LocalDebugKeepAliveTests {
    @Test("仅在连接和用户授权同时存在时播放，断开后立即停止")
    func requiresConnectionAndOptIn() {
        let playback = TestPlayback()
        let keepAlive = LocalDebugKeepAlive(playback: playback)

        keepAlive.update(isConnected: false, enabled: true)
        #expect(!keepAlive.isActive)
        keepAlive.update(isConnected: true, enabled: false)
        #expect(!keepAlive.isActive)
        #expect(playback.startCount == 0)

        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.isActive)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(playback.startCount == 1)

        keepAlive.update(isConnected: false, enabled: true)
        #expect(!keepAlive.isActive)
        #expect(!playback.isPlaying)
    }

    @Test("关闭开关或离开页面后不能被音频恢复事件重新启动")
    func stopRevokesPlaybackIntent() {
        let playback = TestPlayback()
        let keepAlive = LocalDebugKeepAlive(playback: playback)
        keepAlive.update(isConnected: true, enabled: true)
        keepAlive.stop()
        keepAlive.handleInterruption(.ended, shouldResume: true)
        #expect(!keepAlive.isActive)
        #expect(playback.startCount == 1)

        keepAlive.update(isConnected: true, enabled: true)
        keepAlive.update(isConnected: true, enabled: false)
        keepAlive.handleInterruption(.ended, shouldResume: true)
        #expect(!keepAlive.isActive)
        #expect(playback.startCount == 2)
    }

    @Test("交出音频给朗读或生成音时不关闭共享会话")
    func yieldsWithoutDeactivatingOtherAudio() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy }
        )
        keepAlive.update(isConnected: true, enabled: true)
        activity.isBusy = true
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive)
        #expect(playback.lastDeactivationRequest == false)

        keepAlive.stop()
        #expect(playback.lastDeactivationRequest == false)
        activity.isBusy = false
        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.isActive)
    }

    @Test("朗读缓冲会让出音频，但不代表已有后台音频覆盖")
    func bufferingYieldsWithoutClaimingBackgroundCoverage() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        activity.isBusy = true
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )

        keepAlive.update(isConnected: true, enabled: true)

        #expect(!keepAlive.isActive && !keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 0)
        #expect(playback.lastDeactivationRequest == false)
    }

    @Test("实际朗读或等待音覆盖后台，无需启动未授权的静音播放")
    func otherAudioCoversConnectionWithSilentPlaybackDisabled() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )

        keepAlive.update(isConnected: true, enabled: false)

        #expect(!keepAlive.isActive && keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 0)
        #expect(playback.lastDeactivationRequest == false)
    }

    @Test("其他音频结束后恢复静音播放，覆盖状态不会中途变为无覆盖")
    func audioHandoffKeepsCoverageUntilSilentPlaybackResumes() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        var coverageChanges: [Bool] = []
        let observation = keepAlive.$hasBackgroundAudioCoverage
            .removeDuplicates()
            .sink { coverageChanges.append($0) }
        defer { observation.cancel() }
        keepAlive.update(isConnected: true, enabled: true)

        activity.isBusy = true
        activity.hasBackgroundAudio = true
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive && keepAlive.hasBackgroundAudioCoverage)

        activity.isBusy = false
        activity.hasBackgroundAudio = false
        keepAlive.update(isConnected: true, enabled: true)

        #expect(keepAlive.isActive && keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 2)
        #expect(coverageChanges == [false, true])
    }

    @Test("其他音频结束且静音恢复失败时清除后台覆盖")
    func failedSilentRestartClearsOtherAudioCoverage() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.hasBackgroundAudioCoverage)

        activity.isBusy = false
        activity.hasBackgroundAudio = false
        playback.failsToStart = true
        keepAlive.update(isConnected: true, enabled: true)

        #expect(!keepAlive.isActive && !keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 1)
    }

    @Test("系统中断立即清除其他音频覆盖，不能由过期播放标记恢复")
    func interruptionClearsCoverageDespiteOtherAudioFlag() {
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: TestPlayback(),
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.hasBackgroundAudioCoverage)

        keepAlive.handleInterruption(.began, shouldResume: false)
        #expect(!keepAlive.hasBackgroundAudioCoverage)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive && !keepAlive.hasBackgroundAudioCoverage)
    }

    @Test("用户停止连接后其他音频不能恢复覆盖或静音播放")
    func stoppingConnectionRevokesCoverageDuringOtherAudio() {
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.hasBackgroundAudioCoverage)

        keepAlive.stop()
        keepAlive.handleInterruption(.ended, shouldResume: true)

        #expect(!keepAlive.isActive && !keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 0)
        #expect(playback.lastDeactivationRequest == false)
    }

    @Test("后台租约到期时真实的其他音频仍可保护诊断连接")
    func leaseExpiryPreservesConnectionCoveredByOtherAudio() {
        let server = LocalDebugServer()
        server.isRunning = true
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: TestPlayback(),
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        keepAlive.update(isConnected: true, enabled: true)
        let lease = ApplicationBackgroundTaskLease(name: "local-debug-test") {
            keepAlive.update(isConnected: server.isRunning, enabled: true)
            if !keepAlive.hasBackgroundAudioCoverage {
                server.suspendForBackground()
            }
        }

        lease.expire()

        #expect(server.isRunning && keepAlive.hasBackgroundAudioCoverage)
        #expect(!keepAlive.isActive)
        server.disconnect()
        keepAlive.stop()
    }

    @Test("后台租约到期先刷新音频，不能沿用已经结束的其他音频覆盖")
    func leaseExpiryRefreshesEndedAudioBeforeSuspending() {
        let server = LocalDebugServer()
        server.isRunning = true
        let playback = TestPlayback()
        let activity = TestAudioActivity()
        activity.isBusy = true
        activity.hasBackgroundAudio = true
        let keepAlive = LocalDebugKeepAlive(
            playback: playback,
            hasOtherAudio: { activity.isBusy },
            hasOtherBackgroundAudio: { activity.hasBackgroundAudio }
        )
        keepAlive.update(isConnected: true, enabled: true)
        let lease = ApplicationBackgroundTaskLease(name: "local-debug-test") {
            keepAlive.update(isConnected: server.isRunning, enabled: true)
            if !keepAlive.hasBackgroundAudioCoverage {
                server.suspendForBackground()
            }
        }
        // Simulate another owner ending before its queued publisher refresh runs.
        activity.isBusy = false
        activity.hasBackgroundAudio = false
        playback.failsToStart = true

        lease.expire()

        #expect(!server.isRunning && !keepAlive.hasBackgroundAudioCoverage)
        #expect(playback.startCount == 1)
        server.disconnect()
        keepAlive.stop()
    }

    @Test("音频中断只在系统允许且用户仍授权时恢复")
    func interruptionRequiresResumePermission() {
        let playback = TestPlayback()
        let keepAlive = LocalDebugKeepAlive(playback: playback)
        keepAlive.update(isConnected: true, enabled: true)
        keepAlive.handleInterruption(.began, shouldResume: false)
        #expect(!keepAlive.isActive)
        #expect(playback.lastDeactivationRequest == false)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive)

        keepAlive.handleInterruption(.ended, shouldResume: false)
        #expect(!keepAlive.isActive)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(keepAlive.isActive)
    }

    @Test("系统允许时只恢复仍被授权的连接")
    func allowedInterruptionResumeRestartsActiveConnection() {
        let playback = TestPlayback()
        let keepAlive = LocalDebugKeepAlive(playback: playback)
        keepAlive.update(isConnected: true, enabled: true)
        keepAlive.handleInterruption(.began, shouldResume: false)
        #expect(!keepAlive.isActive)
        keepAlive.handleInterruption(.ended, shouldResume: true)
        #expect(keepAlive.isActive)
        #expect(playback.startCount == 2)
    }

    @Test("音频启动失败不得报告保活成功")
    func playbackFailureLeavesKeepAliveInactive() {
        let playback = TestPlayback()
        playback.failsToStart = true
        let keepAlive = LocalDebugKeepAlive(playback: playback)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive)
        #expect(!playback.isPlaying)
    }

    @Test("未实际开始播放时释放音频会话")
    func inactivePlaybackIsCleanedUp() {
        let playback = TestPlayback()
        playback.startsWithoutPlayback = true
        let keepAlive = LocalDebugKeepAlive(playback: playback)
        keepAlive.update(isConnected: true, enabled: true)
        #expect(!keepAlive.isActive)
        #expect(playback.lastDeactivationRequest == true)
    }

    @Test("循环音频缓冲区只包含零样本")
    func silenceBufferContainsNoAudibleSamples() throws {
        let buffer = try LocalDebugSilentAudioPlayback.makeSilenceBuffer()
        #expect(buffer.frameLength > 0)
        #expect(buffer.frameLength == buffer.frameCapacity)
        let samples = try #require(buffer.floatChannelData)
        for channel in 0..<Int(buffer.format.channelCount) {
            #expect((0..<Int(buffer.frameLength)).allSatisfy { samples[channel][$0] == 0 })
        }
    }
}

@MainActor
private final class TestAudioActivity {
    var isBusy = false
    var hasBackgroundAudio = false
}

@MainActor
private final class TestPlayback: LocalDebugKeepAlivePlayback {
    var isPlaying = false
    var startCount = 0
    var failsToStart = false
    var startsWithoutPlayback = false
    var lastDeactivationRequest: Bool?

    func start() throws {
        startCount += 1
        if failsToStart { throw TestFailure.start }
        isPlaying = !startsWithoutPlayback
    }

    func stop(deactivateSession: Bool) {
        isPlaying = false
        lastDeactivationRequest = deactivateSession
    }

    private enum TestFailure: Error {
        case start
    }
}
