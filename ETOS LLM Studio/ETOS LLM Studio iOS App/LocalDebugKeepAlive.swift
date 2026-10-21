// ============================================================================
// LocalDebugKeepAlive.swift
// ETOS LLM Studio
//
// 用户主动开启后，仅在远程文件访问连接期间播放静音缓冲区。
// 音频中断、朗读和生成等待音优先；保活失败不会被报告为仍在运行。
// ============================================================================

#if os(iOS)
import AVFoundation
import Combine
import ETOSCore
import Foundation

@MainActor
protocol LocalDebugKeepAlivePlayback: AnyObject {
    var isPlaying: Bool { get }
    func start() throws
    func stop(deactivateSession: Bool)
}

@MainActor
final class LocalDebugKeepAlive: ObservableObject {
    @Published private(set) var isActive = false

    private let playback: any LocalDebugKeepAlivePlayback
    private let hasOtherAudio: () -> Bool
    private var isConnected = false
    private var isEnabled = false
    private var isInterrupted = false
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        let tts = TTSManager.shared
        let generationAudio = BackgroundGenerationAudioKeepAliveManager.shared
        self.init(
            playback: LocalDebugSilentAudioPlayback(),
            hasOtherAudio: { tts.isSpeaking || generationAudio.isPlaying }
        )

        tts.$isSpeaking
            .combineLatest(generationAudio.$isPlaying)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPlayback()
                }
            }
            .store(in: &cancellables)
    }

    init(
        playback: any LocalDebugKeepAlivePlayback,
        hasOtherAudio: @escaping () -> Bool = { false },
        notificationCenter: NotificationCenter = .default
    ) {
        self.playback = playback
        self.hasOtherAudio = hasOtherAudio

        notificationCenter.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                let options = AVAudioSession.InterruptionOptions(
                    rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                )
                Task { @MainActor [weak self] in
                    self?.handleInterruption(type, shouldResume: options.contains(.shouldResume))
                }
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stopPlayback(deactivateSession: false)
                    self.refreshPlayback()
                }
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: .AVAudioEngineConfigurationChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive, !self.playback.isPlaying else { return }
                    // 路由或共享会话改变后，交由页面的后台租约处理真正停止的引擎。
                    self.stopPlayback(deactivateSession: false)
                }
            }
            .store(in: &cancellables)
    }

    func update(isConnected: Bool, enabled: Bool) {
        self.isConnected = isConnected
        isEnabled = enabled
        refreshPlayback()
    }

    func stop() {
        isConnected = false
        isEnabled = false
        refreshPlayback()
    }

    func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            isInterrupted = true
            stopPlayback(deactivateSession: false)
        case .ended:
            isInterrupted = false
            if shouldResume {
                refreshPlayback()
            }
        @unknown default:
            isInterrupted = true
            stopPlayback(deactivateSession: false)
        }
    }

    private func refreshPlayback() {
        let otherAudioIsActive = hasOtherAudio()
        guard isConnected, isEnabled, !isInterrupted, !otherAudioIsActive else {
            // 与等待音的 pauseForSpeech 一致：只停止本播放器，不能关闭刚被朗读接管的会话。
            stopPlayback(deactivateSession: !isInterrupted && !otherAudioIsActive)
            return
        }
        guard !playback.isPlaying else {
            isActive = true
            return
        }
        do {
            try playback.start()
            guard playback.isPlaying else {
                stopPlayback(deactivateSession: true)
                return
            }
            isActive = true
        } catch {
            stopPlayback(deactivateSession: true)
        }
    }

    private func stopPlayback(deactivateSession: Bool) {
        playback.stop(deactivateSession: deactivateSession)
        isActive = false
    }
}

@MainActor
final class LocalDebugSilentAudioPlayback: LocalDebugKeepAlivePlayback {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var ownsAudioSession = false

    var isPlaying: Bool {
        engine?.isRunning == true && player?.isPlaying == true
    }

    static func makeSilenceBuffer() throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let channels = buffer.floatChannelData else {
            throw PlaybackError.bufferUnavailable
        }
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
        }
        return buffer
    }

    func start() throws {
        guard !isPlaying else { return }
        let buffer = try Self.makeSilenceBuffer()
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
        ownsAudioSession = true

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        self.engine = engine
        self.player = player
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop(deactivateSession: Bool) {
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        defer { ownsAudioSession = false }
        guard ownsAudioSession, deactivateSession else { return }
        let session = AVAudioSession.sharedInstance()
        // TTS 或录音可能已更改共享会话；不能停用另一位使用者的会话。
        guard session.category == .playback,
              session.mode == .default,
              session.categoryOptions.contains(.mixWithOthers) else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum PlaybackError: Error {
        case bufferUnavailable
    }
}
#endif
