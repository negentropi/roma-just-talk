@testable import VoiceInkCore

final class SpecialShortcutEvidenceTests: XCTestCase {
    func testPointerActivityDiscardsSpecialShortcut() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(didUsePointerDuringPress: true)
            )
        )
    }
}
