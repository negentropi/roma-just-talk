import Foundation
@testable import VoiceInkCore

final class SpecialShortcutKeyEvidencePolicyTests: XCTestCase {
    func testReliablePressContextAllowsSpecialShortcutCommit() {
        XCTAssertFalse(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext()
            )
        )
    }

    func testTypingEvidenceDiscardsSpecialShortcut() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)
            )
        )
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(didReleaseOtherKeyDuringPress: true)
            )
        )
    }

    func testUnreliableKeyEvidenceFailsClosed() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(hasReliableKeyEvidence: false)
            )
        )
    }
}
