import Foundation
@testable import VoiceInkCore

final class ModelManagementPresentationTests: XCTestCase {
    func testModelManagementFiltersPreservePlatformTitles() {
        XCTAssertEqual(
            VoiceInkModelManagementFilter.allCases.map(\.title),
            ["Recommended", "Local", "Cloud", "Custom"]
        )
        XCTAssertEqual(VoiceInkModelManagementFilter.local.settingsSectionTitle, "Local Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.local.manageSettingsTitle, "Manage Local Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.cloud.settingsSectionTitle, "Cloud Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.cloud.manageSettingsTitle, "Manage Cloud Models")
    }

    func testModelManagementFiltersApplySharedModelFacts() {
        let models = [
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "custom-api", category: .custom)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testModelManagementRecommendedOrderIsShared() {
        let models = [
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local),
            model(name: "parakeet-tdt-0.6b-v2", category: .local),
            model(name: "ggml-base.en", category: .local),
            model(name: "missing", category: .cloud)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
    }

    func testModelManagementFiltersOwnListFilteringAndRecommendedOrder() {
        let models = [
            model(name: "custom-api", category: .custom),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "parakeet-tdt-0.6b-v2", category: .local)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testModelManagementPresentationPreservesPlatformCopy() {
        XCTAssertEqual(VoiceInkModelManagementPresentation.settingsTitle, "Model Settings")
        XCTAssertEqual(VoiceInkModelManagementPresentation.defaultModelTitle, "Default Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle, "Set as Default")
        XCTAssertEqual(VoiceInkModelManagementPresentation.downloadButtonTitle, "Download")
        XCTAssertEqual(VoiceInkModelManagementPresentation.editModelButtonTitle, "Edit Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteModelButtonTitle, "Delete Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteCustomModelAlertTitle, "Delete Custom Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.showInFinderButtonTitle, "Show in Finder")
        XCTAssertEqual(VoiceInkModelManagementPresentation.speedLabel, "Speed")
        XCTAssertEqual(VoiceInkModelManagementPresentation.accuracyLabel, "Accuracy")
        XCTAssertEqual(VoiceInkModelManagementPresentation.multilingualLanguageLabel, "Multilingual")
        XCTAssertEqual(VoiceInkModelManagementPresentation.englishOnlyLanguageLabel, "English-only")
        XCTAssertEqual(VoiceInkModelManagementPresentation.languageLabel(isMultilingual: true), "Multilingual")
        XCTAssertEqual(VoiceInkModelManagementPresentation.languageLabel(isMultilingual: false), "English-only")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importedLocalModelDescription, "Imported local model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.customProviderLabel, "Custom Provider")
        XCTAssertEqual(VoiceInkModelManagementPresentation.openAICompatibleLabel, "OpenAI Compatible")
        XCTAssertEqual(VoiceInkModelManagementPresentation.nativeAppleProviderLabel, "Native Apple")
        XCTAssertEqual(VoiceInkModelManagementPresentation.onDeviceLabel, "On-Device")
        XCTAssertEqual(VoiceInkModelManagementPresentation.macOS26RequiredLabel, "macOS 26+")
        XCTAssertEqual(VoiceInkModelManagementPresentation.noModelSelectedText, "No model selected")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importLocalModelTitle, "Import Local Model…")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelHelpText,
            "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file."
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelLearnMoreURLString,
            "https://tryvoiceink.com/docs/custom-local-whisper-models"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelLearnMoreHelpText,
            "Read more about custom local models"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelPanelTitle,
            "Select a Whisper ggml .bin model"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.customModelsLimitationText,
            "Only OpenAI-compatible transcription APIs are supported."
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.intelMacLocalModelsWarningText,
            "Local models don't work reliably on Intel Macs"
        )
        XCTAssertEqual(VoiceInkModelManagementPresentation.intelMacUseCloudButtonTitle, "Use Cloud")
        XCTAssertEqual(VoiceInkModelManagementPresentation.closeButtonHelp, "Close")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteCustomModelAlertMessage(displayName: "My Model"),
            "Are you sure you want to delete the custom model 'My Model'?"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteModelAlertMessage(modelName: "ggml-base.en"),
            "Are you sure you want to delete the model 'ggml-base.en'?"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelAlreadyExistsTitle(modelFilename: "custom.bin"),
            "A model named custom.bin already exists"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelSuccessTitle(filename: "custom.bin"),
            "Imported custom.bin"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelFailureTitle(errorDescription: "Permission denied"),
            "Failed to import model: Permission denied"
        )
    }

    private func model(
        name: String,
        category: VoiceInkModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool = true
    ) -> ModelManagementFilterFixture {
        ModelManagementFilterFixture(
            facts: VoiceInkModelManagementModelFacts(
                name: name,
                category: category,
                isAvailableOnCurrentOS: isAvailableOnCurrentOS
            )
        )
    }
}

private struct ModelManagementFilterFixture {
    let facts: VoiceInkModelManagementModelFacts
}
