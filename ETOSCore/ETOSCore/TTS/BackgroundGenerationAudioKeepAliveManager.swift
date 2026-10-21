// ============================================================================
// BackgroundGenerationAudioKeepAliveManager.swift
// ============================================================================
// ETOS LLM Studio
//
// 在用户主动启用后，于回复生成期间循环播放可听的轻柔等待音。
// 回复朗读开始时自动暂停，避免等待音与语音内容叠加。
// ============================================================================

import Combine
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

enum BackgroundGenerationWaitAudioFactory {
    static let sampleRate = 22_050
    static let duration: TimeInterval = 4

    nonisolated static func makeWAVData() -> Data {
        let frameCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        var randomState: UInt64 = 0x7A6D_91C3_4E28_B5F1
        var smoothedNoise = 0.0

        for frame in 0..<frameCount {
            randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
            let randomUnit = Double((randomState >> 32) & 0xFFFF) / Double(UInt16.max)
            let whiteNoise = randomUnit * 2 - 1
            smoothedNoise = smoothedNoise * 0.965 + whiteNoise * 0.035

            let time = Double(frame) / Double(sampleRate)
            let edgeFade = min(1, min(time / 0.18, (duration - time) / 0.18))
            let breathingEnvelope = 0.72 + 0.28 * sin(.pi * time / duration)
            let sampleValue = smoothedNoise * 0.42 * max(0, edgeFade) * breathingEnvelope
            let integerSample = Int16(
                (sampleValue * Double(Int16.max))
                    .rounded()
                    .clamped(to: Double(Int16.min)...Double(Int16.max))
            )
            pcm.appendLittleEndian(integerSample)
        }

        return makeWAVContainer(pcm: pcm, sampleRate: sampleRate)
    }

    private nonisolated static func makeWAVContainer(pcm: Data, sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8

        var data = Data(capacity: pcm.count + 44)
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        data.appendLittleEndian(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

@MainActor
protocol BackgroundGenerationAudioPlayback: AnyObject {
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var onPlaybackEnded: (@MainActor @Sendable (Bool) -> Void)? { get set }
    func play() -> Bool
    func pause()
    func stop(resetPosition: Bool)
}

@MainActor
public final class BackgroundGenerationAudioKeepAliveManager: ObservableObject {
    public static let shared = BackgroundGenerationAudioKeepAliveManager()

    @Published public private(set) var isGenerationActive = false
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isPreparing = false
    @Published public private(set) var isPreviewing = false
    @Published public private(set) var hasPlaybackError = false

    private let featureEnabled: @MainActor () -> Bool
    private let updateFeatureEnabled: @MainActor (Bool) -> Void
    private let volume: @MainActor () -> Double
    private let updateVolume: @MainActor (Double) -> Void
    private let isSpeechActive: @MainActor () -> Bool
    private let playerFactory: @MainActor (Data) throws -> any BackgroundGenerationAudioPlayback
    private let activateSession: @MainActor () throws -> Void
    private let deactivateSession: @MainActor () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var preparationTask: Task<Void, Never>?
    private var preparationID: UUID?
    private var playbackID: UUID?
    private var previewTask: Task<Void, Never>?
    private var ownsAudioSession = false
    private var isInterrupted = false
    private var mediaServicesAvailable = true
    private var audioPlayer: (any BackgroundGenerationAudioPlayback)?

    public convenience init(
        appConfig: AppConfigStore? = nil,
        ttsManager: TTSManager? = nil
    ) {
        let appConfig = appConfig ?? .shared
        let ttsManager = ttsManager ?? .shared
        self.init(
            featureEnabled: { appConfig.backgroundGenerationAudioKeepAliveEnabled },
            updateFeatureEnabled: { appConfig.backgroundGenerationAudioKeepAliveEnabled = $0 },
            volume: { appConfig.backgroundGenerationAudioKeepAliveVolume },
            updateVolume: { appConfig.backgroundGenerationAudioKeepAliveVolume = $0 },
            isSpeechActive: { ttsManager.isSpeaking },
            playerFactory: Self.makePlayer,
            activateSession: Self.activateAudioSession,
            deactivateSession: Self.deactivateAudioSession
        )

        ttsManager.$isSpeaking
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePlayback()
                }
            }
            .store(in: &cancellables)

        appConfig.$backgroundGenerationAudioKeepAliveEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePlayback()
                }
            }
            .store(in: &cancellables)

