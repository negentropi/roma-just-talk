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
