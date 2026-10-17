import Foundation

public struct RomaIOSAudioSessionRecordingConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playAndRecord
    }

    public enum Mode: String, Equatable, Sendable {
        case spokenAudio
    }

    public enum Option: String, Equatable, Sendable {
        case defaultToSpeaker
        case allowBluetooth
        case allowBluetoothA2DP
        case mixWithOthers
    }

    public let category: Category
    public let mode: Mode
    public let options: [Option]

    public init(category: Category, mode: Mode, options: [Option]) {
        self.category = category
        self.mode = mode
        self.options = options
    }

    public static let voiceRecording = Self(
        category: .playAndRecord,
        mode: .spokenAudio,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
    )
}

public struct RomaIOSAudioPlaybackSessionConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playback
    }

    public enum Mode: String, Equatable, Sendable {
        case spokenAudio
    }

    public let category: Category
    public let mode: Mode

    public init(category: Category, mode: Mode) {
        self.category = category
        self.mode = mode
    }

    public static let notePlayback = Self(category: .playback, mode: .spokenAudio)
}

public enum RomaAudioSessionDiagnostics {
    public static let activatedForRecordingMessage = "Audio session activated for recording"
    public static let activatedForPlaybackMessage = "Audio session activated for playback"
    public static let deactivatedMessage = "Audio session deactivated"

    public static func activationFailedMessage(localizedDescription: String, code: Int) -> String {
        "Audio session activation failed: \(localizedDescription) (code: \(code))"
    }

    public static func deactivationScheduledMessage(seconds: Int) -> String {
        "Audio session deactivation scheduled in \(seconds) seconds"
    }

    public static func deactivationFailedMessage(localizedDescription: String) -> String {
        "Failed to deactivate audio session: \(localizedDescription)"
    }
}

public struct RomaAudioSessionPlaybackActivationPlan: Equatable, Sendable {
    private let shouldCancelScheduledDeactivation: Bool
    private let shouldDeactivateCurrentSession: Bool

    fileprivate init(
        shouldCancelScheduledDeactivation: Bool,
        shouldDeactivateCurrentSession: Bool
    ) {
        self.shouldCancelScheduledDeactivation = shouldCancelScheduledDeactivation
        self.shouldDeactivateCurrentSession = shouldDeactivateCurrentSession
    }

    public func applyRuntimeState(
        cancelScheduledDeactivation: () -> Void,
        deactivateCurrentSession: () throws -> Void,
        markDeactivated: () -> Void
    ) throws {
        if shouldCancelScheduledDeactivation {
            cancelScheduledDeactivation()
        }

        if shouldDeactivateCurrentSession {
            try deactivateCurrentSession()
            markDeactivated()
        }
    }
}

public struct RomaAudioSessionImmediateDeactivationPlan: Equatable, Sendable {
    private let shouldCancelScheduledDeactivation: Bool
    private let shouldDeactivateSession: Bool

    fileprivate init(
        shouldCancelScheduledDeactivation: Bool,
        shouldDeactivateSession: Bool
    ) {
        self.shouldCancelScheduledDeactivation = shouldCancelScheduledDeactivation
        self.shouldDeactivateSession = shouldDeactivateSession
    }

    @discardableResult
    public func applyRuntimeState(
        cancelScheduledDeactivation: () -> Void,
        deactivateSession: () throws -> Void,
        markDeactivated: () -> Void
    ) throws -> Bool {
        if shouldCancelScheduledDeactivation {
            cancelScheduledDeactivation()
        }

        guard shouldDeactivateSession else {
            return false
        }

        try deactivateSession()
        markDeactivated()
        return true
    }
}

public struct RomaAudioSessionLifecycleState: Equatable, Sendable {
    public private(set) var isSessionActive: Bool
    public private(set) var timeoutRemaining: TimeInterval

    public init(
        isSessionActive: Bool = false,
        timeoutRemaining: TimeInterval = 0
    ) {
        self.isSessionActive = isSessionActive
        self.timeoutRemaining = timeoutRemaining
    }

    public mutating func markActivatedForRecording() {
        isSessionActive = true
        cancelScheduledDeactivation()
    }

    public mutating func markActivatedForPlayback() {
        isSessionActive = true
        cancelScheduledDeactivation()
    }

    public mutating func beginPlaybackActivation() -> RomaAudioSessionPlaybackActivationPlan {
        let plan = RomaAudioSessionPlaybackActivationPlan(
            shouldCancelScheduledDeactivation: true,
            shouldDeactivateCurrentSession: isSessionActive
        )
        cancelScheduledDeactivation()
        return plan
    }

