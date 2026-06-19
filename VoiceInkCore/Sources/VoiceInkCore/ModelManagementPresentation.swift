import Foundation

public enum VoiceInkModelManagementFilter: String, CaseIterable, Identifiable, Sendable {
    case recommended = "Recommended"
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"

    public var id: String { rawValue }
    public var title: String { rawValue }
    public var settingsSectionTitle: String { "\(title) Models" }
    public var manageSettingsTitle: String { "Manage \(settingsSectionTitle)" }
}

public enum VoiceInkModelManagementPresentation {
    public static let settingsTitle = "Model Settings"
    public static let defaultModelTitle = "Default Model"
    public static let setAsDefaultButtonTitle = "Set as Default"
    public static let noModelSelectedText = "No model selected"
    public static let importLocalModelTitle = "Import Local Model…"
    public static let customModelsLimitationText = "Only OpenAI-compatible transcription APIs are supported."
    public static let closeButtonHelp = "Close"
}
