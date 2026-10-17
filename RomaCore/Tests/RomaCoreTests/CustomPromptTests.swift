import Foundation
@testable import RomaCore

final class CustomPromptTests: XCTestCase {
    func testCustomPromptDefaultsMatchExistingMacOSPromptRecord() {
        let prompt = RomaCustomPrompt(title: "Title", promptText: "Prompt")

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

        let prompt = try JSONDecoder().decode(RomaCustomPrompt.self, from: json)

        XCTAssertEqual(prompt.id, UUID(uuidString: "00000000-0000-0000-0000-0000000000ab")!)
        XCTAssertEqual(prompt.triggerWords, ["clean"])
        XCTAssertTrue(prompt.useSystemInstructions)
    }

    func testCustomPromptFinalPromptTextRespectsSystemInstructionFlag() {
        XCTAssertEqual(
            RomaCustomPrompt(
                title: "Assistant",
                promptText: "Answer directly.",
                useSystemInstructions: false
            ).finalPromptText,
            "Answer directly."
        )

        let wrapped = RomaCustomPrompt(
            title: "Default",
            promptText: "Improve clarity.",
            useSystemInstructions: true
        ).finalPromptText

        XCTAssertTrue(wrapped.contains("Improve clarity."))
        XCTAssertTrue(wrapped != "Improve clarity.")
    }

