import Foundation
@testable import VoiceInkCore

final class PromptTriggerPolicyTests: XCTestCase {
    func testAddingTriggerWordTrimsAndRejectsBlankAndCaseInsensitiveDuplicate() {
        XCTAssertEqual(
            VoiceInkPromptTriggerPolicy.addingTriggerWord("  Roma  ", to: ["Dictate"]),
            ["Dictate", "Roma"]
        )
        XCTAssertNil(VoiceInkPromptTriggerPolicy.addingTriggerWord(" \n\t ", to: ["Dictate"]))
        XCTAssertNil(VoiceInkPromptTriggerPolicy.addingTriggerWord("dictate", to: ["Dictate"]))
    }

    func testDetectStripsLeadingTriggerAndCapitalizesRemainingText() throws {
        let promptId = UUID()
        let match = try XCTUnwrap(
            VoiceInkPromptTriggerPolicy.detect(
                in: " email, send this",
                triggers: [
                    VoiceInkPromptTrigger(promptId: promptId, triggerWords: ["email"])
                ]
            )
        )

        XCTAssertEqual(match.promptId, promptId)
        XCTAssertEqual(match.triggerWord, "email")
        XCTAssertEqual(match.processedText, "Send this")
    }

    func testDetectStripsTrailingTriggerBeforeLeadingAndKeepsPromptOrder() throws {
        let notePromptId = UUID()
        let emailPromptId = UUID()
        let match = try XCTUnwrap(
            VoiceInkPromptTriggerPolicy.detect(
                in: "please send, email!",
                triggers: [
                    VoiceInkPromptTrigger(promptId: notePromptId, triggerWords: ["note"]),
                    VoiceInkPromptTrigger(promptId: emailPromptId, triggerWords: ["email"])
                ]
            )
        )

        XCTAssertEqual(match.promptId, emailPromptId)
        XCTAssertEqual(match.triggerWord, "email")
        XCTAssertEqual(match.processedText, "Please send")
    }

    func testDetectUsesLongestTriggerAndRejectsWordPrefix() throws {
        let promptId = UUID()
        let match = try XCTUnwrap(
            VoiceInkPromptTriggerPolicy.detect(
                in: "do it now",
                triggers: [
                    VoiceInkPromptTrigger(promptId: promptId, triggerWords: ["do", "do it"])
                ]
            )
        )

        XCTAssertEqual(match.triggerWord, "do it")
        XCTAssertEqual(match.processedText, "Now")
        XCTAssertNil(
            VoiceInkPromptTriggerPolicy.detect(
                in: "domain update",
                triggers: [
                    VoiceInkPromptTrigger(promptId: promptId, triggerWords: ["do"])
                ]
            )
        )
    }

    func testDetectStripsSameTriggerFromBothEnds() throws {
        let promptId = UUID()
        let match = try XCTUnwrap(
            VoiceInkPromptTriggerPolicy.detect(
                in: "email, send this email",
                triggers: [
                    VoiceInkPromptTrigger(promptId: promptId, triggerWords: ["email"])
                ]
            )
        )

        XCTAssertEqual(match.triggerWord, "email")
        XCTAssertEqual(match.processedText, "Send this")
    }
}
