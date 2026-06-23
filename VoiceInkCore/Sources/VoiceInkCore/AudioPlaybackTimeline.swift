import Foundation

public enum VoiceInkAudioPlaybackDiagnostics {
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

public enum VoiceInkAudioPlaybackTimeline {
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

public enum VoiceInkAudioPlaybackTimerTickAction: Equatable, Sendable {
    case none
    case markStopped
    case markStoppedAndSeek(TimeInterval)

    public var shouldStopTimer: Bool {
        switch self {
        case .none:
            return false
        case .markStopped, .markStoppedAndSeek:
            return true
        }
    }

    public var playerSeekTime: TimeInterval? {
        switch self {
        case .none, .markStopped:
            return nil
        case .markStoppedAndSeek(let seekTime):
            return seekTime
        }
    }
}

public struct VoiceInkAudioPlaybackTimerTickPlan: Equatable, Sendable {
    public let currentTime: TimeInterval
    public let action: VoiceInkAudioPlaybackTimerTickAction

    public init(
        currentTime: TimeInterval,
        action: VoiceInkAudioPlaybackTimerTickAction
    ) {
        self.currentTime = currentTime
        self.action = action
    }

    public var shouldStopTimer: Bool {
        action.shouldStopTimer
    }

    public var playerSeekTime: TimeInterval? {
        action.playerSeekTime
    }

    public static func macOS(
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> VoiceInkAudioPlaybackTimerTickPlan {
        if currentTime >= duration {
            return VoiceInkAudioPlaybackTimerTickPlan(
                currentTime: currentTime,
                action: .markStoppedAndSeek(0)
            )
        }

        return VoiceInkAudioPlaybackTimerTickPlan(
            currentTime: currentTime,
            action: .none
        )
    }

    public static func iOS(
        currentTime: TimeInterval,
        playerIsPlaying: Bool,
        shellIsPlaying: Bool
    ) -> VoiceInkAudioPlaybackTimerTickPlan {
        VoiceInkAudioPlaybackTimerTickPlan(
            currentTime: currentTime,
            action: !playerIsPlaying && shellIsPlaying ? .markStopped : .none
        )
    }
}

public struct VoiceInkAudioPlaybackState: Equatable, Sendable {
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
    ) -> VoiceInkAudioPlaybackState {
        copy(
            currentTime: resetCurrentTime ? 0 : currentTime,
            duration: duration
        )
    }

    public func playing() -> VoiceInkAudioPlaybackState {
        copy(isPlaying: true)
    }

    public func paused() -> VoiceInkAudioPlaybackState {
        copy(isPlaying: false)
    }

    public func stopped() -> VoiceInkAudioPlaybackState {
        copy(isPlaying: false, currentTime: 0)
    }

    public func seeking(to time: TimeInterval) -> VoiceInkAudioPlaybackState {
        copy(currentTime: VoiceInkAudioPlaybackTimeline.clampedTime(time, duration: duration))
    }

    public func updatingCurrentTime(_ time: TimeInterval) -> VoiceInkAudioPlaybackState {
        copy(currentTime: time)
    }

    public func applyingTimerTickPlan(_ plan: VoiceInkAudioPlaybackTimerTickPlan) -> VoiceInkAudioPlaybackState {
        let updatedState = updatingCurrentTime(plan.currentTime)

        switch plan.action {
        case .none:
            return updatedState
        case .markStopped:
            return updatedState.paused()
        case .markStoppedAndSeek(let seekTime):
            return updatedState.paused().seeking(to: seekTime)
        }
    }

    public func cyclingPlaybackRate() -> VoiceInkAudioPlaybackState {
        copy(playbackRate: VoiceInkAudioPlaybackRate.next(after: playbackRate))
    }

    private func copy(
        isPlaying: Bool? = nil,
        currentTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        playbackRate: Float? = nil
    ) -> VoiceInkAudioPlaybackState {
        VoiceInkAudioPlaybackState(
            isPlaying: isPlaying ?? self.isPlaying,
            currentTime: currentTime ?? self.currentTime,
            duration: duration ?? self.duration,
            playbackRate: playbackRate ?? self.playbackRate
        )
    }
}

public enum VoiceInkAudioPlaybackRate {
    public static let defaultRate: Float = 1.0
    public static let controlTitle = "Playback speed"

