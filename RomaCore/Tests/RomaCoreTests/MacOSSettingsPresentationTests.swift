@testable import RomaCore

final class MacOSSettingsPresentationTests: XCTestCase {
    func testIconVisibilityThumbLabelsMatchVisibleState() {
        let presentation = RomaMacOSSettingsPresentation.macOS

        XCTAssertEqual(presentation.visibilityValueTitle(isVisible: true), "Show")
        XCTAssertEqual(presentation.visibilityValueTitle(isVisible: false), "Hide")
    }
}
