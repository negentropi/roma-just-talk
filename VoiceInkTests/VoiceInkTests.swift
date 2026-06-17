//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
import SwiftData
import Carbon.HIToolbox
import os
@testable import VoiceInk

struct VoiceInkTests {

    @Test func freshDefaultsHideMenuBarIcon() async throws {
        #expect(AppDefaults.registeredDefaults[AppDefaults.Keys.showMenuBarIcon] as? Bool == false)
        #expect(AppDefaults.registeredDefaults["IsMenuBarOnly"] as? Bool == true)
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey] as? Bool == true)
    }

    @Test func rollingBufferPreloadPreviewStaysVisibleDuringRecording() {
        #expect(RecordingState.idle.acceptsRollingBufferPreloadPreview)
        #expect(RecordingState.recording.acceptsRollingBufferPreloadPreview)
        #expect(!RecordingState.starting.acceptsRollingBufferPreloadPreview)
        #expect(!RecordingState.transcribing.acceptsRollingBufferPreloadPreview)
        #expect(!RecordingState.enhancing.acceptsRollingBufferPreloadPreview)
        #expect(!RecordingState.busy.acceptsRollingBufferPreloadPreview)
    }

    @Test @MainActor func rollingPreloadQuickReleaseDurationUsesMono16kPCMByteCount() {
        #expect(VoiceInkEngine.durationForMono16kPCMData(Data(count: 32_000)) == 1.0)
        #expect(VoiceInkEngine.durationForMono16kPCMData(Data(count: 16_000)) == 0.5)
        #expect(VoiceInkEngine.durationForMono16kPCMData(Data()) == 0)
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

    @Test func contextualCapitalizationLowercasesTitlecaseTextAfterMidSentencePrefix() async throws {
        let result = ContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is the "
        )

        #expect(result == "model output")
    }

    @Test func contextualCapitalizationKeepsTitlecaseTextAfterSentenceBoundary() async throws {
        let result = ContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is done. "
        )

        #expect(result == "Model output")
    }

    @Test func contextualCapitalizationCapitalizesLowercaseTextAtDocumentStart() async throws {
        let result = ContextualCapitalizationFormatter.format(
            "model output",
            beforeCursor: ""
        )

        #expect(result == "Model output")
    }

    @Test func contextualCapitalizationPreservesAcronymsAfterMidSentencePrefix() async throws {
        let result = ContextualCapitalizationFormatter.format(
            "API response",
            beforeCursor: "call the "
        )

        #expect(result == "API response")
    }

    @Test func contextualCapitalizationSkipsCursorContextWhenTextCannotChange() async throws {
        #expect(ContextualCapitalizationFormatter.needsCursorContext("API response") == false)
        #expect(ContextualCapitalizationFormatter.needsCursorContext("iPhone setup") == false)
        #expect(ContextualCapitalizationFormatter.needsCursorContext("1234") == false)
    }

    @Test func contextualCapitalizationReadsCursorContextWhenTextCanChange() async throws {
        #expect(ContextualCapitalizationFormatter.needsCursorContext("Model output") == true)
        #expect(ContextualCapitalizationFormatter.needsCursorContext("model output") == true)
    }

    @Test func resolvesAPIKeyEnvironmentReference() async throws {
        let environment = ["ELEVENLABS_API_KEY": "test-key"]

        #expect(APIKeyManager.resolveAPIKeyReference("$ELEVENLABS_API_KEY", environment: environment) == "test-key")
        #expect(APIKeyManager.resolveAPIKeyReference("${ELEVENLABS_API_KEY}", environment: environment) == "test-key")
        #expect(APIKeyManager.resolveAPIKeyReference("literal-key", environment: environment) == "literal-key")
        #expect(APIKeyManager.resolveAPIKeyReference("$MISSING", environment: environment) == nil)
    }

    @Test @MainActor func wordReplacementServiceUsesWarmedCacheUntilInvalidated() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        let service = WordReplacementService.shared
        service.invalidateCache()
        defer { service.invalidateCache() }

        context.insert(WordReplacement(originalText: "voice ink", replacementText: "roma"))
        try context.save()

        service.warmCache(using: context)
        #expect(service.applyReplacements(to: "voice ink", using: context) == "roma")

        context.insert(WordReplacement(originalText: "quick release", replacementText: "instant paste"))
        try context.save()

        #expect(service.applyReplacements(to: "quick release", using: context) == "quick release")

        service.invalidateCache()
        #expect(service.applyReplacements(to: "quick release", using: context) == "instant paste")
    }

    @Test @MainActor func dictionaryWordReplacementSaveInvalidatesWarmedCache() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        let service = WordReplacementService.shared
        service.invalidateCache()
        defer { service.invalidateCache() }

        service.warmCache(using: context)
        #expect(service.applyReplacements(to: "voice ink", using: context) == "voice ink")

        let error = DictionaryService.addWordReplacement(
            original: "voice ink",
            replacement: "roma",
            existing: [],
            context: context
        )

        #expect(error == nil)
        #expect(service.applyReplacements(to: "voice ink", using: context) == "roma")
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

        let triggerPrompt = CustomPrompt(
            title: "Fast Trigger",
            promptText: "Clean this",
            triggerWords: ["clean"]
        )
        service.customPrompts = [triggerPrompt]

        #expect(service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.map(\.id) == [triggerPrompt.id])

        service.customPrompts = [
            CustomPrompt(
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
        let triggerPrompt = CustomPrompt(
            title: "Assistant Trigger",
            promptText: "Answer directly",
            triggerWords: ["answer"]
        )
        service.customPrompts = [
            CustomPrompt(title: "No Trigger", promptText: "Clean this"),
            triggerPrompt
        ]

        let detection = PromptDetectionService().analyzeText("answer what is this?", with: service)

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
        let manager = RecorderUIManager()

        #expect(manager.activeSessionToggleAction(for: .starting) == .toggleRecord)
        #expect(manager.activeSessionToggleAction(for: .recording) == .toggleRecord)
        #expect(manager.activeSessionToggleAction(for: .transcribing) == .cancelRecording)
        #expect(manager.activeSessionToggleAction(for: .enhancing) == .cancelRecording)
        #expect(manager.activeSessionToggleAction(for: .idle) == .dismissRecorder)
        #expect(manager.activeSessionToggleAction(for: .busy) == .dismissRecorder)
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

    @Test @MainActor func specialModeKeyDownPreparesWithoutStartingRecorder() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0
        var directCommitCount = 0

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
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                return true
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

        #expect(prepareQuickReleaseCount == 1)
        #expect(directCommitCount == 0)
        #expect(discardQuickReleaseCount == 0)
        #expect(toggleCount == 0)
        #expect(cancelCount == 0)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCleanReleaseCommitsReadyPreloadWithoutStartingRecorder() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0
        var directCommitCount = 0

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
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                recordingState = .transcribing
                return true
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext()
        )

        #expect(prepareQuickReleaseCount == 1)
        #expect(directCommitCount == 1)
        #expect(discardQuickReleaseCount == 0)
        #expect(toggleCount == 0)
        #expect(cancelCount == 0)
        #expect(recordingState == .transcribing)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeTypingEvidenceDiscardsWithoutStartingRecorder() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0
        var directCommitCount = 0

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
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                recordingState = .transcribing
                return true
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true)
        )

        #expect(prepareQuickReleaseCount == 1)
        #expect(discardQuickReleaseCount == 1)
        #expect(directCommitCount == 0)
        #expect(toggleCount == 0)
        #expect(cancelCount == 0)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeUnreliableEvidenceDiscardsWithoutStartingRecorder() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0
        var directCommitCount = 0

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
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                recordingState = .transcribing
                return true
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(hasReliableKeyEvidence: false)
        )

        #expect(prepareQuickReleaseCount == 1)
        #expect(discardQuickReleaseCount == 1)
        #expect(directCommitCount == 0)
        #expect(toggleCount == 0)
        #expect(cancelCount == 0)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCleanReleaseStopsAlreadyVisibleRecorder() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var recordingState = RecordingState.recording
        var sessionActive = true
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var directCommitCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                recordingState = .transcribing
                sessionActive = false
            },
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                return true
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
            eventTime: 1.6,
            mode: .special
        )

        #expect(prepareQuickReleaseCount == 0)
        #expect(directCommitCount == 0)
        #expect(toggleCount == 1)
        #expect(cancelCount == 0)
        #expect(recordingState == .transcribing)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeTypingEvidenceDoesNotCancelAlreadyVisibleRecorder() async throws {
        var recordingState = RecordingState.recording
        var sessionActive = true
        var toggleCount = 0
        var cancelCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0
        var directCommitCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                recordingState = .transcribing
                sessionActive = false
            },
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                return true
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true)
        )

        #expect(prepareQuickReleaseCount == 0)
        #expect(discardQuickReleaseCount == 1)
        #expect(directCommitCount == 0)
        #expect(toggleCount == 0)
        #expect(cancelCount == 0)
        #expect(recordingState == .recording)
        #expect(sessionActive)
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
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 1)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2.5
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [],
            eventTime: 3
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyUpCount == 1)
    }

    @Test func modifierOnlyShortcutTracksOtherKeyDownWithoutReleaseEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutUsesEventTapOrderingWhenTrackingKeyEvidence() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 1)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutTracksSystemDefinedEvidenceDuringPress() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutMarksSecureInputAsUnreliableEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(hasReliableKeyEvidence: false)])
    }

    @Test func modifierOnlyShortcutChecksPressedNonModifierKeysAtRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

        ShortcutMonitor.configureKeyboardStateClientForTesting(
            KeyboardState.Client(isKeyPressed: { keyCode in keyCode == UInt16(kVK_ANSI_X) })
        )
        defer {
            monitor.stop()
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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true)])
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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 0)
    }

    @Test func modifierOnlyShortcutMarksOtherKeyUpAsTyping() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlyShortcutTracksOtherModifierPressAndRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    private func makeWordReplacementContainer() throws -> ModelContainer {
        let schema = Schema([WordReplacement.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSessionMetricContainer() throws -> ModelContainer {
        let schema = Schema([Transcription.self, SessionMetric.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
