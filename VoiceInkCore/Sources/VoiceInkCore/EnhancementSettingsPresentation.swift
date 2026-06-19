import Foundation

public struct VoiceInkEnhancementIntegerOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Int

    public var id: Int { value }
}

public struct VoiceInkEnhancementRetryOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Bool

    public var id: Bool { value }
}

public struct VoiceInkEnhancementSettingsPresentation: Equatable, Sendable {
    public let title: String
    public let closeButtonHelp: String
    public let contextSectionTitle: String
    public let clipboardContextTitle: String
    public let clipboardContextHelp: String
    public let screenContextTitle: String
    public let screenContextHelp: String
    public let skipShortEnhancementTitle: String
    public let skipShortEnhancementHelp: String
    public let disclosureSystemImageName: String
    public let minimumWordsPickerTitle: String
    public let shortEnhancementWordOptions: [VoiceInkEnhancementIntegerOption]
    public let timeoutPickerTitle: String
    public let timeoutOptions: [VoiceInkEnhancementIntegerOption]
    public let timeoutRetryPickerTitle: String
    public let timeoutRetryOptions: [VoiceInkEnhancementRetryOption]
    public let requestTimeoutSectionTitle: String
    public let requestTimeoutHelp: String
    public let shortcutsSectionTitle: String

    public static let macOS = VoiceInkEnhancementSettingsPresentation(
        title: "Enhancement Settings",
        closeButtonHelp: "Close",
        contextSectionTitle: "Context",
        clipboardContextTitle: "Clipboard Context",
        clipboardContextHelp: "Use clipboard text to understand context for better enhancement.",
        screenContextTitle: "Screen Context",
        screenContextHelp: "Capture on-screen text to understand context for better enhancement.",
        skipShortEnhancementTitle: "Skip short transcriptions",
        skipShortEnhancementHelp: "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement.",
        disclosureSystemImageName: "chevron.right",
        minimumWordsPickerTitle: "Minimum words",
        shortEnhancementWordOptions: (1...15).map {
            VoiceInkEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
        },
        timeoutPickerTitle: "Timeout duration",
        timeoutOptions: [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
            VoiceInkEnhancementIntegerOption(title: "\($0) seconds", value: $0)
        },
        timeoutRetryPickerTitle: "On timeout",
        timeoutRetryOptions: [
            VoiceInkEnhancementRetryOption(title: "Fail immediately", value: false),
            VoiceInkEnhancementRetryOption(title: "Retry", value: true)
        ],
        requestTimeoutSectionTitle: "Request Timeout",
        requestTimeoutHelp: "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts).",
        shortcutsSectionTitle: "Shortcuts"
    )
}
