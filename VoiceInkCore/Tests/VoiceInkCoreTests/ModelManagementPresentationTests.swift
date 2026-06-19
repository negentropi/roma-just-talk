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

    func testModelManagementPresentationPreservesPlatformCopy() {
        XCTAssertEqual(VoiceInkModelManagementPresentation.settingsTitle, "Model Settings")
        XCTAssertEqual(VoiceInkModelManagementPresentation.defaultModelTitle, "Default Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle, "Set as Default")
        XCTAssertEqual(VoiceInkModelManagementPresentation.noModelSelectedText, "No model selected")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importLocalModelTitle, "Import Local Model…")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.customModelsLimitationText,
            "Only OpenAI-compatible transcription APIs are supported."
        )
        XCTAssertEqual(VoiceInkModelManagementPresentation.closeButtonHelp, "Close")
    }
}