    public mutating func beginImmediateDeactivation() -> RomaAudioSessionImmediateDeactivationPlan {
        let plan = RomaAudioSessionImmediateDeactivationPlan(
            shouldCancelScheduledDeactivation: true,
            shouldDeactivateSession: isSessionActive
        )
        cancelScheduledDeactivation()
        return plan
    }

    public mutating func scheduleDeactivation(timeoutSeconds: Int) -> RomaAudioSessionDeactivationPlan {
        cancelScheduledDeactivation()

        let plan = RomaAudioSessionTimeoutPreference.deactivationPlan(for: timeoutSeconds)
        if case .delayed(let interval) = plan {
            timeoutRemaining = interval
        }

        return plan
    }

    public mutating func scheduleDeactivationExecution(timeoutSeconds: Int) -> RomaAudioSessionDeactivationExecutionPlan {
        scheduleDeactivation(timeoutSeconds: timeoutSeconds).executionPlan
    }

    public mutating func advanceCountdown() -> RomaAudioSessionDeactivationPlan {
        timeoutRemaining = RomaAudioSessionTimeoutPreference.remainingTimeAfterCountdownTick(timeoutRemaining)
        return timeoutRemaining <= 0 ? .immediate : .delayed(timeoutRemaining)
    }

    public mutating func advanceCountdownExecution() -> RomaAudioSessionDeactivationExecutionPlan {
        advanceCountdown().executionPlan
    }

    public mutating func cancelScheduledDeactivation() {
        timeoutRemaining = 0
    }

    public mutating func markDeactivated() {
        isSessionActive = false
        cancelScheduledDeactivation()
    }
}

public struct RomaIOSAudioRecorderConfiguration: Equatable, Sendable {
    public enum Format: String, Equatable, Sendable {
        case linearPCM
    }

    public enum Quality: String, Equatable, Sendable {
        case high
    }

    public let format: Format
    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
    public let isBigEndian: Bool
    public let isFloatingPoint: Bool
    public let quality: Quality
    public let isMeteringEnabled: Bool

    public init(
        format: Format,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        isBigEndian: Bool,
        isFloatingPoint: Bool,
        quality: Quality,
        isMeteringEnabled: Bool
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isBigEndian = isBigEndian
        self.isFloatingPoint = isFloatingPoint
        self.quality = quality
        self.isMeteringEnabled = isMeteringEnabled
    }

    public static let voiceRecording = Self(
        format: .linearPCM,
        sampleRate: RomaPCM16Audio.mono16kSampleRate,
        channelCount: RomaPCM16Audio.monoChannelCount,
        bitDepth: RomaPCM16Audio.bitsPerSample,
        isBigEndian: RomaPCM16Audio.isBigEndian,
        isFloatingPoint: RomaPCM16Audio.isFloatingPoint,
        quality: .high,
        isMeteringEnabled: true
    )
}

public enum RomaAudioPlaybackDiagnostics {
    public static func loadFailedMessage(errorDescription: String) -> String {
        "Failed to load audio: \(errorDescription)"
    }

    public static func playFailedMessage(errorDescription: String) -> String {
        "Failed to play audio: \(errorDescription)"
    }

    public static func macOSWaveformReadFailedMessage(errorDescription: String) -> String {
        "Error reading audio file: \(errorDescription)"
    }

    public static func macOSLoadFailedMessage(localizedDescription: String) -> String {
        "Error loading audio: \(localizedDescription)"
    }
}

public enum RomaAudioPlaybackTimeline {
    public static let updateInterval: TimeInterval = 0.1

    public static func progress(
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0, currentTime.isFinite, duration.isFinite else {
            return 0
        }

        return clampedProgress(currentTime / duration)
    }

    public static func progress(
        locationX: Double,
        width: Double
    ) -> Double {
        guard width > 0, locationX.isFinite, width.isFinite else {
            return 0
        }

        return clampedProgress(locationX / width)
    }

    public static func time(
        atLocationX locationX: Double,
        width: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0, duration.isFinite else {
            return 0
        }

        return progress(locationX: locationX, width: width) * duration
    }

    public static func clampedTime(
        _ time: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0, time.isFinite, duration.isFinite else {
            return 0
        }

        return min(max(time, 0), duration)
    }

    public static func sampleProgress(index: Int, sampleCount: Int) -> Double {
        guard sampleCount > 0 else {
            return 0
        }

        return clampedProgress(Double(index) / Double(sampleCount))
    }

    private static func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }
}

enum RomaAudioPlaybackTimerTickAction: Equatable, Sendable {
    case none
    case markStopped
    case markStoppedAndSeek(TimeInterval)
}