        appConfig.$backgroundGenerationAudioKeepAliveVolume
            .removeDuplicates()
            .sink { [weak self] volume in
                Task { @MainActor [weak self] in
                    self?.applyVolume(volume)
                }
            }
            .store(in: &cancellables)
    }

    init(
        featureEnabled: @escaping @MainActor () -> Bool,
        updateFeatureEnabled: @escaping @MainActor (Bool) -> Void,
        volume: @escaping @MainActor () -> Double,
        updateVolume: @escaping @MainActor (Double) -> Void,
        isSpeechActive: @escaping @MainActor () -> Bool,
        playerFactory: @escaping @MainActor (Data) throws -> any BackgroundGenerationAudioPlayback,
        activateSession: @escaping @MainActor () throws -> Void,
        deactivateSession: @escaping @MainActor () -> Void,
        notificationCenter: NotificationCenter = .default
    ) {
        self.featureEnabled = featureEnabled
        self.updateFeatureEnabled = updateFeatureEnabled
        self.volume = volume
        self.updateVolume = updateVolume
        self.isSpeechActive = isSpeechActive
        self.playerFactory = playerFactory
        self.activateSession = activateSession
        self.deactivateSession = deactivateSession
#if os(iOS) || os(watchOS)
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
                Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereLostNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleMediaServicesLost() }
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying, self.audioPlayer?.isPlaying != true else { return }
                    self.stopPlayback(resetPosition: false)
                }
            }
            .store(in: &cancellables)
#endif
    }

    public func setFeatureEnabled(_ enabled: Bool) {
        if enabled {
            hasPlaybackError = false
        }
        updateFeatureEnabled(enabled)
        if enabled {
            preparePlayerIfNeeded()
            updatePlayback()
        } else {
            stopPreview()
        }
    }

    public func setGenerationActive(_ active: Bool) {
        guard isGenerationActive != active else {
            updatePlayback()
            return
        }
        isGenerationActive = active
        updatePlayback()
    }

    public func setVolume(_ volume: Double) {
        updateVolume(BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(volume))
    }

    public func togglePreview() {
        if isPreviewing {
            stopPreview()
            return
        }

        previewTask?.cancel()
        hasPlaybackError = false
        isPreviewing = true
        updatePlayback()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isPreviewing = false
            self.previewTask = nil
            self.updatePlayback()
        }
    }

    public func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        isPreviewing = false
        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlay = isPreviewing
            || (featureEnabled() && isGenerationActive)

        guard shouldPlay else {
            stopPlayback(resetPosition: true)
            return
        }

        guard mediaServicesAvailable, !isInterrupted, !isSpeechActive() else {
            pauseForSpeech()
            return
        }

        if audioPlayer == nil {
            guard !hasPlaybackError else { return }
            preparePlayerIfNeeded()
            return
        }
        startPlayback()
    }

    private func preparePlayerIfNeeded() {
        guard audioPlayer == nil, preparationTask == nil else { return }
        let id = UUID()
        preparationID = id
        isPreparing = true
        hasPlaybackError = false

        preparationTask = Task { @MainActor [weak self] in
            let data = await Task.detached(priority: .utility) {
                BackgroundGenerationWaitAudioFactory.makeWAVData()
            }.value
            guard let self, !Task.isCancelled, self.preparationID == id else { return }

            do {
                let player = try self.playerFactory(data)
                player.volume = Float(
                    BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(self.volume())
                )
                self.audioPlayer = player
            } catch {
                self.hasPlaybackError = true
                self.isPlaying = false
            }

            self.isPreparing = false
            self.preparationTask = nil
            self.preparationID = nil
            self.updatePlayback()
        }
    }

    private func startPlayback() {
        guard let audioPlayer, !audioPlayer.isPlaying else {
            isPlaying = audioPlayer?.isPlaying == true
            return
        }

        do {
            try activateSession()
            ownsAudioSession = true
            audioPlayer.volume = Float(
                BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(volume())
            )
            let id = UUID()
            playbackID = id
            audioPlayer.onPlaybackEnded = { [weak self] successful in
                guard let self, self.playbackID == id else { return }
                self.stopPlayback(resetPosition: true)
                self.hasPlaybackError = !successful
            }
            guard audioPlayer.play(), audioPlayer.isPlaying else {
                hasPlaybackError = true
                stopPlayback(resetPosition: true)
                return
            }
            hasPlaybackError = false
            isPlaying = true
        } catch {
            hasPlaybackError = true
            stopPlayback(resetPosition: true)
        }
    }

    private func stopPlayback(resetPosition: Bool) {
        playbackID = nil
        audioPlayer?.onPlaybackEnded = nil
        audioPlayer?.stop(resetPosition: resetPosition)
        isPlaying = false
        deactivateAudioSessionIfNeeded()
    }

    private func pauseForSpeech() {
        playbackID = nil
        audioPlayer?.onPlaybackEnded = nil
        audioPlayer?.pause()
        isPlaying = false
        // 朗读会立即接管共享音频会话，此处只暂停播放器，不能关闭朗读刚激活的会话。
        ownsAudioSession = false
    }

    private func applyVolume(_ volume: Double) {
        audioPlayer?.volume = Float(
            BackgroundGenerationAudioKeepAliveSettings.normalizedVolume(volume)
        )
    }

    func handleMediaServicesLost() {
        mediaServicesAvailable = false
        discardPlaybackForMediaServiceChange()
    }

    func handleMediaServicesReset() {
        discardPlaybackForMediaServiceChange()
        // Media-service loss is independent of an ongoing phone-call interruption.
        mediaServicesAvailable = true
        hasPlaybackError = false
        updatePlayback()
    }

    private func discardPlaybackForMediaServiceChange() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        isPreparing = false
        playbackID = nil
        audioPlayer?.onPlaybackEnded = nil
        audioPlayer?.stop(resetPosition: true)
        audioPlayer = nil
        isPlaying = false
        ownsAudioSession = false
    }

