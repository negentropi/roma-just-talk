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
}
