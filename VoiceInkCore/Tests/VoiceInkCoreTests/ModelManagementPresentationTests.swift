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
        let localAvailable = VoiceInkModelManagementModelFacts(
            name: "ggml-base.en",
            category: .local,
            isAvailableOnCurrentOS: true
        )
        let localUnavailable = VoiceInkModelManagementModelFacts(
            name: "ggml-large-v3-turbo-q5_0",
            category: .local,
            isAvailableOnCurrentOS: false
        )
        let cloud = VoiceInkModelManagementModelFacts(
            name: "whisper-large-v3-turbo",
            category: .cloud,
            isAvailableOnCurrentOS: true
        )
        let custom = VoiceInkModelManagementModelFacts(
            name: "custom-api",
            category: .custom,
            isAvailableOnCurrentOS: true
        )

        XCTAssertTrue(VoiceInkModelManagementFilter.recommended.includes(localAvailable))
        XCTAssertTrue(VoiceInkModelManagementFilter.recommended.includes(localUnavailable))
        XCTAssertTrue(VoiceInkModelManagementFilter.recommended.includes(cloud))
        XCTAssertTrue(VoiceInkModelManagementFilter.local.includes(localAvailable))
        XCTAssertFalse(VoiceInkModelManagementFilter.local.includes(localUnavailable))
        XCTAssertTrue(VoiceInkModelManagementFilter.cloud.includes(cloud))
        XCTAssertFalse(VoiceInkModelManagementFilter.cloud.includes(custom))
        XCTAssertTrue(VoiceInkModelManagementFilter.custom.includes(custom))
    }

    func testModelManagementRecommendedOrderIsShared() {
        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommendedModelNames,
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertLessThan(
            VoiceInkModelManagementFilter.recommended.sortRank(forModelName: "ggml-base.en"),
            VoiceInkModelManagementFilter.recommended.sortRank(forModelName: "whisper-large-v3-turbo")
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.sortRank(forModelName: "missing"),
            Int.max
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
        XCTAssertEqual(VoiceInkModelManagementPresentation.importedLocalModelDescription, "Imported local model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.customProviderLabel, "Custom Provider")
        XCTAssertEqual(VoiceInkModelManagementPresentation.openAICompatibleLabel, "OpenAI Compatible")
        XCTAssertEqual(VoiceInkModelManagementPresentation.nativeAppleProviderLabel, "Native Apple")
        XCTAssertEqual(VoiceInkModelManagementPresentation.onDeviceLabel, "On-Device")
        XCTAssertEqual(VoiceInkModelManagementPresentation.macOS26RequiredLabel, "macOS 26+")
        XCTAssertEqual(VoiceInkModelManagementPresentation.noModelSelectedText, "No model selected")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importLocalModelTitle, "Import Local Model…")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.customModelsLimitationText,
            "Only OpenAI-compatible transcription APIs are supported."
        )
        XCTAssertEqual(VoiceInkModelManagementPresentation.closeButtonHelp, "Close")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteCustomModelAlertMessage(displayName: "My Model"),
            "Are you sure you want to delete the custom model 'My Model'?"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteModelAlertMessage(modelName: "ggml-base.en"),
            "Are you sure you want to delete the model 'ggml-base.en'?"
        )
    }
}
