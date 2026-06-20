import Foundation
@testable import VoiceInkCore

final class SettingsBackupPolicyTests: XCTestCase {
    func testBackupCategoriesPreserveMacOSImportOrderAndTitles() {
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.rawValue),
            ["general", "prompts", "powerMode", "dictionary", "customModels"]
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.title),
            [
                "General Settings",
                "Custom Prompts",
                "Power Mode",
                "Dictionary",
                "Custom Model Definitions"
            ]
        )
    }

    func testBackupImportPolicySummarizesAllAndSelectedCategories() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(
                for: Set(VoiceInkSettingsBackupCategory.allCases)
            ),
            "All settings"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(for: [.dictionary, .prompts]),
            "Custom Prompts, Dictionary"
        )
    }

    func testBackupImportPolicyRemindsOnlyForAPIKeyDependentCategories() {
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: []))
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.general, .dictionary]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.prompts]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.powerMode]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.customModels]))
    }
}
