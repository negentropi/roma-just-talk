import AppKit
import Carbon.HIToolbox
import Foundation
import os
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test @MainActor func doubleShiftKeepsRecordingAfterReleaseAndAssignedShortcutFinishesOnce() async {
        let probe = SpecialShortcutProbe()
        await probe.doubleTap()
        #expect(probe.effects == ["start"])
        #expect(probe.sessionActive)
        await probe.shift(.down, at: 2)
        await probe.shift(.up, at: 2.04)
        await probe.shift(.up, at: 2.05)
        #expect(probe.effects == ["start", "finish"])
        #expect(!probe.sessionActive)
        await probe.releaseDeadlines()
        #expect(probe.effects == ["start", "finish"])
    }

    @Test @MainActor func shortSingleShiftReleaseWaitsThenFinishesWithEmptyTapFallback() async {
        let probe = SpecialShortcutProbe()
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.03)
        #expect(probe.effects == ["start"])
        await probe.releaseDeadlines()
        #expect(probe.effects == ["start", "fallback", "finish"])
        #expect(!probe.sessionActive)
    }

    @Test @MainActor func longShiftHoldFinishesImmediatelyWithoutDoubleTapWait() async {
        let probe = SpecialShortcutProbe()
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.8)
        #expect(probe.effects == ["start", "finish"])
        #expect(!probe.sessionActive)
    }

    @Test @MainActor func customSpecialShortcutStartsOnlyAfterSecondShiftRelease() async {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_Space), modifierFlags: [.command])
        let probe = SpecialShortcutProbe(shortcut: shortcut)
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.03)
        #expect(probe.effects.isEmpty)
        await probe.shift(.down, at: 1.06)
        #expect(probe.effects.isEmpty)
        await probe.shift(.up, at: 1.09)
        #expect(probe.effects == ["start"])
        await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 2, mode: .special)
        await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 2.03, mode: .special)
        #expect(probe.effects == ["start", "finish"])
    }

    @Test @MainActor func doubleShiftUsesSameSideAndStrictConfiguredGapBoundary() async {
        let probe = SpecialShortcutProbe(interval: 250)
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.125)
        await probe.shift(.down, at: 1.375)
        await probe.shift(.up, at: 1.5)
        await probe.releaseDeadlines()
        #expect(probe.effects.filter { $0 == "finish" }.count == 2)
        #expect(!probe.sessionActive)

        let inside = SpecialShortcutProbe(interval: 250)
        await inside.shift(.down, at: 1)
        await inside.shift(.up, at: 1.125)
        await inside.shift(.down, at: 1.374)
        await inside.shift(.up, at: 1.5)
        await inside.releaseDeadlines()
        #expect(inside.effects == ["start"])
        #expect(inside.sessionActive)

        let mixed = SpecialShortcutProbe(shortcut: .key(keyCode: UInt16(kVK_Space), modifierFlags: [.command]))
        await mixed.shift(.down, at: 1)
        await mixed.shift(.up, at: 1.03)
        await mixed.shift(.down, at: 1.06, keyCode: UInt16(kVK_RightShift))
        await mixed.shift(.up, at: 1.09, keyCode: UInt16(kVK_RightShift))
        #expect(mixed.effects.isEmpty)
        await mixed.releaseDeadlines()
    }

    @Test @MainActor func intervalOffPreservesOrdinarySpecialHoldAndRelease() async {
        let probe = SpecialShortcutProbe(interval: 0)
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.03)
        #expect(probe.effects.isEmpty)
        await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 2, mode: .special,
                                          specialOptions: probe.options)
        await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 2.5, mode: .special,
                                        specialOptions: probe.options)
        #expect(probe.effects == ["start", "finish"])
    }

    @Test @MainActor func latchedShiftTypingAndUnsafeFinishLeaveRecordingActive() async {
        let probe = SpecialShortcutProbe()
        await probe.doubleTap()
        await probe.shift(.down, at: 2)
        await probe.shift(.invalidated, at: 2.01,
                          context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true))
        await probe.shift(.up, at: 2.04,
                          context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true))
        #expect(probe.effects == ["start"])
        #expect(probe.sessionActive)
        await probe.shift(.down, at: 3)
        await probe.shift(.up, at: 3.04)
        #expect(probe.effects == ["start", "finish"])
    }

    @Test @MainActor func customFinishUsesItsOwnEvidenceAndDoesNotCancelExistingRecording() async {
        let probe = SpecialShortcutProbe(shortcut: .key(keyCode: UInt16(kVK_Space), modifierFlags: [.command]))
        await probe.doubleTap()
        await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 2, mode: .special)
        await probe.shift(.invalidated, at: 2.01, keyCode: UInt16(kVK_Space))
        await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 2.04, mode: .special,
                                        context: VoiceInkShortcutPressContext(hasReliableKeyEvidence: false))
        #expect(probe.effects == ["start"])
        #expect(probe.sessionActive)
        await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 3, mode: .special)
        await probe.shift(.invalidated, at: 3.01, keyCode: UInt16(kVK_Space))
        await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 3.04, mode: .special)
        #expect(probe.effects == ["start", "finish"])

        let existing = SpecialShortcutProbe(shortcut: .key(keyCode: UInt16(kVK_Space), modifierFlags: [.command]))
        existing.sessionActive = true
        existing.state = .recording
        await existing.doubleTap()
        #expect(existing.effects.isEmpty)
        await existing.handler.handleKeyDown(action: .primaryRecording, eventTime: 4, mode: .special)
        await existing.handler.handleKeyUp(action: .primaryRecording, eventTime: 4.04, mode: .special,
                                           context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true))
        #expect(existing.effects.isEmpty)
        #expect(existing.sessionActive)
    }

    @Test @MainActor func chordAndSecureEvidenceCancelOnlyFreshShiftStart() async {
        for context in [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true),
                        VoiceInkShortcutPressContext(hasReliableKeyEvidence: false)] {
            let probe = SpecialShortcutProbe()
            await probe.shift(.down, at: 1)
            await probe.shift(.up, at: 1.03)
            await probe.shift(.invalidated, at: 1.04, context: context)
            await probe.shift(.down, at: 1.06, context: context)
            await probe.shift(.up, at: 1.09, context: context)
            await probe.releaseDeadlines()
            #expect(probe.effects == ["start", "cancel"])
            #expect(!probe.sessionActive)
        }
    }

    @Test @MainActor func slowRecordingStartupStillLatchesAndFinishWhileStartingRunsOnce() async {
        let probe = SpecialShortcutProbe()
        probe.suspendStart = true
        let startup = Task { await probe.shift(.down, at: 1) }
        await probe.flushCallbacks()
        #expect(probe.state == .starting)
        await probe.shift(.up, at: 1.02)
        await probe.shift(.down, at: 1.04)
        await probe.shift(.up, at: 1.06)
        await probe.shift(.down, at: 2)
        await probe.shift(.up, at: 2.04)
        #expect(probe.effects == ["start", "finish"])
        probe.startContinuation?.resume()
        await startup.value
        #expect(probe.effects == ["start", "finish"])
        #expect(!probe.sessionActive)
        await probe.releaseDeadlines()
    }

    @Test @MainActor func startupFailureAndExternalCancelClearStaleLatch() async {
        let probe = SpecialShortcutProbe()
        await probe.doubleTap()
        probe.sessionActive = false
        probe.state = .idle
        await probe.shift(.down, at: 2)
        await probe.shift(.up, at: 2.04)
        await probe.releaseDeadlines()
        #expect(probe.effects == ["start", "start", "fallback", "finish"])

        let failed = SpecialShortcutProbe()
        failed.failStart = true
        await failed.shift(.down, at: 1)
        failed.failStart = false
        await failed.doubleTap(at: 2)
        #expect(failed.effects == ["start", "start"])
        #expect(failed.sessionActive)
        await failed.releaseDeadlines()
    }

    @Test @MainActor func monitorRefreshKeepsFinishAvailableAndStaleDeadlineCannotStopNewSession() async {
        let probe = SpecialShortcutProbe()
        await probe.shift(.down, at: 1)
        await probe.shift(.up, at: 1.03)
        await probe.flushCallbacks()
        probe.handler.resetForMonitorRefresh(availableRecordingActions: [.primaryRecording])
        await probe.releaseDeadlines()
        #expect(probe.effects == ["start"])
        await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 2, mode: .toggle)
        await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 2.04, mode: .toggle)
        #expect(probe.effects == ["start", "finish"])

        let stale = SpecialShortcutProbe()
        await stale.shift(.down, at: 1)
        await stale.shift(.up, at: 1.03)
        await stale.flushCallbacks()
        stale.handler.reset()
        stale.sessionActive = false
        stale.state = .idle
        await stale.doubleTap(at: 2)
        await stale.releaseDeadlines()
        #expect(stale.effects == ["start", "start"])
        #expect(stale.sessionActive)
    }

    @Test @MainActor func rawShiftDoesNotStealAnotherRecordingShortcutSession() async {
        let probe = SpecialShortcutProbe(shortcut: .key(keyCode: UInt16(kVK_Space), modifierFlags: [.command]))
        await probe.shift(.down, at: 1)
        await probe.handler.handleKeyDown(action: .secondaryRecording, eventTime: 1, mode: .toggle)
        await probe.shift(.up, at: 1.03)
        await probe.handler.handleKeyUp(action: .secondaryRecording, eventTime: 1.03, mode: .toggle)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await probe.shift(.down, at: 2)
        await probe.handler.handleKeyDown(action: .secondaryRecording, eventTime: 2, mode: .toggle)
        await probe.shift(.up, at: 2.03)
        await probe.handler.handleKeyUp(action: .secondaryRecording, eventTime: 2.03, mode: .toggle)
        #expect(probe.effects == ["start", "finish"])
        #expect(!probe.sessionActive)
        await probe.releaseDeadlines()
    }

    @Test @MainActor func monitorRoutesShiftOnlyOnceAndRejectsOverlappingShiftsAndTypingBetweenTaps() async {
        let probe = SpecialShortcutProbe()
        let monitor = ShortcutMonitor()
        var assignedDowns = 0
        var assignedUps = 0
        ShortcutMonitor.configureSecureEventInputClientForTesting(.init(isEnabled: { false }))
        ShortcutMonitor.configureKeyboardStateClientForTesting(.init(isKeyPressed: { _ in false }))
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }
        monitor.configureForTesting(
            shortcuts: [.primaryRecording: probe.owner.shortcut],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in assignedDowns += 1 },
            onKeyUp: { _, _, _ in assignedUps += 1 },
            shiftObservedAction: .primaryRecording,
            onShiftEvent: { event in
                Task { @MainActor in
                    await probe.handler.handleShiftEvent(event, owner: probe.owner, options: probe.options)
                }
            }
        )
        for (time, flags) in [(1.0, NSEvent.ModifierFlags.shift), (1.02, []), (1.04, .shift), (1.06, [])] {
            monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: flags, eventTime: time)
        }
        await probe.flushCallbacks()
        #expect(probe.effects == ["start"])
        #expect(assignedDowns == 0)
        #expect(assignedUps == 0)
        await probe.shift(.down, at: 2)
        await probe.shift(.up, at: 2.04)
        #expect(probe.effects == ["start", "finish"])

        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 3)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_RightShift), modifierFlags: [.shift], eventTime: 3.02)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTime: 3.04)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_RightShift), modifierFlags: [], eventTime: 3.06)
        await probe.flushCallbacks()
        #expect(probe.effects == ["start", "finish", "start", "cancel"])
        #expect(!probe.sessionActive)

        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 4)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTime: 4.02)
        monitor.handleKeyDownForTesting(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [], eventTime: 4.03)
        monitor.handleKeyUpForTesting(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [], eventTime: 4.04)
        await probe.flushCallbacks()
        #expect(probe.effects == ["start", "finish", "start", "cancel", "start", "cancel"])
        await probe.releaseDeadlines()
    }
    @Test @MainActor func monitorRejectsSecureDoubleShiftAndDropsCallbacksFromOldGeneration() async {
        let probe = SpecialShortcutProbe()
        let monitor = ShortcutMonitor()
        var secureInput = true
        ShortcutMonitor.configureSecureEventInputClientForTesting(.init(isEnabled: { secureInput }))
        ShortcutMonitor.configureKeyboardStateClientForTesting(.init(isKeyPressed: { _ in false }))
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }
        func configure() {
            monitor.configureForTesting(
                shortcuts: [.primaryRecording: probe.owner.shortcut],
                secureInputBlockedActions: [.primaryRecording],
                handlesModifierOnlyShortcutsInEventTap: true,
                onKeyDown: { _, _ in }, onKeyUp: { _, _, _ in },
                shiftObservedAction: .primaryRecording,
                onShiftEvent: { event in
                    Task { @MainActor in
                        await probe.handler.handleShiftEvent(event, owner: probe.owner, options: probe.options)
                    }
                }
            )
        }
        configure()
        for (time, flags) in [(1.0, NSEvent.ModifierFlags.shift), (1.02, []), (1.04, .shift), (1.06, [])] {
            monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: flags, eventTime: time)
        }
        await probe.flushCallbacks()
        #expect(probe.effects.isEmpty)
        secureInput = false
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 2)
        monitor.stop()
        configure()
        await probe.flushCallbacks()
        #expect(probe.effects.isEmpty)
        for (time, flags) in [(3.0, NSEvent.ModifierFlags.shift), (3.02, []), (3.04, .shift), (3.06, [])] {
            monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: flags, eventTime: time)
        }
        await probe.flushCallbacks()
        #expect(probe.effects == ["start"])
        #expect(probe.sessionActive)
        secureInput = true
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 4)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTime: 4.04)
        await probe.flushCallbacks()
        #expect(probe.effects == ["start"])
        #expect(probe.sessionActive)
        await probe.releaseDeadlines()
    }

    @Test @MainActor func eitherShiftCanLatchCustomShortcutAndLongSecondHoldFinishesAssignedShift() async {
        let right = SpecialShortcutProbe(shortcut: .key(keyCode: UInt16(kVK_Space), modifierFlags: [.command]))
        await right.shift(.down, at: 1, keyCode: UInt16(kVK_RightShift))
        await right.shift(.up, at: 1.02, keyCode: UInt16(kVK_RightShift))
        await right.shift(.down, at: 1.04, keyCode: UInt16(kVK_RightShift))
        await right.shift(.up, at: 1.06, keyCode: UInt16(kVK_RightShift))
        #expect(right.effects == ["start"])
        #expect(right.sessionActive)
        await right.releaseDeadlines()

        let hold = SpecialShortcutProbe()
        await hold.shift(.down, at: 1)
        await hold.shift(.up, at: 1.02)
        await hold.shift(.down, at: 1.04)
        await hold.shift(.up, at: 1.8)
        #expect(hold.effects == ["start", "finish"])
        #expect(!hold.sessionActive)
        await hold.releaseDeadlines()
    }

    @Test @MainActor func monitoredAssignedShiftFinishesExistingRecorderAndSurvivingActionFinishesAfterRefresh() async {
        let probe = SpecialShortcutProbe()
        probe.sessionActive = true
        probe.state = .recording
        let monitor = ShortcutMonitor()
        ShortcutMonitor.configureSecureEventInputClientForTesting(.init(isEnabled: { false }))
        ShortcutMonitor.configureKeyboardStateClientForTesting(.init(isKeyPressed: { _ in false }))
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }
        func configure(owner: SpecialShortcutOwner, action: ShortcutAction, mode: VoiceInkRecordingShortcutMode) {
            monitor.configureForTesting(
                shortcuts: [action: owner.shortcut], handlesModifierOnlyShortcutsInEventTap: true,
                onKeyDown: { action, time in
                    Task { @MainActor in
                        await probe.handler.handleKeyDown(action: action, eventTime: time, mode: mode,
                                                          specialOptions: probe.options)
                    }
                },
                onKeyUp: { action, time, context in
                    Task { @MainActor in
                        await probe.handler.handleKeyUp(action: action, eventTime: time, mode: mode,
                                                        context: context, specialOptions: probe.options)
                    }
                },
                shiftObservedAction: mode == .special ? action : nil,
                onShiftEvent: mode == .special ? { event in
                    Task { @MainActor in
                        await probe.handler.handleShiftEvent(event, owner: owner, options: probe.options)
                    }
                } : nil
            )
        }
        configure(owner: probe.owner, action: .primaryRecording, mode: .special)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 1)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTime: 1.03)
        await probe.flushCallbacks()
        #expect(probe.effects == ["fallback", "finish"])
        #expect(!probe.sessionActive)

        let secondaryOwner = SpecialShortcutOwner(action: .secondaryRecording, shortcut: probe.owner.shortcut)
        configure(owner: secondaryOwner, action: .secondaryRecording, mode: .special)
        for (time, flags) in [(2.0, NSEvent.ModifierFlags.shift), (2.02, []), (2.04, .shift), (2.06, [])] {
            monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: flags, eventTime: time)
        }
        await probe.flushCallbacks()
        #expect(probe.effects == ["fallback", "finish", "start"])
        monitor.stop()
        probe.handler.resetForMonitorRefresh(availableRecordingActions: [.primaryRecording])
        configure(owner: probe.owner, action: .primaryRecording, mode: .toggle)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift], eventTime: 3)
        monitor.handleEventTapFlagsChangedForTesting(keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTime: 3.03)
        await probe.flushCallbacks()
        #expect(probe.effects == ["fallback", "finish", "start", "finish"])
        #expect(!probe.sessionActive)
        await probe.releaseDeadlines()
    }

    @Test @MainActor func stoppingAndCancellationDrainBeforeNextStartAndRefreshKeepsValidPowerModeOwner() async {
        for cancel in [false, true] {
            let probe = SpecialShortcutProbe()
            await probe.doubleTap()
            probe.suspendFinish = !cancel
            probe.suspendCancel = cancel
            let stopping: Task<Void, Never>
            if cancel {
                probe.handler.resetForMonitorRefresh(availableRecordingActions: [.primaryRecording])
                await probe.handler.handleKeyDown(action: .primaryRecording, eventTime: 2, mode: .special)
                await probe.handler.handleKeyUp(action: .primaryRecording, eventTime: 2.03, mode: .special)
                await probe.shift(.down, at: 3)
                stopping = Task {
                    await probe.shift(.invalidated, at: 3.01, context: .init(hasReliableKeyEvidence: false))
                }
            } else {
                await probe.shift(.down, at: 2)
                stopping = Task { await probe.shift(.up, at: 2.03) }
            }
            await probe.flushCallbacks()
            let effectsWhileStopping = probe.effects
            await probe.shift(.down, at: 4)
            #expect(probe.effects == effectsWhileStopping)
            probe.stopContinuation?.resume()
            await stopping.value
            probe.suspendFinish = false
            probe.suspendCancel = false
            await probe.shift(.down, at: 5)
            #expect(probe.effects.last == "start")
            #expect(probe.sessionActive)
            await probe.shift(.up, at: 5.5)
            await probe.releaseDeadlines()
        }

        let powerMode = SpecialShortcutProbe()
        let action = ShortcutAction.powerMode(UUID())
        await powerMode.handler.handleKeyDown(action: action, eventTime: 1, mode: .special)
        powerMode.handler.resetForMonitorRefresh(availableRecordingActions: [.primaryRecording, action])
        await powerMode.handler.handleKeyDown(action: action, eventTime: 2, mode: .special)
        await powerMode.handler.handleKeyUp(action: action, eventTime: 2.03, mode: .special)
        #expect(powerMode.effects == ["start", "finish"])
    }

    @Test @MainActor func expiredSecondDownCannotReplayAfterReleaseOrResetDuringSuspendedFinish() async {
        for resetDuringFinish in [false, true] {
            let probe = SpecialShortcutProbe()
            await probe.shift(.down, at: 1)
            await probe.shift(.up, at: 1.03)
            await probe.flushCallbacks()
            probe.suspendFinish = true
            let expiredPress = Task { await probe.shift(.down, at: 1.5) }
            await probe.flushCallbacks()
            #expect(probe.effects == ["start", "fallback", "finish"])
            if resetDuringFinish {
                probe.handler.reset()
            } else {
                await probe.shift(.up, at: 1.54)
            }
            probe.stopContinuation?.resume()
            await expiredPress.value
            #expect(probe.effects == ["start", "fallback", "finish"])
            #expect(!probe.sessionActive)
            probe.suspendFinish = false
            await probe.doubleTap(at: 2)
            #expect(probe.effects == ["start", "fallback", "finish", "start"])
            #expect(probe.sessionActive)
            await probe.releaseDeadlines()
        }
    }

}