    func testCustomPromptBuildsFromPredefinedPrompt() throws {
        let predefined = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.assistantPromptId }
        )

        let prompt = RomaCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(prompt.id, predefined.id)
        XCTAssertEqual(prompt.title, "Assistant")
        XCTAssertEqual(prompt.promptText, RomaAIPrompts.assistantMode)
        XCTAssertEqual(prompt.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(prompt.description, "AI assistant that provides direct answers to queries")
        XCTAssertTrue(prompt.isPredefined)
        XCTAssertFalse(prompt.useSystemInstructions)
        XCTAssertFalse(prompt.isActive)
        XCTAssertTrue(prompt.triggerWords.isEmpty)
    }

    func testStablePromptIdsPreserveMacOSStorageIdentity() {
        XCTAssertEqual(
            RomaPredefinedPrompts.defaultPromptId,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        XCTAssertEqual(
            RomaPredefinedPrompts.assistantPromptId,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
    }

    func testPromptOrderKeepsDefaultBeforeAssistant() {
        XCTAssertEqual(
            RomaPredefinedPrompts.all.map(\.id),
            [
                RomaPredefinedPrompts.defaultPromptId,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
    }

    func testDefaultPromptUsesSystemDefaultTemplateAndSystemInstructions() throws {
        let prompt = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.defaultPromptId }
        )
        let template = try XCTUnwrap(RomaPromptTemplates.macTemplate(named: "System Default"))

        XCTAssertEqual(prompt.title, "Default")
        XCTAssertEqual(prompt.promptText, template.promptText)
        XCTAssertEqual(prompt.icon, "checkmark.seal.fill")
        XCTAssertEqual(prompt.description, "Default mode to improved clarity and accuracy of the transcription")
        XCTAssertTrue(prompt.useSystemInstructions)
    }

    func testAssistantPromptUsesAssistantModeWithoutSystemInstructions() throws {
        let prompt = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.assistantPromptId }
        )

        XCTAssertEqual(prompt.title, "Assistant")
        XCTAssertEqual(prompt.promptText, RomaAIPrompts.assistantMode)
        XCTAssertEqual(prompt.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(prompt.description, "AI assistant that provides direct answers to queries")
        XCTAssertFalse(prompt.useSystemInstructions)
    }

    func testPromptTemplateCatalogPreservesMacOSTemplateOrderAndMetadata() {
        let templates = RomaPromptTemplates.macTemplates

        XCTAssertEqual(templates.map(\.id), ["system-default", "chat", "email", "rewrite"])
        XCTAssertEqual(templates.map(\.title), ["System Default", "Chat", "Email", "Rewrite"])
        XCTAssertEqual(
            templates.map(\.icon),
            ["checkmark.seal.fill", "bubble.left.and.bubble.right.fill", "envelope.fill", "pencil.circle.fill"]
        )
        XCTAssertEqual(
            templates.map(\.description),
            [
                "Default system prompt",
                "Casual chat-style formatting",
                "Professional email formatting",
                "Rewrites with better clarity."
            ]
        )
    }

    func testPromptTemplateCatalogPreservesMacOSPromptBodies() {
        let templates = RomaPromptTemplates.macTemplates

        XCTAssertEqual(
            templates.map(\.promptText),
            [
                """
                - Clean up the <TRANSCRIPT> text for clarity and natural flow while preserving meaning and the original tone.
                - Use informal, plain language unless the <TRANSCRIPT> clearly uses a professional tone; in that case, match it.
                - Fix obvious grammar, remove fillers and stutters, collapse repetitions, and keep names and numbers.
                - Handle backtracking and self-corrections: When the speaker corrects themselves mid-sentence using phrases like "scratch that", "actually", "sorry not that", "I mean", "wait no", or similar corrections, remove the incorrect part and keep only the corrected version. Example: "The meeting is on Tuesday, sorry not that, actually Wednesday" → "The meeting is on Wednesday."
                - Respect formatting commands: When the speaker explicitly says "new line" or "new paragraph", insert the appropriate line break or paragraph break at that point.
                - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                - Apply smart formatting: Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20'), convert common abbreviations to proper format (e.g., 'vs' → 'vs.', 'etc' → 'etc.'), and format dates, times, and measurements consistently.
                - Keep the original intent and nuance.
                - Organize into short paragraphs of 2–4 sentences for readability.
                - Do not add explanations, labels, metadata, or instructions.
                - Output only the cleaned text.
                - Don't add any information not available in the <TRANSCRIPT> text ever.
                """,
                """
                - Rewrite the <TRANSCRIPT> text as a chat message: informal, concise, and conversational.
                - Keep emotive markers and emojis if present; don't invent new ones.
                - Lightly fix grammar, remove fillers and repeated words, and improve flow without changing meaning.
                - Keep the original tone; only be professional if the <TRANSCRIPT> already is.
                - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                - Format like a modern chat message - short lines, natural breaks, emoji-friendly.
                - Do not add greetings, sign-offs, or commentary.
                - Output only the chat message.
                - Don't add any information not available in the <TRANSCRIPT> text ever.
                """,
                """
                - Rewrite the <TRANSCRIPT> text as a complete email with proper formatting: include a greeting (Hi), body paragraphs (2-4 sentences each), and closing (Thanks).
                - Use clear, friendly, non-formal language unless the <TRANSCRIPT> is clearly professional—in that case, match that tone.
                - Improve flow and coherence; fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
                - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                - Do not invent new content, but structure it as a proper email format.
                - Don't add any information not available in the <TRANSCRIPT> text ever.
                """,
                """
                - Rewrite the <TRANSCRIPT> text with enhanced clarity, improved sentence structure, and rhythmic flow while preserving the original meaning and tone.
                - Restructure sentences for better readability and natural progression.
                - Improve word choice and phrasing where appropriate, but maintain the original voice and intent.
                - Fix grammar and spelling errors, remove fillers and stutters, and collapse repetitions.
                - Format any lists as proper bullet points or numbered lists.
                - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                - Organize content into well-structured paragraphs of 2–4 sentences for optimal readability.
                - Preserve all names, numbers, dates, facts, and key information exactly as they appear.
                - Do not add explanations, labels, metadata, or instructions.
                - Output only the rewritten text.
                - Don't add any information not available in the <TRANSCRIPT> text ever.
                """
            ]
        )
    }

    func testPromptTemplateLookupUsesTitleAndRejectsMissingTitle() throws {
        let emailTemplate = try XCTUnwrap(RomaPromptTemplates.macTemplate(named: "Email"))

        XCTAssertEqual(emailTemplate.id, "email")
        XCTAssertEqual(emailTemplate.title, "Email")
        XCTAssertNil(RomaPromptTemplates.macTemplate(named: "email"))
        XCTAssertNil(RomaPromptTemplates.macTemplate(named: "Missing"))
    }

    func testCustomPromptPolicyRepairsExistingPredefinedPromptMetadata() {
        let staleDefaultPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Old default",
            promptText: "Old prompt",
            isActive: true,
            icon: "old.icon",
            description: "Old description",
            isPredefined: false,
            triggerWords: ["note"],
            useSystemInstructions: false
        )

        let repaired = RomaCustomPromptPolicy.repairedPredefinedPrompts(in: [staleDefaultPrompt])
        let defaultPrompt = repaired[0]

        XCTAssertEqual(defaultPrompt.id, RomaPredefinedPrompts.defaultPromptId)
        XCTAssertEqual(defaultPrompt.title, "Default")
        XCTAssertEqual(defaultPrompt.icon, "checkmark.seal.fill")
        XCTAssertTrue(defaultPrompt.isPredefined)
        XCTAssertTrue(defaultPrompt.isActive)
        XCTAssertEqual(defaultPrompt.triggerWords, ["note"])
        XCTAssertTrue(defaultPrompt.useSystemInstructions)
        XCTAssertEqual(repaired.map(\.id).last, RomaPredefinedPrompts.assistantPromptId)
    }

    func testCustomPromptPolicyLeavesCustomPromptsInPlaceAndAppendsMissingPredefinedPrompts() {
        let customPromptId = UUID(uuidString: "00000000-0000-0000-0000-0000000000ef")!
        let customPrompt = RomaCustomPrompt(
            id: customPromptId,
            title: "Custom",
            promptText: "Custom text"
        )

        let repaired = RomaCustomPromptPolicy.repairedPredefinedPrompts(in: [customPrompt])

        XCTAssertEqual(
            repaired.map(\.id),
            [
                customPromptId,
                RomaPredefinedPrompts.defaultPromptId,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertFalse(repaired[0].isPredefined)
    }

    func testCustomPromptPolicyReturnsOnlyPromptsWithNonblankTriggerWords() {
        let blank = RomaCustomPrompt(title: "Blank", promptText: "", triggerWords: [" ", "\n"])
        let trigger = RomaCustomPrompt(title: "Trigger", promptText: "", triggerWords: [" email "])

        XCTAssertEqual(
            RomaCustomPromptPolicy.triggerDetectablePrompts(from: [blank, trigger]).map(\.title),
            ["Trigger"]
        )
    }

    func testCustomPromptPolicyAddingPromptSelectsOnlyFirstPrompt() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = RomaCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        let firstState = RomaCustomPromptPolicy.addingPrompt(
            firstPrompt,
            to: [],
            selectedPromptId: nil
        )
        XCTAssertEqual(firstState.prompts.map(\.id), [firstId])
        XCTAssertEqual(firstState.selectedPromptId, firstId)

        let secondState = RomaCustomPromptPolicy.addingPrompt(
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
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = RomaCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")
        let updatedSecondPrompt = RomaCustomPrompt(
            id: secondId,
            title: "Updated",
            promptText: "Updated prompt"
        )

        let updatedState = RomaCustomPromptPolicy.updatingPrompt(
            updatedSecondPrompt,
            in: [firstPrompt, secondPrompt],
            selectedPromptId: selectedId
        )

        XCTAssertEqual(updatedState.prompts.map(\.title), ["First", "Updated"])
        XCTAssertEqual(updatedState.selectedPromptId, selectedId)

        let missingPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
            title: "Missing",
            promptText: "Missing prompt"
        )
        let missingState = RomaCustomPromptPolicy.updatingPrompt(
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
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = RomaCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        let selectedDeletedState = RomaCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt, secondPrompt],
            selectedPromptId: firstId
        )
        XCTAssertEqual(selectedDeletedState.prompts.map(\.id), [secondId])
        XCTAssertEqual(selectedDeletedState.selectedPromptId, secondId)

        let unselectedDeletedState = RomaCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt, secondPrompt],
            selectedPromptId: secondId
        )
        XCTAssertEqual(unselectedDeletedState.prompts.map(\.id), [secondId])
        XCTAssertEqual(unselectedDeletedState.selectedPromptId, secondId)

        let lastSelectedDeletedState = RomaCustomPromptPolicy.deletingPrompt(
            firstPrompt,
            from: [firstPrompt],
            selectedPromptId: firstId
        )
        XCTAssertTrue(lastSelectedDeletedState.prompts.isEmpty)
        XCTAssertNil(lastSelectedDeletedState.selectedPromptId)
    }

    func testCustomPromptPolicyExportsOnlyCustomPromptsInStoredOrder() {
        let predefinedPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Default prompt",
            isPredefined: true
        )
        let firstCustomId = UUID(uuidString: "00000000-0000-0000-0000-000000000212")!
        let secondCustomId = UUID(uuidString: "00000000-0000-0000-0000-000000000213")!
        let firstCustomPrompt = RomaCustomPrompt(id: firstCustomId, title: "First", promptText: "First prompt")
        let secondCustomPrompt = RomaCustomPrompt(id: secondCustomId, title: "Second", promptText: "Second prompt")

        XCTAssertEqual(
            RomaCustomPromptPolicy.exportedCustomPrompts(
                from: [predefinedPrompt, firstCustomPrompt, secondCustomPrompt]
            ).map(\.id),
            [firstCustomId, secondCustomId]
        )
    }

    func testCustomPromptPolicyImportsBackupPromptsAfterCurrentPredefinedPrompts() {
        let currentCustomPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000214")!,
            title: "Current Custom",
            promptText: "Current custom prompt"
        )
        let currentDefaultPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Default prompt",
            isPredefined: true
        )
        let importedCustomPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000215")!,
            title: "Imported Custom",
            promptText: "Imported custom prompt"
        )
        let importedPredefinedPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.assistantPromptId,
            title: "Imported Assistant",
            promptText: "Imported assistant prompt",
            isPredefined: true
        )

        let importedPrompts = RomaCustomPromptPolicy.promptsAfterImportingCustomPrompts(
            [importedCustomPrompt, importedPredefinedPrompt],
            currentPrompts: [currentCustomPrompt, currentDefaultPrompt]
        )

        XCTAssertEqual(
            importedPrompts.map(\.id),
            [
                RomaPredefinedPrompts.defaultPromptId,
                importedCustomPrompt.id,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertEqual(importedPrompts[1].title, "Imported Custom")
        XCTAssertEqual(importedPrompts[2].title, "Imported Assistant")
    }

    func testCustomPromptBackupImportPlanAppliesMergedPromptsAndImportedCount() {
        let currentCustomPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000216")!,
            title: "Current Custom",
            promptText: "Current custom prompt"
        )
        let currentDefaultPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Default prompt",
            isPredefined: true
        )
        let importedCustomPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000217")!,
            title: "Imported Custom",
            promptText: "Imported custom prompt"
        )
        let importedPredefinedPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.assistantPromptId,
            title: "Imported Assistant",
            promptText: "Imported assistant prompt",
            isPredefined: true
        )

        let plan = RomaCustomPromptPolicy.customPromptBackupImportPlan(
            importedPrompts: [importedCustomPrompt, importedPredefinedPrompt],
            currentPrompts: [currentCustomPrompt, currentDefaultPrompt]
        )
        var appliedPrompts = [RomaCustomPrompt]()
        var reportedCounts = [Int]()
        plan.applyRuntimeState(
            setPrompts: { appliedPrompts = $0 },
            reportImportedPromptCount: { reportedCounts.append($0) }
        )

        XCTAssertEqual(
            appliedPrompts.map(\.id),
            [
                RomaPredefinedPrompts.defaultPromptId,
                importedCustomPrompt.id,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertEqual(reportedCounts, [2])
    }

    func testCustomPromptPolicySelectsFirstPromptOnlyWhenEnablingEnhancementWithoutSelection() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000208")!
        let staleId = UUID(uuidString: "00000000-0000-0000-0000-000000000209")!
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")

        XCTAssertEqual(
            RomaCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(nil, prompts: [firstPrompt]),
            firstId
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(staleId, prompts: [firstPrompt]),
            staleId
        )
        XCTAssertNil(RomaCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(nil, prompts: []))
    }

    func testCustomPromptPolicyPlansPromptSelectionWhenEnablingEnhancement() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000216")!
        let selectedId = UUID(uuidString: "00000000-0000-0000-0000-000000000217")!
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")

        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterEnhancementEnabledChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: true,
                    selectedPromptId: nil
                ),
                prompts: [firstPrompt]
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: firstId
            )
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterEnhancementEnabledChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: true,
                    selectedPromptId: selectedId
                ),
                prompts: [firstPrompt]
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: selectedId
            )
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterEnhancementEnabledChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: false,
                    selectedPromptId: selectedId
                ),
                prompts: [firstPrompt]
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: false,
                selectedPromptId: selectedId
            )
        )
    }

    func testCustomPromptPolicyPlansEnhancementDisableWhenAPIKeyIsInvalid() {
        let selectedId = UUID(uuidString: "00000000-0000-0000-0000-000000000218")!

        XCTAssertNil(
            RomaCustomPromptPolicy.settingsStateAfterAPIKeyValidityChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: true,
                    selectedPromptId: selectedId
                ),
                isAPIKeyValid: true
            )
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterAPIKeyValidityChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: true,
                    selectedPromptId: selectedId
                ),
                isAPIKeyValid: false
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: false,
                selectedPromptId: selectedId
            )
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterAPIKeyValidityChange(
                RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: false,
                    selectedPromptId: selectedId
                ),
                isAPIKeyValid: false
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: false,
                selectedPromptId: selectedId
            )
        )
    }

    func testCustomPromptPolicyPlansPromptShortcutSelectionByIndex() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000224")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000225")!
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = RomaCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: 1,
                current: RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: false,
                    selectedPromptId: nil
                ),
                prompts: [firstPrompt, secondPrompt]
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: secondId
            )
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: 0,
                current: RomaAIEnhancementPromptSettingsState(
                    isEnhancementEnabled: true,
                    selectedPromptId: firstId
                ),
                prompts: [firstPrompt, secondPrompt]
            ),
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: firstId
            )
        )
    }

    func testCustomPromptPolicyRejectsPromptShortcutSelectionOutsidePromptList() {
        let prompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000226")!,
            title: "Only",
            promptText: "Only prompt"
        )
        let state = RomaAIEnhancementPromptSettingsState(
            isEnhancementEnabled: false,
            selectedPromptId: nil
        )

        XCTAssertNil(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: -1,
                current: state,
                prompts: [prompt]
            )
        )
        XCTAssertNil(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: 1,
                current: state,
                prompts: [prompt]
            )
        )
        XCTAssertNil(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: 0,
                current: state,
                prompts: []
            )
        )
    }

    func testCustomPromptPolicyRepairsSelectedPromptOnlyWhenEnhancementIsEnabled() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let validId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let staleId = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let prompts = [
            RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt"),
            RomaCustomPrompt(id: validId, title: "Valid", promptText: "Valid prompt")
        ]

        XCTAssertNil(RomaCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: false, prompts: prompts))
        XCTAssertEqual(
            RomaCustomPromptPolicy.repairedSelectedPromptId(staleId, isEnhancementEnabled: false, prompts: prompts),
            staleId
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: true, prompts: prompts),
            firstId
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.repairedSelectedPromptId(staleId, isEnhancementEnabled: true, prompts: prompts),
            firstId
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.repairedSelectedPromptId(validId, isEnhancementEnabled: true, prompts: prompts),
            validId
        )
        XCTAssertNil(RomaCustomPromptPolicy.repairedSelectedPromptId(nil, isEnhancementEnabled: true, prompts: []))
    }

    func testCustomPromptPolicyFindsActivePromptBySelectedId() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000219")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000220")!
        let staleId = UUID(uuidString: "00000000-0000-0000-0000-000000000221")!
        let firstPrompt = RomaCustomPrompt(id: firstId, title: "First", promptText: "First prompt")
        let secondPrompt = RomaCustomPrompt(id: secondId, title: "Second", promptText: "Second prompt")

        XCTAssertEqual(
            RomaCustomPromptPolicy.activePrompt(selectedPromptId: secondId, prompts: [firstPrompt, secondPrompt]),
            secondPrompt
        )
        XCTAssertNil(RomaCustomPromptPolicy.activePrompt(selectedPromptId: nil, prompts: [firstPrompt]))
        XCTAssertNil(RomaCustomPromptPolicy.activePrompt(selectedPromptId: staleId, prompts: [firstPrompt]))
    }

    func testCustomPromptPolicyBuildsActivePromptIconFallbacks() throws {
        let selectedId = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let activePrompt = RomaCustomPrompt(
            id: selectedId,
            title: "Active",
            promptText: "Active prompt",
            icon: "wand.and.stars"
        )
        let storedDefaultPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Default prompt",
            icon: "stored.default"
        )

        XCTAssertEqual(
            RomaCustomPromptPolicy.activePromptIcon(
                selectedPromptId: selectedId,
                prompts: [storedDefaultPrompt, activePrompt]
            ),
            "wand.and.stars"
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.activePromptIcon(
                selectedPromptId: nil,
                prompts: [storedDefaultPrompt, activePrompt]
            ),
            "stored.default"
        )

        let defaultPrompt = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.defaultPromptId }
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.activePromptIcon(
                selectedPromptId: UUID(uuidString: "00000000-0000-0000-0000-000000000223")!,
                prompts: [activePrompt]
            ),
            defaultPrompt.icon
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.activePromptIcon(
                selectedPromptId: nil,
                prompts: [],
                predefinedPrompts: []
            ),
            RomaCustomPromptPresentation.defaultPromptFallbackIconSystemName
        )
    }

    func testCustomPromptPolicyBuildsStartupStoreStateInMacOSRepairOrder() {
        let storedPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let stalePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let storedPrompt = RomaCustomPrompt(
            id: storedPromptId,
            title: "Stored",
            promptText: "Stored prompt"
        )

        let repairedState = RomaCustomPromptPolicy.startupStoreState(
            loadedPrompts: [storedPrompt],
            selectedPromptId: stalePromptId,
            isEnhancementEnabled: true
        )

        XCTAssertEqual(
            repairedState.prompts.map(\.id),
            [
                storedPromptId,
                RomaPredefinedPrompts.defaultPromptId,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertEqual(repairedState.selectedPromptId, storedPromptId)

        let emptyState = RomaCustomPromptPolicy.startupStoreState(
            loadedPrompts: [],
            selectedPromptId: nil,
            isEnhancementEnabled: true
        )
        XCTAssertEqual(
            emptyState.prompts.map(\.id),
            [
                RomaPredefinedPrompts.defaultPromptId,
                RomaPredefinedPrompts.assistantPromptId
            ]
        )
        XCTAssertNil(emptyState.selectedPromptId)
    }

    func testCustomPromptPolicyUsesAssistantPromptWithoutSystemInstructions() throws {
        let predefined = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.assistantPromptId }
        )
        let assistantPrompt = RomaCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(
            RomaCustomPromptPolicy.basePromptText(activePrompt: assistantPrompt, prompts: [assistantPrompt]),
            RomaAIPrompts.assistantMode
        )
    }

    func testCustomPromptPolicyWrapsNonAssistantActivePrompt() {
        let activePrompt = RomaCustomPrompt(
            title: "Edit",
            promptText: "Make the transcript concise.",
            useSystemInstructions: true
        )

        let promptText = RomaCustomPromptPolicy.basePromptText(
            activePrompt: activePrompt,
            prompts: [activePrompt]
        )

        XCTAssertEqual(promptText, activePrompt.finalPromptText)
        XCTAssertTrue(promptText.contains("Make the transcript concise."))
        XCTAssertTrue(promptText != activePrompt.promptText)
    }

    func testCustomPromptPolicyFallsBackToDefaultPromptText() throws {
        let customPrompt = RomaCustomPrompt(
            title: "Custom",
            promptText: "Use custom rules.",
            useSystemInstructions: true
        )
        let predefined = try XCTUnwrap(
            RomaPredefinedPrompts.all.first { $0.id == RomaPredefinedPrompts.defaultPromptId }
        )
        let defaultPrompt = RomaCustomPrompt(predefinedPrompt: predefined)

        XCTAssertEqual(
            RomaCustomPromptPolicy.basePromptText(
                activePrompt: nil,
                prompts: [customPrompt, defaultPrompt]
            ),
            defaultPrompt.finalPromptText
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.basePromptText(activePrompt: nil, prompts: [customPrompt]),
            customPrompt.finalPromptText
        )
        XCTAssertEqual(RomaCustomPromptPolicy.basePromptText(activePrompt: nil, prompts: []), "")
    }

    func testCustomPromptDraftSaveabilityPreservesMacOSEmptyStringRule() {
        XCTAssertFalse(
            RomaCustomPromptPolicy.isSaveableCustomPromptDraft(
                RomaCustomPromptDraft(
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
            RomaCustomPromptPolicy.isSaveableCustomPromptDraft(
                RomaCustomPromptDraft(
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
            RomaCustomPromptPolicy.isSaveableCustomPromptDraft(
                RomaCustomPromptDraft(
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

    func testCustomPromptDraftBuildsNewAndEditState() {
        let newDraft = RomaCustomPromptDraft.newPrompt
        XCTAssertEqual(newDraft.title, "")
        XCTAssertEqual(newDraft.promptText, "")
        XCTAssertEqual(newDraft.icon, RomaCustomPromptPresentation.defaultIconSystemName)
        XCTAssertEqual(newDraft.description, "")
        XCTAssertTrue(newDraft.triggerWords.isEmpty)
        XCTAssertTrue(newDraft.useSystemInstructions)

        let existing = RomaCustomPrompt(
            title: "Existing",
            promptText: "Existing prompt",
            icon: "tray.full.fill",
            description: nil,
            triggerWords: ["reply"],
            useSystemInstructions: false
        )
        let editDraft = RomaCustomPromptDraft(prompt: existing)

        XCTAssertEqual(editDraft.title, "Existing")
        XCTAssertEqual(editDraft.promptText, "Existing prompt")
        XCTAssertEqual(editDraft.icon, "tray.full.fill")
        XCTAssertEqual(editDraft.description, "")
        XCTAssertEqual(editDraft.triggerWords, ["reply"])
        XCTAssertFalse(editDraft.useSystemInstructions)
    }

    func testCustomPromptDraftOwnsSaveAndApplyHelpers() {
        let draft = RomaCustomPromptDraft(
            title: "Proofread",
            promptText: "Fix grammar.",
            icon: "pencil",
            description: "",
            triggerWords: ["proof"],
            useSystemInstructions: false
        )

        XCTAssertTrue(draft.isSaveable)

        let newPrompt = draft.customPrompt
        XCTAssertEqual(newPrompt.title, "Proofread")
        XCTAssertEqual(newPrompt.promptText, "Fix grammar.")
        XCTAssertEqual(newPrompt.icon, "pencil")
        XCTAssertNil(newPrompt.description)
        XCTAssertFalse(newPrompt.isPredefined)
        XCTAssertEqual(newPrompt.triggerWords, ["proof"])
        XCTAssertFalse(newPrompt.useSystemInstructions)

        let customPrompt = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000304")!,
            title: "Old",
            promptText: "Old prompt",
            isActive: true,
            icon: "old.icon",
            description: "Old description",
            isPredefined: false,
            triggerWords: ["old"],
            useSystemInstructions: true
        )
        let updatedCustomPrompt = draft.applying(to: customPrompt)
        XCTAssertEqual(updatedCustomPrompt.id, customPrompt.id)
        XCTAssertEqual(updatedCustomPrompt.title, "Proofread")
        XCTAssertEqual(updatedCustomPrompt.promptText, "Fix grammar.")
        XCTAssertTrue(updatedCustomPrompt.isActive)
        XCTAssertEqual(updatedCustomPrompt.icon, "pencil")
        XCTAssertNil(updatedCustomPrompt.description)
        XCTAssertFalse(updatedCustomPrompt.isPredefined)
        XCTAssertEqual(updatedCustomPrompt.triggerWords, ["proof"])
        XCTAssertFalse(updatedCustomPrompt.useSystemInstructions)

        let predefinedPrompt = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Template prompt",
            isActive: true,
            icon: "template.icon",
            description: "Template description",
            isPredefined: true,
            triggerWords: ["old"],
            useSystemInstructions: true
        )
        let updatedPredefinedPrompt = draft.applying(to: predefinedPrompt)
        XCTAssertEqual(updatedPredefinedPrompt.title, predefinedPrompt.title)
        XCTAssertEqual(updatedPredefinedPrompt.promptText, predefinedPrompt.promptText)
        XCTAssertEqual(updatedPredefinedPrompt.icon, predefinedPrompt.icon)
        XCTAssertEqual(updatedPredefinedPrompt.description, predefinedPrompt.description)
        XCTAssertEqual(updatedPredefinedPrompt.triggerWords, ["proof"])
        XCTAssertTrue(updatedPredefinedPrompt.useSystemInstructions)
    }

    func testCustomPromptDraftAppliesTemplatePreservingTriggerAndSystemInstructionState() {
        let draft = RomaCustomPromptDraft(
            title: "Old",
            promptText: "Old prompt",
            icon: "old.icon",
            description: "Old description",
            triggerWords: ["email"],
            useSystemInstructions: false
        )
        let template = RomaTemplatePrompt(
            id: "reply",
            title: "Reply",
            promptText: "Write a reply.",
            icon: "arrowshape.turn.up.left.fill",
            description: "Reply template"
        )

        let appliedDraft = draft.applyingTemplate(template)

        XCTAssertEqual(appliedDraft.title, "Reply")
        XCTAssertEqual(appliedDraft.promptText, "Write a reply.")
        XCTAssertEqual(appliedDraft.icon, "arrowshape.turn.up.left.fill")
        XCTAssertEqual(appliedDraft.description, "Reply template")
        XCTAssertEqual(appliedDraft.triggerWords, ["email"])
        XCTAssertFalse(appliedDraft.useSystemInstructions)
    }

    func testCustomPromptEditorContextBuildsAddModeStateAndSavePlan() {
        let context = RomaCustomPromptEditorContext.add

        XCTAssertEqual(context.initialDraft, .newPrompt)
        XCTAssertTrue(context.isAddingPrompt)
        XCTAssertFalse(context.isEditingPredefinedPrompt)
        XCTAssertFalse(context.shouldShowPredefinedPromptForm)
        XCTAssertTrue(context.shouldShowTemplateSection)
        XCTAssertEqual(context.editorTitle, "New Prompt")
        XCTAssertTrue(context.isSaveButtonDisabled(for: context.initialDraft))

        let draft = RomaCustomPromptDraft(
            title: "Proofread",
            promptText: "Fix grammar.",
            icon: "pencil",
            description: "",
            triggerWords: ["proof"],
            useSystemInstructions: false
        )
        XCTAssertFalse(context.isSaveButtonDisabled(for: draft))

        let plan = context.savePlan(for: draft)
        switch plan {
        case .add(let prompt):
            XCTAssertEqual(prompt.title, "Proofread")
            XCTAssertEqual(prompt.promptText, "Fix grammar.")
            XCTAssertEqual(prompt.triggerWords, ["proof"])
        case .update:
            XCTFail("Expected add plan")
        }

        var events: [String] = []
        plan.applyRuntimeState(
            addPrompt: { events.append("add:\($0.title)") },
            updatePrompt: { events.append("update:\($0.title)") }
        )
        XCTAssertEqual(events, ["add:Proofread"])
    }

    func testCustomPromptEditorContextBuildsCustomEditModeStateAndSavePlan() {
        let existing = RomaCustomPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
            title: "Old",
            promptText: "Old prompt",
            icon: "old.icon",
            description: "Old description",
            triggerWords: ["old"],
            useSystemInstructions: true
        )
        let context = RomaCustomPromptEditorContext.edit(prompt: existing)

        XCTAssertEqual(context.initialDraft, RomaCustomPromptDraft(prompt: existing))
        XCTAssertFalse(context.isAddingPrompt)
        XCTAssertFalse(context.isEditingPredefinedPrompt)
        XCTAssertFalse(context.shouldShowPredefinedPromptForm)
        XCTAssertFalse(context.shouldShowTemplateSection)
        XCTAssertEqual(context.editorTitle, "Edit Prompt")

        let draft = RomaCustomPromptDraft(
            title: "New",
            promptText: "New prompt",
            icon: "new.icon",
            description: "",
            triggerWords: ["new"],
            useSystemInstructions: false
        )
        let plan = context.savePlan(for: draft)

        switch plan {
        case .add:
            XCTFail("Expected update plan")
        case .update(let prompt):
            XCTAssertEqual(prompt.id, existing.id)
            XCTAssertEqual(prompt.title, "New")
            XCTAssertEqual(prompt.promptText, "New prompt")
            XCTAssertEqual(prompt.icon, "new.icon")
            XCTAssertNil(prompt.description)
            XCTAssertEqual(prompt.triggerWords, ["new"])
            XCTAssertFalse(prompt.useSystemInstructions)
        }
    }

    func testCustomPromptEditorContextBuildsPredefinedEditModeStateAndSavePlan() {
        let existing = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Template prompt",
            isActive: true,
            icon: "template.icon",
            description: "Template description",
            isPredefined: true,
            triggerWords: ["old"],
            useSystemInstructions: true
        )
        let context = RomaCustomPromptEditorContext.edit(prompt: existing)

        XCTAssertFalse(context.isAddingPrompt)
        XCTAssertTrue(context.isEditingPredefinedPrompt)
        XCTAssertTrue(context.shouldShowPredefinedPromptForm)
        XCTAssertFalse(context.shouldShowTemplateSection)
        XCTAssertEqual(context.editorTitle, "Edit Trigger Words")
        XCTAssertFalse(context.isSaveButtonDisabled(for: .newPrompt))

        var draft = context.initialDraft
        draft.title = ""
        draft.promptText = ""
        draft.triggerWords = ["updated"]

        switch context.savePlan(for: draft) {
        case .add:
            XCTFail("Expected update plan")
        case .update(let prompt):
            XCTAssertEqual(prompt.id, existing.id)
            XCTAssertEqual(prompt.title, existing.title)
            XCTAssertEqual(prompt.promptText, existing.promptText)
            XCTAssertEqual(prompt.icon, existing.icon)
            XCTAssertEqual(prompt.description, existing.description)
            XCTAssertEqual(prompt.triggerWords, ["updated"])
            XCTAssertTrue(prompt.useSystemInstructions)
        }
    }

    func testCustomPromptPolicyBuildsNewPromptFromDraft() {
        let prompt = RomaCustomPromptPolicy.customPrompt(
            from: RomaCustomPromptDraft(
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
        let existing = RomaCustomPrompt(
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

        let updated = RomaCustomPromptPolicy.prompt(
            existing,
            applying: RomaCustomPromptDraft(
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
        let existing = RomaCustomPrompt(
            id: RomaPredefinedPrompts.defaultPromptId,
            title: "Default",
            promptText: "Template prompt",
            isActive: true,
            icon: "template.icon",
            description: "Template description",
            isPredefined: true,
            triggerWords: ["old"],
            useSystemInstructions: true
        )

        let updated = RomaCustomPromptPolicy.prompt(
            existing,
            applying: RomaCustomPromptDraft(
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
        let prompt = RomaCustomPrompt(
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

    func testCustomPromptPresentationFormatsTriggerSummaryAndDeleteAlert() throws {
        XCTAssertNil(RomaCustomPromptPresentation.triggerSummary(for: []))

        let singleSummary = try XCTUnwrap(RomaCustomPromptPresentation.triggerSummary(for: ["email"]))
        XCTAssertEqual(singleSummary.iconSystemName, "mic.fill")
        XCTAssertEqual(singleSummary.text, "\"email...\"")

        let multiSummary = try XCTUnwrap(RomaCustomPromptPresentation.triggerSummary(for: ["email", "reply"]))
        XCTAssertEqual(multiSummary.text, "\"email...\" +1")

        XCTAssertEqual(RomaCustomPromptPresentation.editActionTitle, "Edit")
        XCTAssertEqual(RomaCustomPromptPresentation.editActionSystemImageName, "pencil")
        XCTAssertEqual(RomaCustomPromptPresentation.deleteActionTitle, "Delete")
        XCTAssertEqual(RomaCustomPromptPresentation.deleteActionSystemImageName, "trash")
        XCTAssertEqual(RomaCustomPromptPresentation.cancelActionTitle, "Cancel")
        XCTAssertEqual(RomaCustomPromptPresentation.deletePromptConfirmationTitle, "Delete Prompt?")
        XCTAssertEqual(
            RomaCustomPromptPresentation.deletePromptConfirmationMessage(promptTitle: "Email"),
            "Are you sure you want to delete 'Email' prompt? This action cannot be undone."
        )
    }

    func testPromptDetectionPolicyReturnsNoMatchResultWithOriginalState() {
        let originalPromptId = UUID()
        let prompt = RomaCustomPrompt(
            title: "Email",
            promptText: "Write an email.",
            triggerWords: ["email"]
        )

        let result = RomaPromptDetectionPolicy.analyzeText(
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
        let emailPrompt = RomaCustomPrompt(
            id: emailPromptId,
            title: "Email",
            promptText: "Write an email.",
            triggerWords: ["email"]
        )

        let result = RomaPromptDetectionPolicy.analyzeText(
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

    func testDetectedPromptResultAppliesSettingsState() throws {
        let detectedPromptId = UUID()
        let currentPromptId = UUID()
        let result = RomaPromptDetectionResult(
            shouldEnableAI: true,
            selectedPromptId: detectedPromptId,
            processedText: "send a follow up",
            detectedTriggerWord: "email",
            originalEnhancementState: false,
            originalPromptId: nil
        )

        let state = try XCTUnwrap(result.applyingSettingsState(
            current: RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: false,
                selectedPromptId: currentPromptId
            )
        ))

        XCTAssertEqual(
            state,
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: detectedPromptId
            )
        )
    }

    func testDetectedPromptResultRestoresSettingsStateIncludingNilPrompt() throws {
        let detectedPromptId = UUID()
        let result = RomaPromptDetectionResult(
            shouldEnableAI: true,
            selectedPromptId: detectedPromptId,
            processedText: "send a follow up",
            detectedTriggerWord: "email",
            originalEnhancementState: false,
            originalPromptId: nil
        )

        let state = try XCTUnwrap(result.restoringSettingsState(
            current: RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: true,
                selectedPromptId: detectedPromptId
            )
        ))

        XCTAssertEqual(
            state,
            RomaAIEnhancementPromptSettingsState(
                isEnhancementEnabled: false,
                selectedPromptId: nil
            )
        )
    }

    func testNoMatchPromptResultReturnsNoSettingsState() {
        let currentPromptId = UUID()
        let originalPromptId = UUID()
        let result = RomaPromptDetectionResult(
            shouldEnableAI: false,
            selectedPromptId: nil,
            processedText: "plain text",
            detectedTriggerWord: nil,
            originalEnhancementState: false,
            originalPromptId: originalPromptId
        )

        let currentState = RomaAIEnhancementPromptSettingsState(
            isEnhancementEnabled: true,
            selectedPromptId: currentPromptId
        )

        XCTAssertNil(result.applyingSettingsState(current: currentState))
        XCTAssertNil(result.restoringSettingsState(current: currentState))
    }

    func testPromptDetectionPolicyIgnoresPromptsWithoutTriggerWords() {
        let prompt = RomaCustomPrompt(
            title: "Blank",
            promptText: "No trigger.",
            triggerWords: [" ", "\n"]
        )

        let result = RomaPromptDetectionPolicy.analyzeText(
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
            RomaPromptTriggerPolicy.addingTriggerWord("  Roma  ", to: ["Dictate"]),
            ["Dictate", "Roma"]
        )
        XCTAssertNil(RomaPromptTriggerPolicy.addingTriggerWord(" \n\t ", to: ["Dictate"]))
        XCTAssertNil(RomaPromptTriggerPolicy.addingTriggerWord("dictate", to: ["Dictate"]))
    }

    func testRemovingTriggerWordPreservesExactMacOSEditingRule() {
        XCTAssertEqual(
            RomaPromptTriggerPolicy.removingTriggerWord("Email", from: ["email", "Email", "Reply"]),
            ["email", "Reply"]
        )
    }

    func testTriggerWordDraftUsesSharedBlankPolicy() {
        XCTAssertFalse(RomaPromptTriggerPolicy.hasTriggerWordDraft(" \n\t "))
        XCTAssertTrue(RomaPromptTriggerPolicy.hasTriggerWordDraft("  Roma  "))
    }

    func testTriggerWordDraftStateUsesSharedBlankPolicy() {
        XCTAssertFalse(RomaPromptTriggerDraftState(draft: " \n\t ").canSubmit)
        XCTAssertTrue(RomaPromptTriggerDraftState(draft: "  Roma  ").canSubmit)
    }

    func testTriggerWordDraftStateSubmitsAndClearsAcceptedWord() {
        let submission = RomaPromptTriggerDraftState(draft: "  Roma  ")
            .submitting(existingWords: ["Dictate"])

        XCTAssertEqual(submission.updatedWords, ["Dictate", "Roma"])
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaPromptTriggerDraftState())
    }

    func testTriggerWordDraftStateKeepsRejectedDraft() {
        let submission = RomaPromptTriggerDraftState(draft: "dictate")
            .submitting(existingWords: ["Dictate"])

        XCTAssertNil(submission.updatedWords)
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaPromptTriggerDraftState(draft: "dictate"))
    }

    func testTriggerWordDraftSubmissionAppliesRuntimeState() {
        let submission = RomaPromptTriggerDraftState(draft: "  Roma  ")
            .submitting(existingWords: ["Dictate"])
        var triggerWords = ["Dictate"]
        var draftState = RomaPromptTriggerDraftState(draft: "  Roma  ")

        let returnedSubmission = submission.applyRuntimeState(
            setTriggerWords: { triggerWords = $0 },
            setDraftState: { draftState = $0 }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(triggerWords, ["Dictate", "Roma"])
        XCTAssertEqual(draftState, RomaPromptTriggerDraftState())
    }

    func testDetectStripsLeadingTriggerAndCapitalizesRemainingText() throws {
        let promptId = UUID()
        let match = try XCTUnwrap(
            RomaPromptTriggerPolicy.detect(
                in: " email, send this",
                triggers: [
                    RomaPromptTrigger(promptId: promptId, triggerWords: ["email"])
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
            RomaPromptTriggerPolicy.detect(
                in: "please send, email!",
                triggers: [
                    RomaPromptTrigger(promptId: notePromptId, triggerWords: ["note"]),
                    RomaPromptTrigger(promptId: emailPromptId, triggerWords: ["email"])
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
            RomaPromptTriggerPolicy.detect(
                in: "do it now",
                triggers: [
                    RomaPromptTrigger(promptId: promptId, triggerWords: ["do", "do it"])
                ]
            )
        )

        XCTAssertEqual(match.triggerWord, "do it")
        XCTAssertEqual(match.processedText, "Now")
        XCTAssertNil(
            RomaPromptTriggerPolicy.detect(
                in: "domain update",
                triggers: [
                    RomaPromptTrigger(promptId: promptId, triggerWords: ["do"])
                ]
            )
        )
    }

    func testDetectStripsSameTriggerFromBothEnds() throws {
        let promptId = UUID()
        let match = try XCTUnwrap(
            RomaPromptTriggerPolicy.detect(
                in: "email, send this email",
                triggers: [
                    RomaPromptTrigger(promptId: promptId, triggerWords: ["email"])
                ]
            )
        )

        XCTAssertEqual(match.triggerWord, "email")
        XCTAssertEqual(match.processedText, "Send this")
    }
}

extension CustomPromptTests {
    func testFinalPromptTextReturnsRawPromptWithoutSystemInstructions() {
        XCTAssertEqual(
            RomaAIPrompts.finalPromptText("Answer the user directly.", useSystemInstructions: false),
            "Answer the user directly."
        )
    }

    func testFinalPromptTextWrapsPromptWithSystemInstructions() {
        let finalPrompt = RomaAIPrompts.finalPromptText(
            "Clean this transcript.",
            useSystemInstructions: true
        )

        XCTAssertTrue(finalPrompt.contains("Clean this transcript."))
        XCTAssertTrue(finalPrompt.contains("[FINAL WARNING]"))
        XCTAssertTrue(finalPrompt.contains("OUTPUT ONLY THE CLEANED UP TEXT"))
    }

    func testPostProcessingRequestRejectsBlankPrompt() {
        XCTAssertNil(RomaPostProcessingRequest(prompt: " \n\t ", transcript: "raw text"))
    }

    func testPostProcessingRequestBuildsSharedIOSMessages() async throws {
        let request = try XCTUnwrap(
            RomaPostProcessingRequest(
                prompt: "Clean this",
                transcript: "raw text"
            )
        )

        let summary = try await request.applyRuntimeState { messages, temperature in
            (messages, temperature)
        }

        XCTAssertEqual(summary.1, 0.2)
        XCTAssertEqual(
            summary.0,
            [
                RomaOpenAICompatibleChatMessage(
                    role: "system",
                    content: "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."
                ),
                RomaOpenAICompatibleChatMessage(
                    role: "user",
                    content: "Prompt: Clean this\n\nTranscript:\nraw text"
                )
            ]
        )
    }

    func testPostProcessingFinalizedTranscriptFallsBackWhenFilteredResponseIsEmpty() {
        let fallbackTranscript = "raw text"

        XCTAssertEqual(
            RomaPostProcessingRequest.finalizedTranscript(
                from: "",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            RomaPostProcessingRequest.finalizedTranscript(
                from: "   \n ",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            RomaPostProcessingRequest.finalizedTranscript(
                from: "<think>hidden reasoning</think>",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
    }

    func testPostProcessingFinalizedTranscriptStripsReasoningTags() {
        XCTAssertEqual(
            RomaPostProcessingRequest.finalizedTranscript(
                from: "<thinking>draft</thinking>\nClean text\n<reasoning>notes</reasoning>",
                fallbackTranscript: "raw text"
            ),
            "Clean text"
        )
    }

    func testPostProcessingFinalizedTranscriptStripsCodexFollowUpPayload() {
        let response = """
        Regards.

        ```json
        {
          "codex_follow_up": true,
          "title": "Follow-up",
          "items": [
            {
              "prompt": "Clean up another short transcript"
            }
          ]
        }
        ```
        """

        XCTAssertEqual(
            RomaPostProcessingRequest.finalizedTranscript(
                from: response,
                fallbackTranscript: "raw text"
            ),
            "Regards."
        )
    }

    func testMovingPromptsPreservesRelativeOrder() {
        let prompts = ["A", "B", "C", "D"].map {
            RomaCustomPrompt(title: $0, promptText: $0)
        }

        XCTAssertEqual(
            RomaCustomPromptPolicy.movingPrompts(
                prompts,
                from: IndexSet([1, 2]),
                to: 4
            ).map(\.title),
            ["A", "D", "B", "C"]
        )
        XCTAssertEqual(
            RomaCustomPromptPolicy.movingPrompts(
                prompts,
                from: IndexSet(integer: 3),
                to: 1
            ).map(\.title),
            ["A", "D", "B", "C"]
        )
    }
}
