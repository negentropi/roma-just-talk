import Foundation
@testable import VoiceInkCore

final class SettingsPresentationTests: XCTestCase {
    func testIOSSettingsPresentationPreservesSettingsChromeCopy() {
        let presentation = VoiceInkSettingsPresentation.iOS

        XCTAssertEqual(presentation.navigationTitle, "Settings")
        XCTAssertEqual(presentation.modesSectionTitle, "Modes")
        XCTAssertEqual(presentation.addModeButtonTitle, "Add New Mode")
        XCTAssertEqual(presentation.addActionSystemImageName, "plus.circle.fill")
        XCTAssertEqual(presentation.debugSectionTitle, "Debug")
        XCTAssertEqual(presentation.resetAllAppDataButtonTitle, "Reset All App Data")
        XCTAssertEqual(presentation.resetAllAppDataSystemImageName, "trash")
    }

    func testMacOSSettingsPresentationPreservesSettingsChromeCopy() {
        let presentation = VoiceInkMacOSSettingsPresentation.macOS

        XCTAssertEqual(presentation.generalSectionTitle, "General")
        XCTAssertEqual(presentation.showMenuBarIconTitle, "Show in Menu Bar")
        XCTAssertEqual(presentation.hideDockIconTitle, "Hide Dock Icon")
        XCTAssertEqual(presentation.launchAtLoginTitle, "Launch at Login")
        XCTAssertEqual(presentation.autoCheckUpdatesTitle, "Auto-check Updates")
        XCTAssertEqual(presentation.showAnnouncementsTitle, "Show Announcements")
        XCTAssertEqual(presentation.checkForUpdatesButtonTitle, "Check for Updates")
        XCTAssertEqual(presentation.privacySectionTitle, "Privacy")
        XCTAssertEqual(
            presentation.privacyFooterText,
            "Control how VoiceInk handles your transcription data and audio recordings."
        )
        XCTAssertEqual(presentation.backupSectionTitle, "Backup")
        XCTAssertEqual(
            presentation.backupFooterText,
            "Export all settings, or choose specific categories when importing a backup."
        )
        XCTAssertEqual(presentation.exportSettingsLabel, "Export Settings")
        XCTAssertEqual(presentation.exportButtonTitle, "Export")
        XCTAssertEqual(presentation.importSettingsLabel, "Import Settings")
        XCTAssertEqual(presentation.importButtonTitle, "Import")
        XCTAssertEqual(presentation.diagnosticsSectionTitle, "Diagnostics")
    }
}
