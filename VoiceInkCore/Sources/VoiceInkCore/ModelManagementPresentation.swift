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

    public static let recommendedModelNames = [
        "ggml-base.en",
        "parakeet-tdt-0.6b-v2",
        "ggml-large-v3-turbo-q5_0",
        "whisper-large-v3-turbo"
    ]

    public func includes(_ facts: VoiceInkModelManagementModelFacts) -> Bool {
        switch self {
        case .recommended:
            return Self.recommendedModelNames.contains(facts.name)
        case .local:
            return facts.category == .local && facts.isAvailableOnCurrentOS
        case .cloud:
            return facts.category == .cloud
        case .custom:
            return facts.category == .custom
        }
    }

    public func sortRank(forModelName name: String) -> Int {
        Self.recommendedModelNames.firstIndex(of: name) ?? Int.max
    }
}

public enum VoiceInkModelManagementModelCategory: Equatable, Sendable {
    case local
    case cloud
    case custom
}

public struct VoiceInkModelManagementModelFacts: Equatable, Sendable {
    public var name: String
    public var category: VoiceInkModelManagementModelCategory
    public var isAvailableOnCurrentOS: Bool

    public init(
        name: String,
        category: VoiceInkModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool
    ) {
        self.name = name
        self.category = category
        self.isAvailableOnCurrentOS = isAvailableOnCurrentOS
    }
}

public enum VoiceInkModelManagementPresentation {
    public static let settingsTitle = "Model Settings"
    public static let defaultModelTitle = "Default Model"
    public static let setAsDefaultButtonTitle = "Set as Default"
    public static let downloadButtonTitle = "Download"
    public static let editModelButtonTitle = "Edit Model"
    public static let deleteModelButtonTitle = "Delete Model"
    public static let deleteButtonTitle = "Delete"
    public static let deleteCustomModelAlertTitle = "Delete Custom Model"
    public static let showInFinderButtonTitle = "Show in Finder"
    public static let speedLabel = "Speed"
    public static let accuracyLabel = "Accuracy"
    public static let importedLocalModelDescription = "Imported local model"
    public static let customProviderLabel = "Custom Provider"
    public static let openAICompatibleLabel = "OpenAI Compatible"
    public static let nativeAppleProviderLabel = "Native Apple"
    public static let onDeviceLabel = "On-Device"
    public static let macOS26RequiredLabel = "macOS 26+"
    public static let noModelSelectedText = "No model selected"
    public static let importLocalModelTitle = "Import Local Model…"
    public static let importLocalModelHelpText = "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file."
    public static let importLocalModelLearnMoreURLString = "https://tryvoiceink.com/docs/custom-local-whisper-models"
    public static let importLocalModelLearnMoreHelpText = "Read more about custom local models"
    public static let importLocalModelPanelTitle = "Select a Whisper ggml .bin model"
    public static let customModelsLimitationText = "Only OpenAI-compatible transcription APIs are supported."
    public static let closeButtonHelp = "Close"

    public static func deleteCustomModelAlertMessage(displayName: String) -> String {
        "Are you sure you want to delete the custom model '\(displayName)'?"
    }

    public static func deleteModelAlertMessage(modelName: String) -> String {
        "Are you sure you want to delete the model '\(modelName)'?"
    }

    public static func importedLocalModelAlreadyExistsTitle(modelFilename: String) -> String {
        "A model named \(modelFilename) already exists"
    }

    public static func importedLocalModelSuccessTitle(filename: String) -> String {
        "Imported \(filename)"
    }

    public static func importedLocalModelFailureTitle(errorDescription: String) -> String {
        "Failed to import model: \(errorDescription)"
    }
}
