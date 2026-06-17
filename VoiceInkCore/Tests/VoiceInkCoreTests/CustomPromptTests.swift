import Foundation
@testable import VoiceInkCore

final class CustomPromptTests: XCTestCase {
    func testCustomPromptDefaultsMatchExistingMacOSPromptRecord() {
        let prompt = VoiceInkCustomPrompt(title: "Title", promptText: "Prompt")

        XCTAssertEqual(prompt.title, "Title")
        XCTAssertEqual(prompt.promptText, "Prompt")
        XCTAssertFalse(prompt.isActive)
        XCTAssertEqual(prompt.icon, "doc.text.fill")
        XCTAssertNil(prompt.description)
        XCTAssertFalse(prompt.isPredefined)
        XCTAssertTrue(prompt.triggerWords.isEmpty)
        XCTAssertTrue(prompt.useSystemInstructions)
    }

    func testCustomPromptDecodesMissingUseSystemInstructionsAsTrue() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-0000000000ab",
          "title": "Legacy",
          "promptText": "Clean up this text.",
          "isActive": false,
          "icon": "doc.text.fill",
          "isPredefined": false,
          "triggerWords": ["clean"]
        }
        """.data(using: .utf8)!

        let prompt = try JSONDecoder().decode(VoiceInkCustomPrompt.self, from: json)

        XCTAssertEqual(prompt.id, UUID(uuidString: "00000000-0000-0000-0000-0000000000ab")!)
        XCTAssertEqual(prompt.triggerWords, ["clean"])
        XCTAssertTrue(prompt.useSystemInstructions)
    }

    func testCustomPromptFinalPromptTextRespectsSystemInstructionFlag() {
        XCTAssertEqual(
            VoiceInkCustomPrompt(
                title: "Assistant",
                promptText: "Answer directly.",
                useSystemInstructions: false
            ).finalPromptText,
            "Answer directly."
        )

        let wrapped = VoiceInkCustomPrompt(
            title: "Default",
            promptText: "Improve clarity.",
            useSystemInstructions: true
        ).finalPromptText

        XCTAssertTrue(wrapped.contains("Improve clarity."))
        XCTAssertTrue(wrapped != "Improve clarity.")
    }

    func testCustomPromptBuildsFromPredefinedPrompt() throws {
        let predefined = try XCTUnwrap(
            VoiceInkPredefinedPrompts.all.first { $0.id == VoiceInkPredefinedPrompts.assistantPromptId }
        )

        let prompt = VoiceInkCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(prompt.id, predefined.id)
        XCTAssertEqual(prompt.title, "Assistant")
        XCTAssertEqual(prompt.promptText, VoiceInkAIPrompts.assistantMode)
        XCTAssertEqual(prompt.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(prompt.description, "AI assistant that provides direct answers to queries")
        XCTAssertTrue(prompt.isPredefined)
        XCTAssertFalse(prompt.useSystemInstructions)
        XCTAssertFalse(prompt.isActive)
        XCTAssertTrue(prompt.triggerWords.isEmpty)
    }

    func testCustomPromptPolicyRepairsExistingPredefinedPromptMetadata() {
        let staleDefaultPrompt = VoiceInkCustomPrompt(
            id: VoiceInkPredefinedPrompts.defaultPromptId,
            title: "Old default",
            promptText: "Old prompt",
            isActive: true,
            icon: "old.icon",
            description: "Old description",
            isPredefined: false,
            triggerWords: ["note"],
            useSystemInstructions: false
        )

        let repaired = VoiceInkCustomPromptPolicy.repairedPredefinedPrompts(in: [staleDefaultPrompt])
        let defaultPrompt = repaired[0]

        XCTAssertEqual(defaultPrompt.id, VoiceInkPredefinedPrompts.defaultPromptId)
        XCTAssertEqual(defaultPrompt.title, "Default")
        XCTAssertEqual(defaultPrompt.icon, "checkmark.seal.fill")
        XCTAssertTrue(defaultPrompt.isPredefined)
        XCTAssertTrue(defaultPrompt.isActive)
        XCTAssertEqual(defaultPrompt.triggerWords, ["note"])
        XCTAssertTrue(defaultPrompt.useSystemInstructions)
        XCTAssertEqual(repaired.map(\.id).last, VoiceInkPredefinedPrompts.assistantPromptId)
    }

    func testCustomPromptPolicyLeavesCustomPromptsInPlaceAndAppendsMissingPredefinedPrompts() {
        let customPromptId = UUID(uuidString: "00000000-0000-0000-0000-0000000000ef")!
        let customPrompt = VoiceInkCustomPrompt(
            id: customPromptId,
            title: "Custom",
            promptText: "Custom text"
        )

        let repaired = VoiceInkCustomPromptPolicy.repairedPredefinedPrompts(in: [customPrompt])

        XCTAssertEqual(
            repaired.map(\.id),
            [
                customPromptId,
                VoiceInkPredefinedPrompts.defaultPromptId,
                VoiceInkPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertFalse(repaired[0].isPredefined)
    }

    func testCustomPromptPolicyReturnsOnlyPromptsWithNonblankTriggerWords() {
        let blank = VoiceInkCustomPrompt(title: "Blank", promptText: "", triggerWords: [" ", "\n"])
        let trigger = VoiceInkCustomPrompt(title: "Trigger", promptText: "", triggerWords: [" email "])

        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.triggerDetectablePrompts(from: [blank, trigger]).map(\.title),
            ["Trigger"]
        )
    }

    func testCustomPromptPolicyRepairsSelectedPromptOnlyWhenEnhancementIsEnabled() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let validId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let staleId = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let prompts = [
            VoiceInkCustomPrompt(id: firstId, title: "First", promptText: "First prompt"),
            VoiceInkCustomPrompt(id: validId, title: "Valid", promptText: "Valid prompt")
        ]

        XCTAssertNil(VoiceInkCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: false, prompts: prompts))
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.repairedSelectedPromptId(staleId, isEnhancementEnabled: false, prompts: prompts),
            staleId
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: true, prompts: prompts),
            firstId
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.repairedSelectedPromptId(staleId, isEnhancementEnabled: true, prompts: prompts),
            firstId
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.repairedSelectedPromptId(validId, isEnhancementEnabled: true, prompts: prompts),
            validId
        )
        XCTAssertNil(VoiceInkCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: true, prompts: []))
    }

    func testCustomPromptPolicyUsesAssistantPromptWithoutSystemInstructions() throws {
        let predefined = try XCTUnwrap(
            VoiceInkPredefinedPrompts.all.first { $0.id == VoiceInkPredefinedPrompts.assistantPromptId }
        )
        let assistantPrompt = VoiceInkCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.basePromptText(activePrompt: assistantPrompt, prompts: [assistantPrompt]),
            VoiceInkAIPrompts.assistantMode
        )
    }

    func testCustomPromptPolicyWrapsNonAssistantActivePrompt() {
        let activePrompt = VoiceInkCustomPrompt(
            title: "Edit",
            promptText: "Make the transcript concise.",
            useSystemInstructions: true
        )

        let promptText = VoiceInkCustomPromptPolicy.basePromptText(
            activePrompt: activePrompt,
            prompts: [activePrompt]
        )

        XCTAssertEqual(promptText, activePrompt.finalPromptText)
        XCTAssertTrue(promptText.contains("Make the transcript concise."))
        XCTAssertTrue(promptText != activePrompt.promptText)
    }

    func testCustomPromptPolicyFallsBackToDefaultPromptText() throws {
        let customPrompt = VoiceInkCustomPrompt(
            title: "Custom",
            promptText: "Use custom rules.",
            useSystemInstructions: true
        )
        let predefined = try XCTUnwrap(
            VoiceInkPredefinedPrompts.all.first { $0.id == VoiceInkPredefinedPrompts.defaultPromptId }
        )
        let defaultPrompt = VoiceInkCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.basePromptText(
                activePrompt: nil,
                prompts: [customPrompt, defaultPrompt]
            ),
            defaultPrompt.finalPromptText
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.basePromptText(activePrompt: nil, prompts: [customPrompt]),
            customPrompt.finalPromptText
        )
        XCTAssertEqual(VoiceInkCustomPromptPolicy.basePromptText(activePrompt: nil, prompts: []), "")
    }

    func testCustomPromptEncodingPreservesExistingMacOSKeys() throws {
        let prompt = VoiceInkCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000cd")!,
            title: "Export",
            promptText: "Keep names exact.",
            isActive: true,
            icon: "tag.fill",
            description: "Exported prompt",
            isPredefined: false,
            triggerWords: ["names"],
            useSystemInstructions: false
        )

        let data = try JSONEncoder().encode(prompt)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["id"] as? String, "00000000-0000-0000-0000-0000000000CD")
        XCTAssertEqual(object?["title"] as? String, "Export")
        XCTAssertEqual(object?["promptText"] as? String, "Keep names exact.")
        XCTAssertEqual(object?["isActive"] as? Bool, true)
        XCTAssertEqual(object?["icon"] as? String, "tag.fill")
        XCTAssertEqual(object?["description"] as? String, "Exported prompt")
        XCTAssertEqual(object?["isPredefined"] as? Bool, false)
        XCTAssertEqual(object?["triggerWords"] as? [String], ["names"])
        XCTAssertEqual(object?["useSystemInstructions"] as? Bool, false)
    }
}
