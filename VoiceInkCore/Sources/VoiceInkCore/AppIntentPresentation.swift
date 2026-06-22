import Foundation

public struct VoiceInkAppIntentPresentation: Equatable, Sendable {
    public let title: String
    public let description: String
    public let successDialog: String

    public init(title: String, description: String, successDialog: String) {
        self.title = title
        self.description = description
        self.successDialog = successDialog
    }
}

public enum VoiceInkMiniRecorderAppIntentPresentation {
    public static let toggle = VoiceInkAppIntentPresentation(
        title: "Toggle VoiceInk Recorder",
        description: "Start or stop the VoiceInk mini recorder for voice transcription.",
        successDialog: "VoiceInk recorder toggled"
    )

    public static let dismiss = VoiceInkAppIntentPresentation(
        title: "Dismiss VoiceInk Recorder",
        description: "Dismiss the VoiceInk mini recorder and cancel any active recording.",
        successDialog: "VoiceInk recorder dismissed"
    )
}
