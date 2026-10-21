import AVFoundation
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
