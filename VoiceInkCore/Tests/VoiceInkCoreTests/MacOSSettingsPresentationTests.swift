@testable import VoiceInkCore

final class MacOSSettingsPresentationTests: XCTestCase {
    func testIconVisibilityThumbLabelsMatchVisibleState() {
        let presentation = VoiceInkMacOSSettingsPresentation.macOS

        XCTAssertEqual(presentation.visibilityValueTitle(isVisible: true), "Show")
        XCTAssertEqual(presentation.visibilityValueTitle(isVisible: false), "Hide")
    }
}
