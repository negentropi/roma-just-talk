//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
import VoiceInkCore
import SwiftData
import AppKit
import Carbon.HIToolbox
import os
@testable import VoiceInk

@Suite(.serialized)
struct VoiceInkTests {

    @Test func freshDefaultsHideMenuBarIcon() async throws {
        #expect(AppDefaults.registeredDefaults[VoiceInkMenuBarPreference.showMenuBarIconKey] as? Bool == false)
        #expect(AppDefaults.registeredDefaults["IsMenuBarOnly"] as? Bool == true)
        #expect(AppDefaults.registeredDefaults[VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap] as? Bool == true)
    }

    @Test @MainActor func failedPasteCommandDoesNotRestoreOverTranscriptClipboard() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let restoreDelayValue = defaults.object(forKey: "clipboardRestoreDelay")
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(restoreDelayValue, forKey: "clipboardRestoreDelay")
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(true, forKey: "restoreClipboardAfterPaste")
        defaults.set(0.01, forKey: "clipboardRestoreDelay")
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        CursorPaster.configurePasteCommandPosterForTesting {
            .commandNotPosted
        }

        let result = await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text")
        try await Task.sleep(nanoseconds: 350_000_000)

        #expect(result == .commandNotPosted)
        #expect(pasteboard.string(forType: .string) == "dictated text")
    }

    @Test @MainActor func accessibilityInsertDeliversWithoutTouchingClipboard() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let pasteMethodValue = defaults.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configureAccessibilityTextInserterForTesting()
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(pasteMethodValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(true, forKey: "restoreClipboardAfterPaste")
        defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        var postedCommand = false
        var insertionResult = CursorTextContextReader.SelectedTextInsertionResult.inserted
        CursorPaster.configureAccessibilityTextInserterForTesting { text, _ in
            text == "dictated text" ? insertionResult : .notApplied
        }
        CursorPaster.configurePasteCommandPosterForTesting {
            postedCommand = true
            return .commandPosted
        }

        for result in [
            CursorTextContextReader.SelectedTextInsertionResult.inserted,
            .insertedWithoutSelection,
            .insertedViaValue,
            .insertedViaValueWithoutSelection
        ] {
            insertionResult = result
            #expect(await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text") == .textInserted)
        }
        #expect(!postedCommand)
        #expect(pasteboard.string(forType: .string) == "previous clipboard")
    }

    @Test @MainActor func nonInsertedAccessibilityResultsFallBackToPasteCommand() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let pasteMethodValue = defaults.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configureAccessibilityTextInserterForTesting()
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(pasteMethodValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(false, forKey: "restoreClipboardAfterPaste")
        defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
        var insertionResult = CursorTextContextReader.SelectedTextInsertionResult.notApplied
        var postedCommandCount = 0
        CursorPaster.configureAccessibilityTextInserterForTesting { _, _ in insertionResult }
        CursorPaster.configurePasteCommandPosterForTesting {
            postedCommandCount += 1
            return .commandPosted
        }

        for result in [
            CursorTextContextReader.SelectedTextInsertionResult.notApplied,
            .unsupported
        ] {
            insertionResult = result
            pasteboard.clearContents()
            pasteboard.setString("previous clipboard", forType: .string)

            #expect(await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text") == .commandPosted)
            #expect(pasteboard.string(forType: .string) == "dictated text")
        }

        #expect(postedCommandCount == 2)
    }

    @Test func accessibilityInsertionObservationRejectsSilentAXSuccess() {
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "",
            rangeBeforeInsertion: CFRange(location: 0, length: 0),
            insertedText: "dictated text",
            textAfterInsertion: "",
            rangeAfterInsertion: CFRange(location: 0, length: 0)
        ))
    }

    @Test func directAccessibilityInsertionSkipsWebBackedEditors() {
        #expect(CursorTextContextReader.shouldUseDirectAccessibilityInsertion(
            ancestorRoles: ["AXTextArea", "AXGroup", "AXWindow"]
        ))
        #expect(!CursorTextContextReader.shouldUseDirectAccessibilityInsertion(
            ancestorRoles: ["AXTextArea", "AXGroup", "AXWebArea", "AXWindow"]
        ))
    }

    @Test func accessibilityInsertionObservationAcceptsTextOrCursorMutation() {
        #expect(CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after",
            rangeAfterInsertion: CFRange(location: 16, length: 0)
        ))
        #expect(CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: nil,
            rangeBeforeInsertion: CFRange(location: 0, length: 0),
            insertedText: "👋",
            textAfterInsertion: nil,
            rangeAfterInsertion: CFRange(location: 2, length: 0)
        ))
    }

    @Test func accessibilityInsertionObservationRejectsUnrelatedTextMutation() {
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before unrelated after",
            rangeAfterInsertion: CFRange(location: 16, length: 0)
        ))
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after",
            rangeAfterInsertion: CFRange(location: 0, length: 0)
        ))
        #expect(CursorTextContextReader.replacementTextWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after"
        ))
    }

    @Test func accessibilityValueReplacementUsesUTF16Selection() throws {
        let replacement = try #require(CursorTextContextReader.valueReplacement(
            textBeforeInsertion: "before 👋 after",
            rangeBeforeInsertion: CFRange(location: 7, length: 2),
            insertedText: "dictated"
        ))

        #expect(replacement.text == "before dictated after")
        #expect(replacement.selectedRange.location == 15)
        #expect(replacement.selectedRange.length == 0)
    }

    @Test func accessibilityValueReplacementRejectsInvalidRange() {
        #expect(CursorTextContextReader.valueReplacement(
            textBeforeInsertion: "text",
            rangeBeforeInsertion: CFRange(location: 5, length: 0),
            insertedText: "dictated"
        ) == nil)
    }

    @Test func accessibilityValueReplacementRequiresExactRangeRestore() {
        let expectedRange = CFRange(location: 8, length: 0)

        #expect(CursorTextContextReader.valueReplacementWasObserved(
            text: "dictated",
            selectedRange: expectedRange,
            textAfterInsertion: "dictated",
            rangeAfterInsertion: expectedRange
        ))
        #expect(!CursorTextContextReader.valueReplacementWasObserved(
            text: "dictated",
            selectedRange: expectedRange,
            textAfterInsertion: "dictated",
            rangeAfterInsertion: CFRange(location: 0, length: 8)
        ))
    }

    @Test @MainActor func sessionMetricRecorderAcceptsSnapshotModelName() throws {
        let container = try makeSessionMetricContainer()
        let context = container.mainContext
        let transcription = Transcription(
            text: "quick release wins",
            duration: 2,
            transcriptionDuration: 0.5,
            transcriptionStatus: .completed
        )
        context.insert(transcription)
        try context.save()

        let didInsertMetric = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription,
            modelDisplayName: "Snapshot Model",
            in: context,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        try context.save()

        let metrics = try context.fetch(FetchDescriptor<SessionMetric>())
        #expect(didInsertMetric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.transcriptionModelName == "Snapshot Model")
        #expect(metrics.first?.wordCount == 3)
        #expect(metrics.first?.speedFactor == 4.0)
    }

    @Test func resolvesAPIKeyEnvironmentReference() async throws {
        let environment = ["ELEVENLABS_API_KEY": "test-key"]

        #expect(VoiceInkAPIKeyReference.resolvedValue("$ELEVENLABS_API_KEY", environment: environment) == "test-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("${ELEVENLABS_API_KEY}", environment: environment) == "test-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("literal-key", environment: environment) == "literal-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("$MISSING", environment: environment) == nil)
    }

    @Test @MainActor func dictionaryServiceUsesWarmedWordReplacementCacheUntilInvalidated() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        context.insert(WordReplacement(originalText: "voice ink", replacementText: "roma"))
        try context.save()

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")

        context.insert(WordReplacement(originalText: "quick release", replacementText: "instant paste"))
        try context.save()

        #expect(DictionaryService.applyWordReplacements(to: "quick release", using: context) == "quick release")

        DictionaryService.invalidateWordReplacementCache()
        #expect(DictionaryService.applyWordReplacements(to: "quick release", using: context) == "instant paste")
    }

    @Test @MainActor func dictionaryServiceIgnoresDisabledWordReplacements() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        context.insert(
            WordReplacement(
                originalText: "voice ink",
                replacementText: "roma",
                isEnabled: false
            )
        )
        try context.save()

        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")
    }

    @Test @MainActor func dictionaryServiceWordReplacementSaveInvalidatesWarmedWordReplacementCache() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")

        let submission = VoiceInkWordReplacementDraftState(
            original: "voice ink",
            replacement: "roma"
        ).submitting(existingRules: [])
        let appliedSubmission = DictionaryService.applyWordReplacementSubmission(
            submission,
            context: context
        )

        #expect(appliedSubmission.alertPresentation == nil)
        #expect(appliedSubmission.plan.shouldComplete)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")
    }

    @Test @MainActor func dictionaryServiceWordReplacementRemovalInvalidatesWarmedWordReplacementCache() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        let replacement = WordReplacement(originalText: "voice ink", replacementText: "roma")
        context.insert(replacement)
        try context.save()

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")

        #expect(DictionaryService.removeWordReplacement(replacement, context: context) == nil)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")
    }

    @Test @MainActor func dictionaryServiceVocabularyRemovalDeletesWord() throws {
        let container = try makeVocabularyContainer()
        let context = container.mainContext
        let word = VocabularyWord(word: "roma")
        context.insert(word)
        context.insert(VocabularyWord(word: "voice ink"))
        try context.save()

        #expect(DictionaryService.removeVocabularyWord(word, context: context) == nil)

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            .map(\.word)
            .sorted()
        #expect(words == ["voice ink"])
    }

    @Test @MainActor func aiEnhancementServiceCachesPromptTriggerEligibility() throws {
        let savedPrompts = UserDefaults.standard.data(forKey: "customPrompts")
        let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId")
        defer {
            if let savedPrompts {
                UserDefaults.standard.set(savedPrompts, forKey: "customPrompts")
            } else {
                UserDefaults.standard.removeObject(forKey: "customPrompts")
            }
            if let savedPromptId {
                UserDefaults.standard.set(savedPromptId, forKey: "selectedPromptId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPromptId")
            }
        }

        let container = try makeWordReplacementContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.customPrompts = []

        #expect(!service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.isEmpty)

        let triggerPrompt = VoiceInkCustomPrompt(
            title: "Fast Trigger",
            promptText: "Clean this",
            triggerWords: ["clean"]
        )
        service.customPrompts = [triggerPrompt]

        #expect(service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.map(\.id) == [triggerPrompt.id])

        service.customPrompts = [
            VoiceInkCustomPrompt(
                title: "Blank Trigger",
                promptText: "Clean this",
                triggerWords: ["   "]
            )
        ]

        #expect(!service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.isEmpty)
    }

    @Test @MainActor func promptDetectionUsesCachedTriggerPrompts() throws {
        let savedPrompts = UserDefaults.standard.data(forKey: "customPrompts")
        let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId")
        defer {
            if let savedPrompts {
                UserDefaults.standard.set(savedPrompts, forKey: "customPrompts")
            } else {
                UserDefaults.standard.removeObject(forKey: "customPrompts")
            }
            if let savedPromptId {
                UserDefaults.standard.set(savedPromptId, forKey: "selectedPromptId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPromptId")
            }
        }

        let container = try makeWordReplacementContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let triggerPrompt = VoiceInkCustomPrompt(
            title: "Assistant Trigger",
            promptText: "Answer directly",
            triggerWords: ["answer"]
        )
        service.customPrompts = [
            VoiceInkCustomPrompt(title: "No Trigger", promptText: "Clean this"),
            triggerPrompt
        ]

        let detection = VoiceInkPromptDetectionPolicy.analyzeText(
            "answer what is this?",
            prompts: service.promptDetectionPrompts,
            isEnhancementEnabled: false,
            selectedPromptId: nil
        )

        #expect(detection.shouldEnableAI)
        #expect(detection.selectedPromptId == triggerPrompt.id)
        #expect(detection.processedText == "What is this?")
    }

    @Test @MainActor func noneRecorderStyleStartsSessionWithoutShowingRecorderWindow() async throws {
        let oldRecorderType = UserDefaults.standard.string(forKey: "RecorderType")
        defer {
            if let oldRecorderType {
                UserDefaults.standard.set(oldRecorderType, forKey: "RecorderType")
            } else {
                UserDefaults.standard.removeObject(forKey: "RecorderType")
            }
        }

        UserDefaults.standard.set("none", forKey: "RecorderType")
        let manager = RecorderUIManager()

        manager.beginRecorderSession()

        #expect(manager.isRecorderSessionActive)
        #expect(!manager.isMiniRecorderVisible)
        #expect(manager.miniWindowManager == nil)
        #expect(manager.notchWindowManager == nil)
    }

    @Test @MainActor func idleNoneRecorderSessionDoesNotBlockNextShortcutStart() async throws {
        let oldRecorderType = UserDefaults.standard.string(forKey: "RecorderType")
        defer {
            if let oldRecorderType {
                UserDefaults.standard.set(oldRecorderType, forKey: "RecorderType")
            } else {
                UserDefaults.standard.removeObject(forKey: "RecorderType")
            }
        }

        UserDefaults.standard.set("none", forKey: "RecorderType")
        let manager = RecorderUIManager()

        manager.beginRecorderSession()

        #expect(manager.isRecorderSessionActive)
        #expect(!manager.isActiveForRecordingShortcut(recordingState: .idle))
        #expect(manager.isActiveForRecordingShortcut(recordingState: .starting))
        #expect(manager.isActiveForRecordingShortcut(recordingState: .recording))
    }

    @Test @MainActor func activeRecorderToggleDefersStopInsteadOfCancelingWhileStarting() async throws {
        var events: [String] = []

        for state in [
            VoiceInkRecordingState.starting,
            .recording,
            .transcribing,
            .enhancing,
            .idle,
            .busy,
        ] {
            await state.applyRecorderUIToggleRuntimeState(
                toggleRecord: { events.append("toggle") },
                cancelRecording: { events.append("cancel") },
                dismissRecorder: { events.append("dismiss") }
            )
        }

        #expect(events == [
            "toggle",
            "toggle",
            "cancel",
            "cancel",
            "dismiss",
            "dismiss",
        ])
    }

    @Test @MainActor func pushToTalkUsesActiveSessionWhenRecorderWindowIsNone() async throws {
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .pushToTalk
        )

        #expect(toggleCount == 1)
        #expect(sessionActive)

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .pushToTalk
        )

        #expect(toggleCount == 2)
        #expect(!sessionActive)
    }

    @Test @MainActor func shortcutCooldownAllowsFastBackToBackPressAfterDuplicateGuard() async throws {
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .pushToTalk
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .pushToTalk
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .pushToTalk
        )
        #expect(toggleCount == 2)

        try await Task.sleep(nanoseconds: 100_000_000)

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1.3,
            mode: .pushToTalk
        )

        #expect(toggleCount == 3)
        #expect(sessionActive)
    }

    @Test @MainActor func specialModeStartsRecordingImmediatelyOnKeyDown() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                recordingState = .recording
                sessionActive = true
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )

        #expect(toggleCount == 1)
        #expect(recordingState == .recording)
        #expect(sessionActive)
    }

    @Test @MainActor func specialModeCleanReleaseStopsRecording() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
                recordingState = sessionActive ? .recording : .idle
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .special,
            context: VoiceInkShortcutPressContext()
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeUnsafeKeyEvidenceCancelsStartedRecording() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                recordingState = .recording
                sessionActive = true
            },
            cancelRecording: {
                cancelCount += 1
                recordingState = .idle
                sessionActive = false
            }
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .special,
            context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)
        )

        #expect(cancelCount == 1)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test func shortcutKeyEvidenceTraceDetailsIdentifyEveryCause() {
        #expect(RecordingShortcutModeHandler.keyEvidenceTraceDetails(
            VoiceInkShortcutPressContext(
                didPressOtherKeyDuringPress: true,
                didReleaseOtherKeyDuringPress: false,
                hasReliableKeyEvidence: false
            )
        ) == "pressedOtherKey=true releasedOtherKey=false reliable=false")
    }

    @Test func inputMonitoringPermissionUsesInjectedSystemClient() async throws {
        var didRequestAccess = false
        let client = InputMonitoringPermission.Client(
            preflight: { false },
            request: {
                didRequestAccess = true
                return true
            }
        )

        #expect(!InputMonitoringPermission.isGranted(client: client))
        #expect(InputMonitoringPermission.requestAccess(client: client))
        #expect(didRequestAccess)
    }

    @Test func accessibilityPermissionUsesInjectedSystemClient() async throws {
        var didRequestAccess = false
        let client = AccessibilityPermission.Client(
            preflight: { false },
            request: {
                didRequestAccess = true
                return true
            }
        )

        #expect(!AccessibilityPermission.isGranted(client: client))
        #expect(AccessibilityPermission.requestAccess(client: client))
        #expect(didRequestAccess)
    }

    @Test @MainActor func permissionNotificationSuppressionScopesNestUntilLastScopeEnds() {
        let suppression = PermissionNotificationSuppression()

        #expect(!suppression.isSuppressingPermissionPrompts)

        let firstScope = suppression.beginScope()
        let secondScope = suppression.beginScope()

        #expect(suppression.isSuppressingPermissionPrompts)

        suppression.endScope(firstScope)
        #expect(suppression.isSuppressingPermissionPrompts)

        suppression.endScope(secondScope)
        #expect(!suppression.isSuppressingPermissionPrompts)
    }

    @Test func macOnboardingProgressStorePersistsStageAndPermissionCursor() {
        let defaults = UserDefaults(suiteName: "MacOnboardingProgressStoreTests")!
        defaults.removePersistentDomain(forName: "MacOnboardingProgressStoreTests")
        defer {
            defaults.removePersistentDomain(forName: "MacOnboardingProgressStoreTests")
        }

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .welcome)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == nil)

        VoiceInkMacOSOnboardingProgressStore.saveStage(.permissions, in: defaults)
        VoiceInkMacOSOnboardingProgressStore.savePermissionKind(.inputMonitoring, in: defaults)

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .permissions)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == .inputMonitoring)

        VoiceInkMacOSOnboardingProgressStore.reset(in: defaults)

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .welcome)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == nil)
    }

    @Test func modifierOnlyShortcutsUseNSEventMonitorPath() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0
        var keyUpCount = 0

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_RightOption),
                    modifierFlags: [.option]
                )
            ],
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, _ in keyUpCount += 1 }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 1
        )
        await drainMainQueue()
        #expect(keyDownCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2
        )
        await drainMainQueue()
        #expect(keyDownCount == 1)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2.5
        )
        await drainMainQueue()
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [],
            eventTime: 3
        )
        await drainMainQueue()
        #expect(keyUpCount == 1)
    }

    @Test func modifierOnlyShortcutTracksOtherKeyDownWithoutReleaseEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []
        var contextUpdates: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) },
            onPressContextChanged: { _, context in contextUpdates.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 2
        )
        #expect(await eventually { contextUpdates.count == 1 })
        #expect(contextUpdates == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutUsesEventTapOrderingWhenTrackingKeyEvidence() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_S),
            modifierFlags: [.shift],
            eventTime: 2
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { keyDownCount == 1 && contexts.count == 1 })
        #expect(keyDownCount == 1)
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutTracksSystemDefinedEvidenceDuringPress() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleSystemDefinedForTesting(eventTime: 2)
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutMarksSecureInputAsUnreliableEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { true })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 2
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(hasReliableKeyEvidence: false)])
    }

    @Test func modifierOnlyShortcutChecksPressedNonModifierKeysAtRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { false })
        )
        ShortcutMonitor.configureKeyboardStateClientForTesting(
            KeyboardState.Client(isKeyPressed: { keyCode in keyCode == UInt16(kVK_ANSI_X) })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 2
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlySpecialShortcutDoesNotStartWithoutKeyEvidenceTap() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0

        ShortcutMonitor.configurePermissionClientsForTesting(
            inputMonitoringClient: InputMonitoringPermission.Client(
                preflight: { false },
                request: { false }
            ),
            accessibilityClient: AccessibilityPermission.Client(
                preflight: { true },
                request: { true }
            )
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetPermissionClientsForTesting()
        }

        let started = monitor.start(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            tracksKeyUpEvidence: true,
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, _ in }
        )

        #expect(!started)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )

        #expect(!(await eventually { keyDownCount > 0 }))
    }

    @Test func modifierOnlyShortcutMarksOtherKeyUpAsTyping() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { false })
        )
        ShortcutMonitor.configureKeyboardStateClientForTesting(
            KeyboardState.Client(isKeyPressed: { _ in false })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 2
        )
        monitor.handleKeyUpForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 3
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 4
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlyShortcutTracksOtherModifierPressAndRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.shift, .option],
            eventTime: 2
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.shift],
            eventTime: 3
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 4
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test @MainActor func shortcutRecorderCancelRestoresStoredShortcut() throws {
        let action = ShortcutAction.powerMode(UUID())
        let originalShortcut = Shortcut.key(keyCode: UInt16(kVK_F13), modifierFlags: [])

        try withTemporaryShortcutStorage(for: action) {
            ShortcutStore.setShortcut(originalShortcut, for: action)

            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })

            #expect(ShortcutStore.shortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))

            recorder.cancel()

            #expect(ShortcutStore.shortcut(for: action) == originalShortcut)
            #expect(!ShortcutStore.isShortcutCleared(for: action))
        }
    }

    @Test @MainActor func shortcutRecorderCancelRestoresDefaultShortcutState() throws {
        let action = ShortcutAction.powerMode(UUID())

        try withTemporaryShortcutStorage(for: action) {
            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))

            recorder.cancel()

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(!ShortcutStore.isShortcutCleared(for: action))
        }
    }

    @Test @MainActor func shortcutRecorderCancelPreservesClearedShortcutState() throws {
        let action = ShortcutAction.powerMode(UUID())

        try withTemporaryShortcutStorage(for: action) {
            ShortcutStore.setShortcut(nil, for: action)

            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })
            recorder.cancel()

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))
        }
    }

    private func makeWordReplacementContainer() throws -> ModelContainer {
        let schema = Schema([WordReplacement.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeVocabularyContainer() throws -> ModelContainer {
        let schema = Schema([VocabularyWord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSessionMetricContainer() throws -> ModelContainer {
        let schema = Schema([Transcription.self, SessionMetric.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func withTemporaryShortcutStorage(for action: ShortcutAction, _ body: () throws -> Void) throws {
        ShortcutStore.removeShortcutStorage(for: action)
        defer { ShortcutStore.removeShortcutStorage(for: action) }
        try body()
    }

    private func restoreDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<20 {
            await drainMainQueue()
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await drainMainQueue()
        return predicate()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
