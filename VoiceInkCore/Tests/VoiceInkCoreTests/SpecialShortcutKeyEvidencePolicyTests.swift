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

    func testShortcutInterruptionPolicyPreservesMacOSWindow() {
        XCTAssertEqual(VoiceInkShortcutInterruptionPolicy.interruptionWindow, 1.0)
        XCTAssertTrue(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 10.5))
        XCTAssertTrue(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.0))
        XCTAssertFalse(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.1))
    }
}