public struct RomaAudioPlaybackTimerTickPlan: Equatable, Sendable {
    fileprivate let tickCurrentTime: TimeInterval
    fileprivate let action: RomaAudioPlaybackTimerTickAction

    init(
        currentTime: TimeInterval,
        action: RomaAudioPlaybackTimerTickAction
    ) {
        self.tickCurrentTime = currentTime
        self.action = action
    }

    public func applyRuntimeState(
        seekPlayer: (TimeInterval) -> Void,
        stopTimer: () -> Void
    ) {
        switch action {
        case .none:
            break
        case .markStopped:
            stopTimer()
        case .markStoppedAndSeek(let seekTime):
            seekPlayer(seekTime)
            stopTimer()
        }
    }

    public static func macOS(
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> RomaAudioPlaybackTimerTickPlan {
        if currentTime >= duration {
            return RomaAudioPlaybackTimerTickPlan(
                currentTime: currentTime,
                action: .markStoppedAndSeek(0)
            )
        }

        return RomaAudioPlaybackTimerTickPlan(
            currentTime: currentTime,
            action: .none
        )
    }

    public static func iOS(
        currentTime: TimeInterval,
        playerIsPlaying: Bool,
        shellIsPlaying: Bool
    ) -> RomaAudioPlaybackTimerTickPlan {
        RomaAudioPlaybackTimerTickPlan(
            currentTime: currentTime,
            action: !playerIsPlaying && shellIsPlaying ? .markStopped : .none
        )
    }
}

public struct RomaAudioPlaybackState: Equatable, Sendable {
    public let isPlaying: Bool
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let playbackRate: Float

    public init(
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        playbackRate: Float
    ) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
    }

    public func loaded(
        duration: TimeInterval,
        resetCurrentTime: Bool
    ) -> RomaAudioPlaybackState {
        copy(
            currentTime: resetCurrentTime ? 0 : currentTime,
            duration: duration
        )
    }

    public func playing() -> RomaAudioPlaybackState {
        copy(isPlaying: true)
    }

    public func paused() -> RomaAudioPlaybackState {
        copy(isPlaying: false)
    }

    public func stopped() -> RomaAudioPlaybackState {
        copy(isPlaying: false, currentTime: 0)
    }

    public func seeking(to time: TimeInterval) -> RomaAudioPlaybackState {
        copy(currentTime: RomaAudioPlaybackTimeline.clampedTime(time, duration: duration))
    }

    public func updatingCurrentTime(_ time: TimeInterval) -> RomaAudioPlaybackState {
        copy(currentTime: time)
    }

    public var playPausePlan: RomaAudioPlaybackPlayPausePlan {
        RomaAudioPlaybackPlayPausePlan(action: isPlaying ? .pause : .play)
    }

    public func applyingTimerTickPlan(_ plan: RomaAudioPlaybackTimerTickPlan) -> RomaAudioPlaybackState {
        let updatedState = updatingCurrentTime(plan.tickCurrentTime)

        switch plan.action {
        case .none:
            return updatedState
        case .markStopped:
            return updatedState.paused()
        case .markStoppedAndSeek(let seekTime):
            return updatedState.paused().seeking(to: seekTime)
        }
    }

    public func cyclingPlaybackRate() -> RomaAudioPlaybackState {
        copy(playbackRate: RomaAudioPlaybackRate.next(after: playbackRate))
    }

    private func copy(
        isPlaying: Bool? = nil,
        currentTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        playbackRate: Float? = nil
    ) -> RomaAudioPlaybackState {
        RomaAudioPlaybackState(
            isPlaying: isPlaying ?? self.isPlaying,
            currentTime: currentTime ?? self.currentTime,
            duration: duration ?? self.duration,
            playbackRate: playbackRate ?? self.playbackRate
        )
    }
}

enum RomaAudioPlaybackPlayPauseAction: Equatable, Sendable {
    case play
    case pause
}

public struct RomaAudioPlaybackPlayPausePlan: Equatable, Sendable {
    fileprivate let action: RomaAudioPlaybackPlayPauseAction

    init(action: RomaAudioPlaybackPlayPauseAction) {
        self.action = action
    }

    public func applyRuntimeState(
        play: () -> Void,
        pause: () -> Void
    ) {
        switch action {
        case .play:
            play()
        case .pause:
            pause()
        }
    }
}

public enum RomaAudioPlaybackRate {
    public static let defaultRate: Float = 1.0
    public static let controlTitle = "Playback speed"

    public static func current(from defaults: UserDefaults = .standard) -> Float {
        restoredRate(defaults.float(forKey: RomaUserDefaultsKey.audioPlaybackRate))
    }

