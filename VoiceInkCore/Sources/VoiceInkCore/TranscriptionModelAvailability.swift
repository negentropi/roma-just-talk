import Foundation

public enum VoiceInkTranscriptionModelAvailabilityRequirement: Equatable, Sendable {
    case configuredAPIKey
    case currentOSSupport
    case downloadedLocalFluidAudioModel
    case downloadedLocalWhisperModel
    case alwaysAvailable
    case unavailable
}

public struct VoiceInkTranscriptionModelAvailabilityFacts: Equatable, Sendable {
    public let requirement: VoiceInkTranscriptionModelAvailabilityRequirement
    public let hasConfiguredAPIKey: Bool
    public let isAvailableOnCurrentOS: Bool
    public let isLocalFluidAudioModelDownloaded: Bool
    public let isLocalWhisperModelDownloaded: Bool

    public init(
        requirement: VoiceInkTranscriptionModelAvailabilityRequirement,
        hasConfiguredAPIKey: Bool = false,
        isAvailableOnCurrentOS: Bool = true,
        isLocalFluidAudioModelDownloaded: Bool = false,
        isLocalWhisperModelDownloaded: Bool = false
    ) {
        self.requirement = requirement
        self.hasConfiguredAPIKey = hasConfiguredAPIKey
        self.isAvailableOnCurrentOS = isAvailableOnCurrentOS
        self.isLocalFluidAudioModelDownloaded = isLocalFluidAudioModelDownloaded
        self.isLocalWhisperModelDownloaded = isLocalWhisperModelDownloaded
    }

    public var isUsable: Bool {
        switch requirement {
        case .configuredAPIKey:
            hasConfiguredAPIKey
        case .currentOSSupport:
            isAvailableOnCurrentOS
        case .downloadedLocalFluidAudioModel:
            isLocalFluidAudioModelDownloaded
        case .downloadedLocalWhisperModel:
            isLocalWhisperModelDownloaded
        case .alwaysAvailable:
            true
        case .unavailable:
            false
        }
    }
}

public enum VoiceInkNativeAppleTranscriptionFailureKind: Equatable, Sendable {
    case unsupportedOS
    case transcriptionFailed
    case localeNotSupported
    case invalidModel
    case assetDownloadRequired(displayName: String)
    case resultStreamTimedOut
}

public enum VoiceInkNativeAppleTranscriptionPolicy {
    public static let minimumResultStreamTimeout: TimeInterval = 20.0
    public static let resultStreamTimeoutMultiplier = 4.0
    public static let resultStreamTimeoutPadding: TimeInterval = 10.0

    public static func requiresMacOS26Title(modelDisplayName: String) -> String {
        "\(modelDisplayName) requires macOS 26 or later"
    }

    public static func errorDescription(for failure: VoiceInkNativeAppleTranscriptionFailureKind) -> String {
        switch failure {
        case .unsupportedOS:
            return "SpeechAnalyzer requires macOS 26 or later."
        case .transcriptionFailed:
            return "Transcription failed using SpeechAnalyzer."
        case .localeNotSupported:
            return "The selected language is not supported by SpeechAnalyzer."
        case .invalidModel:
            return "Invalid model type provided for Native Apple transcription."
        case .assetDownloadRequired(let displayName):
            return "Download required for \(displayName)."
        case .resultStreamTimedOut:
            return "Apple Speech did not finish returning transcription results."
        }
    }

    public static func resultStreamTimeout(forAudioDuration audioDuration: TimeInterval) -> TimeInterval {
        max(minimumResultStreamTimeout, audioDuration * resultStreamTimeoutMultiplier + resultStreamTimeoutPadding)
    }
}
