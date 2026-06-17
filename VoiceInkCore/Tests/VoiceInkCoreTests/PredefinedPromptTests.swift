import Foundation
@testable import VoiceInkCore

final class PredefinedPromptTests: XCTestCase {
    func testStablePromptIdsPreserveMacOSStorageIdentity() {
        XCTAssertEqual(
            VoiceInkPredefinedPrompts.defaultPromptId,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        XCTAssertEqual(
            VoiceInkPredefinedPrompts.assistantPromptId,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
    }

    func testPromptOrderKeepsDefaultBeforeAssistant() {
        XCTAssertEqual(
            VoiceInkPredefinedPrompts.all.map(\.id),
            [
                VoiceInkPredefinedPrompts.defaultPromptId,
                VoiceInkPredefinedPrompts.assistantPromptId
            ]
        )
    }

    func testDefaultPromptUsesSystemDefaultTemplateAndSystemInstructions() throws {
        let prompt = try XCTUnwrap(
            VoiceInkPredefinedPrompts.all.first { $0.id == VoiceInkPredefinedPrompts.defaultPromptId }
        )
        let template = try XCTUnwrap(VoiceInkPromptTemplates.macTemplate(named: "System Default"))

        XCTAssertEqual(prompt.title, "Default")
        XCTAssertEqual(prompt.promptText, template.promptText)
        XCTAssertEqual(prompt.icon, "checkmark.seal.fill")
        XCTAssertEqual(prompt.description, "Default mode to improved clarity and accuracy of the transcription")
        XCTAssertTrue(prompt.useSystemInstructions)
    }

    func testAssistantPromptUsesAssistantModeWithoutSystemInstructions() throws {
        let prompt = try XCTUnwrap(
            VoiceInkPredefinedPrompts.all.first { $0.id == VoiceInkPredefinedPrompts.assistantPromptId }
        )

        XCTAssertEqual(prompt.title, "Assistant")
        XCTAssertEqual(prompt.promptText, VoiceInkAIPrompts.assistantMode)
        XCTAssertEqual(prompt.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(prompt.description, "AI assistant that provides direct answers to queries")
        XCTAssertFalse(prompt.useSystemInstructions)
    }
}