@MainActor
private final class SpecialShortcutProbe {
    var state = VoiceInkRecordingState.idle
    var sessionActive = false
    var effects: [String] = []
    var suspendStart = false
    var failStart = false
    var suspendFinish = false
    var suspendCancel = false
    var stopContinuation: CheckedContinuation<Void, Never>?
    var startContinuation: CheckedContinuation<Void, Never>?
    private var deadlineContinuations: [CheckedContinuation<Void, Never>] = []
    let owner: SpecialShortcutOwner
    let options: SpecialShortcutOptions

    lazy var handler = RecordingShortcutModeHandler(
        logger: Logger(subsystem: "VoiceInkTests", category: "SpecialShortcutHandsFree"),
        canHandleShortcutAction: { true },
        isRecorderVisible: { self.sessionActive },
        recordingState: { self.state },
        toggleMiniRecorder: { _ in
            if self.sessionActive {
                self.effects.append("finish")
                self.sessionActive = false
                self.state = .idle
                if self.suspendFinish { await withCheckedContinuation { self.stopContinuation = $0 } }
            } else {
                self.effects.append("start")
                self.sessionActive = true
                self.state = .starting
                if self.suspendStart {
                    await withCheckedContinuation { self.startContinuation = $0 }
                }
                if self.failStart { self.sessionActive = false }
                self.state = self.sessionActive ? .recording : .idle
            }
        },
        cancelRecording: {
            self.effects.append("cancel")
            self.sessionActive = false
            self.state = .idle
            if self.suspendCancel { await withCheckedContinuation { self.stopContinuation = $0 } }
        },
        sleepForSpecialRelease: { _ in
            await withCheckedContinuation { self.deadlineContinuations.append($0) }
        },
        scheduleEmptyFallback: { self.effects.append("fallback") }
    )

    init(interval: Int = 300, shortcut: Shortcut = .modifierOnly(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift])) {
        owner = SpecialShortcutOwner(action: .primaryRecording, shortcut: shortcut)
        options = SpecialShortcutOptions(pasteLastTranscriptOnEmptyTap: true, doubleShiftTapIntervalMilliseconds: interval)
    }

    func shift(_ edge: ShiftShortcutEvent.Edge, at time: TimeInterval,
               keyCode: UInt16 = UInt16(kVK_Shift), context: VoiceInkShortcutPressContext = .init()) async {
        await handler.handleShiftEvent(.init(edge: edge, keyCode: keyCode, time: time, context: context),
                                       owner: owner, options: options)
    }

    func doubleTap(at time: TimeInterval = 1) async {
        await shift(.down, at: time)
        await shift(.up, at: time + 0.02)
        await shift(.down, at: time + 0.04)
        await shift(.up, at: time + 0.06)
    }

    func flushCallbacks() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func releaseDeadlines() async {
        await flushCallbacks()
        let continuations = deadlineContinuations
        deadlineContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
        await flushCallbacks()
    }
}