#if os(iOS) || os(watchOS)
    func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            isInterrupted = true
            pauseForSpeech()
        case .ended:
            isInterrupted = false
            if shouldResume { updatePlayback() }
        @unknown default:
            isInterrupted = true
            pauseForSpeech()
        }
    }
#endif

    private static func makePlayer(data: Data) throws -> any BackgroundGenerationAudioPlayback {
#if canImport(AVFoundation)
        return try BackgroundGenerationAudioPlayer(data: data)
#else
        throw CocoaError(.featureUnsupported)
#endif
    }

    private static func activateAudioSession() throws {
#if os(iOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
#if os(watchOS)
        try session.setCategory(
            .playback,
            mode: .default,
            policy: .longFormAudio,
            options: []
        )
#else
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
#endif
        try session.setActive(true)
#endif
    }

    private func deactivateAudioSessionIfNeeded() {
        guard ownsAudioSession else { return }
        deactivateSession()
        ownsAudioSession = false
    }

    private static func deactivateAudioSession() {
#if os(iOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}

#if canImport(AVFoundation)
@MainActor
private final class BackgroundGenerationAudioPlayer: BackgroundGenerationAudioPlayback {
    private let player: AVAudioPlayer
    private var delegate: BackgroundGenerationAudioPlayerDelegate?

    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        player.numberOfLoops = -1
        guard player.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
    }

    var isPlaying: Bool { player.isPlaying }
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var onPlaybackEnded: (@MainActor @Sendable (Bool) -> Void)? {
        didSet {
            if let onPlaybackEnded {
                delegate = BackgroundGenerationAudioPlayerDelegate(onFinish: onPlaybackEnded)
            } else {
                delegate = nil
            }
            player.delegate = delegate
        }
    }
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop(resetPosition: Bool) {
        if resetPosition { player.stop(); player.currentTime = 0 }
        else { player.pause() }
    }
}

private final class BackgroundGenerationAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @MainActor @Sendable (Bool) -> Void
    init(onFinish: @escaping @MainActor @Sendable (Bool) -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [onFinish] in onFinish(flag) }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [onFinish] in onFinish(false) }
    }
}
#endif

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
