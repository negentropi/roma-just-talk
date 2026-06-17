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
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.keyDownBehaviorKey] as? String == SpecialShortcutKeyDownBehavior.preloadOnly.rawValue)
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.allowsKeyDownOnlyTriggerKey] as? Bool == true)
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

    @Test func specialShortcutOptionsDefaultToPreloadOnly() {
        #expect(SpecialShortcutOptions().keyDownBehavior == .preloadOnly)
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

    @Test @MainActor func specialModeStopsWhenNoOtherKeyWasReleased() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
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
            context: ShortcutPressContext(didReleaseOtherKeyDuringPress: false)
        )

        #expect(toggleCount == 2)
        #expect(cancelCount == 0)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCancelsWhenAnotherKeyWasReleased() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
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
            context: ShortcutPressContext(didReleaseOtherKeyDuringPress: true)
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCleanLongPressStopsRecording() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .startRecording,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.6,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 2)
        #expect(cancelCount == 0)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCancelsShortNoEvidencePresses() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .startRecording,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModePreloadOnlyLongPressCommits() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.6,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .transcribing)
    }

    @Test @MainActor func specialModePreloadOnlyCommitsShortNoEvidencePresses() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .transcribing)
    }

    @Test @MainActor func specialModePreloadOnlyIgnoresUnreliableEvidence() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .special,
            context: ShortcutPressContext(hasReliableKeyEvidence: false),
            specialOptions: specialOptions
        )

        #expect(toggleCount == 0)
        #expect(recordingState == .idle)
    }

    @Test @MainActor func specialModePreloadOnlyRequestsDeferredStopWhileStarting() async throws {
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        defer { SpecialShortcutEmptyTranscriptionFallback.resetForTesting() }

        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if toggleCount == 1 {
                    recordingState = .starting
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.6,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .transcribing)
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

    @Test @MainActor func specialModeCancelsWhenAnotherKeyWasPressedBeforeModifierRelease() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .startRecording,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false),
            specialOptions: specialOptions
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCanCancelKeyDownOnlyTypingWhenFlexIsOff() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .startRecording,
            allowsKeyDownOnlyTrigger: false,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false),
            specialOptions: specialOptions
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModePreloadOnlyCommitsReadyPreloadWithoutStartingRecorder() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var directCommitCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
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
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 0)
        #expect(recordingState == .idle)
        #expect(prepareQuickReleaseCount == 1)

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(),
            specialOptions: specialOptions
        )

        #expect(directCommitCount == 1)
        #expect(toggleCount == 0)
        #expect(prepareQuickReleaseCount == 1)
        #expect(discardQuickReleaseCount == 0)
        #expect(recordingState == .transcribing)
    }

    @Test @MainActor func specialModePreloadOnlyFallsBackToRecorderWhenNoPreloadIsReady() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var directCommitCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            prepareQuickReleaseContext: { _ in
                prepareQuickReleaseCount += 1
            },
            discardQuickReleaseContext: {
                discardQuickReleaseCount += 1
            },
            commitReadyRollingBufferPreload: { _ in
                directCommitCount += 1
                return false
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(),
            specialOptions: specialOptions
        )

        #expect(directCommitCount == 1)
        #expect(toggleCount == 2)
        #expect(prepareQuickReleaseCount == 1)
        #expect(discardQuickReleaseCount == 1)
        #expect(recordingState == .transcribing)
    }

    @Test @MainActor func specialModePreloadOnlyDiscardsPreparedContextOnUnsafeEvidence() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0
        var directCommitCount = 0
        var prepareQuickReleaseCount = 0
        var discardQuickReleaseCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive = true
                recordingState = .recording
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
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true),
            specialOptions: specialOptions
        )

        #expect(prepareQuickReleaseCount == 1)
        #expect(discardQuickReleaseCount == 1)
        #expect(directCommitCount == 0)
        #expect(toggleCount == 0)
        #expect(recordingState == .idle)
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
