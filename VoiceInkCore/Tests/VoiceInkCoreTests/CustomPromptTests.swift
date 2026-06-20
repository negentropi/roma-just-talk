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

    func testCustomPromptPolicyAddingPromptSelectsOnlyFirstPrompt() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let firstPrompt = VoiceInkCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = VoiceInkCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        let firstState = VoiceInkCustomPromptPolicy.addingPrompt(
            firstPrompt,
            to: [],
            selectedPromptId: nil
        )
        XCTAssertEqual(firstState.prompts.map(\.id), [firstId])
        XCTAssertEqual(firstState.selectedPromptId, firstId)

        let secondState = VoiceInkCustomPromptPolicy.addingPrompt(
            secondPrompt,
            to: firstState.prompts,
            selectedPromptId: firstState.selectedPromptId
        )
        XCTAssertEqual(secondState.prompts.map(\.id), [firstId, secondId])
        XCTAssertEqual(secondState.selectedPromptId, firstId)
    }

    func testCustomPromptPolicyUpdatingPromptReplacesMatchingPromptOnly() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
        let selectedId = secondId
        let firstPrompt = VoiceInkCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = VoiceInkCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")
        let updatedSecondPrompt = VoiceInkCustomPrompt(
            id: secondId,
            title: "Updated",
            promptText: "Updated prompt"
        )

        let updatedState = VoiceInkCustomPromptPolicy.updatingPrompt(
            updatedSecondPrompt,
            in: [firstPrompt, secondPrompt],
            selectedPromptId: selectedId
        )

        XCTAssertEqual(updatedState.prompts.map(\.title), ["First", "Updated"])
        XCTAssertEqual(updatedState.selectedPromptId, selectedId)

        let missingPrompt = VoiceInkCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
            title: "Missing",
            promptText: "Missing prompt"
        )
        let missingState = VoiceInkCustomPromptPolicy.updatingPrompt(
            missingPrompt,
            in: [firstPrompt, secondPrompt],
            selectedPromptId: selectedId
        )

        XCTAssertEqual(missingState.prompts, [firstPrompt, secondPrompt])
        XCTAssertEqual(missingState.selectedPromptId, selectedId)
    }

    func testCustomPromptPolicyDeletingPromptRepairsSelectionWhenNeeded() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000206")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000207")!
        let firstPrompt = VoiceInkCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = VoiceInkCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        let selectedDeletedState = VoiceInkCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt, secondPrompt],
            selectedPromptId: firstId
        )
        XCTAssertEqual(selectedDeletedState.prompts.map(\.id), [secondId])
        XCTAssertEqual(selectedDeletedState.selectedPromptId, secondId)

        let unselectedDeletedState = VoiceInkCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt, secondPrompt],
            selectedPromptId: secondId
        )
        XCTAssertEqual(unselectedDeletedState.prompts.map(\.id), [secondId])
        XCTAssertEqual(unselectedDeletedState.selectedPromptId, secondId)

        let lastSelectedDeletedState = VoiceInkCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt],
            selectedPromptId: firstId
        )
        XCTAssertTrue(lastSelectedDeletedState.prompts.isEmpty)
        XCTAssertNil(lastSelectedDeletedState.selectedPromptId)
    }

    func testCustomPromptPolicySelectsFirstPromptOnlyWhenEnablingEnhancementWithoutSelection() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000208")!
        let staleId = UUID(uuidString: "00000000-0000-0000-0000-000000000209")!
        let firstPrompt = VoiceInkCustomPrompt(id: firstId, title: "First", promptText: "First prompt")

        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(nil, prompts: [firstPrompt]),
            firstId
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(staleId, prompts: [firstPrompt]),
            staleId
        )
        XCTAssertNil(VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(nil, prompts: []))
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

    func testCustomPromptPolicyBuildsStartupStoreStateInMacOSRepairOrder() {
        let storedPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let stalePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let storedPrompt = VoiceInkCustomPrompt(
            id: storedPromptId,
            title: "Stored",
            promptText: "Stored prompt"
        )

        let repairedState = VoiceInkCustomPromptPolicy.startupStoreState(
            loadedPrompts: [storedPrompt],
            selectedPromptId: stalePromptId,
            isEnhancementEnabled: true
        )

        XCTAssertEqual(
            repairedState.prompts.map(\.id),
            [
                storedPromptId,
                VoiceInkPredefinedPrompts.defaultPromptId,
                VoiceInkPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertEqual(repairedState.selectedPromptId, storedPromptId)

        let emptyState = VoiceInkCustomPromptPolicy.startupStoreState(
            loadedPrompts: [],
            selectedPromptId: nil,
            isEnhancementEnabled: true
        )
        XCTAssertEqual(
            emptyState.prompts.map(\.id),
            [
                VoiceInkPredefinedPrompts.defaultPromptId,
                VoiceInkPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertNil(emptyState.selectedPromptId)
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

    func testCustomPromptDraftSaveabilityPreservesMacOSEmptyStringRule() {
        XCTAssertFalse(
            VoiceInkCustomPromptPolicy.isSaveableCustomPromptDraft(
                VoiceInkCustomPromptDraft(
                    title: "",
                    promptText: "Prompt",
                    icon: "doc.text.fill",
                    description: "",
                    triggerWords: [],
                    useSystemInstructions: true
                )
            )
        )
        XCTAssertFalse(
            VoiceInkCustomPromptPolicy.isSaveableCustomPromptDraft(
                VoiceInkCustomPromptDraft(
                    title: "Title",
                    promptText: "",
                    icon: "doc.text.fill",
                    description: "",
                    triggerWords: [],
                    useSystemInstructions: true
                )
            )
        )
        XCTAssertTrue(
            VoiceInkCustomPromptPolicy.isSaveableCustomPromptDraft(
                VoiceInkCustomPromptDraft(
                    title: " ",
                    promptText: " ",
                    icon: "doc.text.fill",
                    description: "",
                    triggerWords: [],
                    useSystemInstructions: true
                )
            )
        )
    }

    func testCustomPromptPolicyBuildsNewPromptFromDraft() {
        let prompt = VoiceInkCustomPromptPolicy.customPrompt(
            from: VoiceInkCustomPromptDraft(
                title: "Proofread",
                promptText: "Fix grammar.",
                icon: "pencil",
                description: "",
                triggerWords: ["proof"],
                useSystemInstructions: false
            )
        )

        XCTAssertEqual(prompt.title, "Proofread")
        XCTAssertEqual(prompt.promptText, "Fix grammar.")
        XCTAssertEqual(prompt.icon, "pencil")
        XCTAssertNil(prompt.description)
        XCTAssertFalse(prompt.isPredefined)
        XCTAssertEqual(prompt.triggerWords, ["proof"])
        XCTAssertFalse(prompt.useSystemInstructions)
    }

    func testCustomPromptPolicyAppliesDraftToCustomPrompt() {
        let existing = VoiceInkCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            title: "Old",
            promptText: "Old prompt",
            isActive: true,
            icon: "old.icon",
            description: "Old description",
            isPredefined: false,
            triggerWords: ["old"],
            useSystemInstructions: true
        )

        let updated = VoiceInkCustomPromptPolicy.prompt(
            existing,
            applying: VoiceInkCustomPromptDraft(
                title: "New",
                promptText: "New prompt",
                icon: "new.icon",
                description: "",
                triggerWords: ["new"],
                useSystemInstructions: false
            )
        )

        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.title, "New")
        XCTAssertEqual(updated.promptText, "New prompt")
        XCTAssertTrue(updated.isActive)
        XCTAssertEqual(updated.icon, "new.icon")
        XCTAssertNil(updated.description)
        XCTAssertFalse(updated.isPredefined)
        XCTAssertEqual(updated.triggerWords, ["new"])
        XCTAssertFalse(updated.useSystemInstructions)
    }

    func testCustomPromptPolicyAppliesOnlyTriggerWordsToPredefinedPrompt() {
        let existing = VoiceInkCustomPrompt(
            id: VoiceInkPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Template prompt",
            isActive: true,
            icon: "template.icon",
            description: "Template description",
            isPredefined: true,
            triggerWords: ["old"],
            useSystemInstructions: true
        )

        let updated = VoiceInkCustomPromptPolicy.prompt(
            existing,
            applying: VoiceInkCustomPromptDraft(
                title: "Changed",
                promptText: "Changed prompt",
                icon: "changed.icon",
                description: "",
                triggerWords: ["new"],
                useSystemInstructions: false
            )
        )

        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.title, existing.title)
        XCTAssertEqual(updated.promptText, existing.promptText)
        XCTAssertTrue(updated.isActive)
        XCTAssertEqual(updated.icon, existing.icon)
        XCTAssertEqual(updated.description, existing.description)
        XCTAssertTrue(updated.isPredefined)
        XCTAssertEqual(updated.triggerWords, ["new"])
        XCTAssertTrue(updated.useSystemInstructions)
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

    func testCustomPromptPresentationPreservesIconCatalogAndGridCopy() {
        XCTAssertEqual(VoiceInkCustomPromptPresentation.defaultIconSystemName, "doc.text.fill")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.iconSystemNames.first, "doc.text.fill")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.iconSystemNames.last, "hand.thumbsup.fill")
        XCTAssertTrue(VoiceInkCustomPromptPresentation.iconSystemNames.contains("bubble.left.and.bubble.right.fill"))
        XCTAssertTrue(VoiceInkCustomPromptPresentation.iconSystemNames.contains("brain.head.profile"))
        XCTAssertEqual(VoiceInkCustomPromptPresentation.addPromptTitle, "Add New")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.addPromptSystemImageName, "plus.circle.fill")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.promptGridEmptyText, "No prompts available")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.promptGridInfoSystemImageName, "info.circle")
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.promptGridHelpText,
            "Double-click to edit • Right-click for more options"
        )
        XCTAssertEqual(VoiceInkCustomPromptPresentation.addPromptHelpText, "Add new prompt")
    }

    func testCustomPromptPresentationPreservesEditorCopy() {
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.editorTitle(
                isEditingPredefinedPrompt: true,
                isAddingPrompt: false
            ),
            "Edit Trigger Words"
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.editorTitle(
                isEditingPredefinedPrompt: false,
                isAddingPrompt: true
            ),
            "New Prompt"
        )
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.editorTitle(
                isEditingPredefinedPrompt: false,
                isAddingPrompt: false
            ),
            "Edit Prompt"
        )
        XCTAssertEqual(VoiceInkCustomPromptPresentation.editingHeaderTitle(for: "Assistant"), "Editing: Assistant")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.promptNamePlaceholder, "Prompt Name")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.descriptionPlaceholder, "Brief description")
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.promptInstructionsPlaceholder,
            "Enter your custom prompt instructions here..."
        )
        XCTAssertEqual(VoiceInkCustomPromptPresentation.useSystemTemplateTitle, "Use System Template")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.triggerWordsSectionTitle, "Trigger Words")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.triggerWordPlaceholder, "Add trigger word")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.addTriggerWordSystemImageName, "plus.circle.fill")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.removeTriggerWordSystemImageName, "xmark")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.noTriggerWordsText, "No trigger words added")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.startWithTemplateTitle, "Start with Template")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.startWithTemplateIconSystemName, "sparkles")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.closeSystemImageName, "xmark")
    }

    func testCustomPromptPresentationFormatsTriggerSummaryAndDeleteAlert() throws {
        XCTAssertNil(VoiceInkCustomPromptPresentation.triggerSummary(for: []))

        let singleSummary = try XCTUnwrap(VoiceInkCustomPromptPresentation.triggerSummary(for: ["email"]))
        XCTAssertEqual(singleSummary.iconSystemName, "mic.fill")
        XCTAssertEqual(singleSummary.text, "\"email...\"")

        let multiSummary = try XCTUnwrap(VoiceInkCustomPromptPresentation.triggerSummary(for: ["email", "reply"]))
        XCTAssertEqual(multiSummary.text, "\"email...\" +1")

        XCTAssertEqual(VoiceInkCustomPromptPresentation.editActionTitle, "Edit")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.editActionSystemImageName, "pencil")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.deleteActionTitle, "Delete")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.deleteActionSystemImageName, "trash")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.cancelActionTitle, "Cancel")
        XCTAssertEqual(VoiceInkCustomPromptPresentation.deletePromptConfirmationTitle, "Delete Prompt?")
        XCTAssertEqual(
            VoiceInkCustomPromptPresentation.deletePromptConfirmationMessage(promptTitle: "Email"),
            "Are you sure you want to delete 'Email' prompt? This action cannot be undone."
        )
    }
}
