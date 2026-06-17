import Foundation
@testable import VoiceInkCore

final class PromptTriggerPolicyTests: XCTestCase {
    func testPromptDetectionPolicyReturnsNoMatchResultWithOriginalState() {
        let originalPromptId = UUID()
        let prompt = VoiceInkCustomPrompt(
            title: "Email",
            promptText: "Write an email.",
            triggerWords: ["email"]
        )

        let result = VoiceInkPromptDetectionPolicy.analyzeText(
            "please write this normally",
            prompts: [prompt],
            isEnhancementEnabled: true,
            selectedPromptId: originalPromptId
        )

        XCTAssertFalse(result.shouldEnableAI)
        XCTAssertNil(result.selectedPromptId)
        XCTAssertEqual(result.processedText, "please write this normally")
        XCTAssertNil(result.detectedTriggerWord)
        XCTAssertTrue(result.originalEnhancementState)
        XCTAssertEqual(result.originalPromptId, originalPromptId)
    }

    func testPromptDetectionPolicyBuildsDetectedEnhancementResult() {
        let originalPromptId = UUID()
        let emailPromptId = UUID()
        let emailPrompt = VoiceInkCustomPrompt(
            id: emailPromptId,
            title: "Email",
            promptText: "Write an email.",
            triggerWords: ["email"]
        )

        let result = VoiceInkPromptDetectionPolicy.analyzeText(
            "email, send a follow up",
            prompts: [emailPrompt],
            isEnhancementEnabled: false,
            selectedPromptId: originalPromptId
        )

        XCTAssertTrue(result.shouldEnableAI)
        XCTAssertEqual(result.selectedPromptId, emailPromptId)
        XCTAssertEqual(result.processedText, "Send a follow up")
        XCTAssertEqual(result.detectedTriggerWord, "email")
        XCTAssertFalse(result.originalEnhancementState)
        XCTAssertEqual(result.originalPromptId, originalPromptId)
    }

    func testPromptDetectionPolicyIgnoresPromptsWithoutTriggerWords() {
        let prompt = VoiceInkCustomPrompt(
            title: "Blank",
            promptText: "No trigger.",
            triggerWords: [" ", "\n"]
        )

        let result = VoiceInkPromptDetectionPolicy.analyzeText(
            "blank, should not match",
            prompts: [prompt],
            isEnhancementEnabled: false,
            selectedPromptId: nil
        )

        XCTAssertFalse(result.shouldEnableAI)
        XCTAssertNil(result.selectedPromptId)
        XCTAssertEqual(result.processedText, "blank, should not match")
        XCTAssertNil(result.detectedTriggerWord)
        XCTAssertFalse(result.originalEnhancementState)
        XCTAssertNil(result.originalPromptId)
    }

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