    public static func current(from defaults: UserDefaults = .standard) -> Float {
        restoredRate(defaults.float(forKey: VoiceInkUserDefaultsKey.audioPlaybackRate))
    }

    public static func restoredRate(_ savedRate: Float) -> Float {
        savedRate > 0 ? savedRate : defaultRate
    }

    public static func save(_ rate: Float, to defaults: UserDefaults = .standard) {
        defaults.set(rate, forKey: VoiceInkUserDefaultsKey.audioPlaybackRate)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioPlaybackRate)
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

public enum VoiceInkAudioPlaybackPresentation {
    public static let loadingText = "Loading..."
    public static let timestampSystemImageName = "calendar"
    public static let durationSystemImageName = "waveform"
    public static let showInFinderHelpText = "Show in Finder"
    public static let selectEnhancementPromptHelpText = "Select enhancement prompt"
    public static let enhancementPromptFallbackSystemImageName = "sparkles"
    public static let retranscribeAudioHelpText = "Retranscribe this audio"
    public static let reEnhanceWithSelectedPromptHelpText = "Re-enhance with selected prompt"
    public static let viewDetailsHelpText = "View details"

    public static func playPauseSystemImageName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    public static func enhancementPromptSystemImageName(activePromptIcon: String?) -> String {
        activePromptIcon ?? enhancementPromptFallbackSystemImageName
    }
}

public struct VoiceInkAudioPlaybackReEnhancementControlPresentation: Equatable, Sendable {
    public let isActionDisabled: Bool
    public let opacity: Double
    public let unavailableBannerPresentation: VoiceInkAudioPlaybackActionBannerPresentation?

    public init(
        isOperationInProgress: Bool,
        isEnhancementEnabled: Bool,
        isEnhancementConfigured: Bool
    ) {
        let unavailableBannerPresentation = VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
            isEnabled: isEnhancementEnabled,
            isConfigured: isEnhancementConfigured
        )

        self.isActionDisabled = isOperationInProgress || unavailableBannerPresentation != nil
        self.opacity = unavailableBannerPresentation == nil ? 1.0 : 0.4
        self.unavailableBannerPresentation = unavailableBannerPresentation
    }
}

public struct VoiceInkAudioPlaybackActionBannerPresentation: Equatable, Sendable {
    public let message: String
    public let isError: Bool

    public init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }

    public static let retranscriptionSuccess = VoiceInkAudioPlaybackActionBannerPresentation(
        message: VoiceInkTranscriptPresentation.audioFileRetranscriptionSuccessMessage,
        isError: false
    )

    public static let reEnhancementSuccess = VoiceInkAudioPlaybackActionBannerPresentation(
        message: VoiceInkTranscriptPresentation.audioFileReEnhancementSuccessMessage,
        isError: false
    )

    public static let retranscriptionNoModelFailure = retranscriptionFailure(
        errorDescription: VoiceInkErrorDescription.text(for: VoiceInkEngineError.noTranscriptionModelSelected)
    )

    public static func retranscriptionFailure(
        errorDescription: String
    ) -> VoiceInkAudioPlaybackActionBannerPresentation {
        VoiceInkAudioPlaybackActionBannerPresentation(
            message: VoiceInkTranscriptPresentation.audioFileRetranscriptionFailureMessage(
                errorDescription: errorDescription
            ),
            isError: true
        )
    }

    public static func reEnhancementFailure(
        errorDescription: String
    ) -> VoiceInkAudioPlaybackActionBannerPresentation {
        VoiceInkAudioPlaybackActionBannerPresentation(
            message: VoiceInkTranscriptPresentation.audioFileReEnhancementFailureMessage(
                errorDescription: errorDescription
            ),
            isError: true
        )
    }

    public static func reEnhancementUnavailable(
        isEnabled: Bool,
        isConfigured: Bool
    ) -> VoiceInkAudioPlaybackActionBannerPresentation? {
        guard let message = VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
            isEnabled: isEnabled,
            isConfigured: isConfigured
        ) else {
            return nil
        }

        return VoiceInkAudioPlaybackActionBannerPresentation(message: message, isError: true)
    }
}