    public static func restoredRate(_ savedRate: Float) -> Float {
        savedRate > 0 ? savedRate : defaultRate
    }

    public static func save(_ rate: Float, to defaults: UserDefaults = .standard) {
        defaults.set(rate, forKey: RomaUserDefaultsKey.audioPlaybackRate)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.audioPlaybackRate)
    }

    public static func next(after rate: Float) -> Float {
        switch rate {
        case 1.0:
            return 1.5
        case 1.5:
            return 2.0
        default:
            return 1.0
        }
    }

    public static func label(for rate: Float) -> String {
        switch rate {
        case 1.0:
            return "1×"
        case 1.5:
            return "1.5×"
        default:
            return "2×"
        }
    }

    public static func isDefault(_ rate: Float) -> Bool {
        rate == defaultRate
    }
}

public enum RomaAudioPlaybackPresentation {
    public static let loadingText = "Loading..."
    public static let timestampSystemImageName = "calendar"
    public static let durationSystemImageName = "waveform"
    public static let showInFinderHelpText = "Show in Finder"
    public static let selectEnhancementPromptHelpText = "Select enhancement prompt"
    public static let enhancementPromptFallbackSystemImageName = "sparkles"
    public static let retranscribeAudioHelpText = "Retranscribe this audio"
    public static let reEnhanceWithSelectedPromptHelpText = "Re-enhance with selected prompt"
    public static let historyReprocessingTitle = "Process Again"
    public static let modePromptTitle = "Mode Prompt"
    public static let retranscribeButtonTitle = "Retranscribe"
    public static let reEnhanceButtonTitle = "Re-enhance"
    public static let viewDetailsHelpText = "View details"

    public static func playPauseSystemImageName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    public static func enhancementPromptSystemImageName(activePromptIcon: String?) -> String {
        activePromptIcon ?? enhancementPromptFallbackSystemImageName
    }
}

public struct RomaAudioPlaybackReEnhancementControlPresentation: Equatable, Sendable {
    public let isActionDisabled: Bool
    public let opacity: Double
    public let unavailableBannerPresentation: RomaAudioPlaybackActionBannerPresentation?

    public init(
        isOperationInProgress: Bool,
        isEnhancementEnabled: Bool,
        isEnhancementConfigured: Bool
    ) {
        let unavailableBannerPresentation = RomaAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
            isEnabled: isEnhancementEnabled,
            isConfigured: isEnhancementConfigured
        )

        self.isActionDisabled = isOperationInProgress || unavailableBannerPresentation != nil
        self.opacity = unavailableBannerPresentation == nil ? 1.0 : 0.4
        self.unavailableBannerPresentation = unavailableBannerPresentation
    }
}

public struct RomaAudioPlaybackActionBannerPresentation: Equatable, Sendable {
    public let message: String
    public let isError: Bool

    public init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }

    public static let retranscriptionSuccess = RomaAudioPlaybackActionBannerPresentation(
        message: RomaTranscriptPresentation.audioFileRetranscriptionSuccessMessage,
        isError: false
    )

    public static let reEnhancementSuccess = RomaAudioPlaybackActionBannerPresentation(
        message: RomaTranscriptPresentation.audioFileReEnhancementSuccessMessage,
        isError: false
    )

    public static let retranscriptionNoModelFailure = retranscriptionFailure(
        errorDescription: RomaErrorDescription.text(for: RomaEngineError.noTranscriptionModelSelected)
    )

    public static func retranscriptionFailure(
        errorDescription: String
    ) -> RomaAudioPlaybackActionBannerPresentation {
        RomaAudioPlaybackActionBannerPresentation(
            message: RomaTranscriptPresentation.audioFileRetranscriptionFailureMessage(
                errorDescription: errorDescription
            ),
            isError: true
        )
    }

    public static func reEnhancementFailure(
        errorDescription: String
    ) -> RomaAudioPlaybackActionBannerPresentation {
        RomaAudioPlaybackActionBannerPresentation(
            message: RomaTranscriptPresentation.audioFileReEnhancementFailureMessage(
                errorDescription: errorDescription
            ),
            isError: true
        )
    }

    public static func reEnhancementUnavailable(
        isEnabled: Bool,
        isConfigured: Bool
    ) -> RomaAudioPlaybackActionBannerPresentation? {
        guard let message = RomaPostProcessingFailurePresentation.enhancementUnavailableMessage(
            isEnabled: isEnabled,
            isConfigured: isConfigured
        ) else {
            return nil
        }

        return RomaAudioPlaybackActionBannerPresentation(message: message, isError: true)
    }
}
