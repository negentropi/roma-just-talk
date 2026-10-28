import AppKit
import Foundation
import Testing
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct WritingActionUndoTests {
        @Test @MainActor func confirmedUnicodeRewriteRestoresExactTextAndOriginalSelectionOnce() async throws {
            let source = "🧪 before e\u{301}, 👩🏽‍💻 after\r\n尾"
            let range = (source as NSString).range(of: "e\u{301}, 👩🏽‍💻")
            let access = UndoWritingAccess(value: source, range: range)
            let controller = WritingActionUndoController()
            let outcome = try await deliver("短い\n😀", using: access, controller: controller)
            #expect(outcome.isConfirmed)
            #expect(controller.isAvailable)
            #expect(access.textAttempts == 1)
            let undo = await controller.undo()
            #expect(undo.didRestoreText)
            guard case .restored = undo else { Issue.record("Original selection was not restored."); return }
            #expect(access.value.utf16.elementsEqual(source.utf16))
            #expect(access.range == range)
            #expect(access.textAttempts == 2)
            #expect(access.rangeWrites == 2)
            #expect(!controller.isAvailable)
            guard case .unavailable = await controller.undo() else { Issue.record("Undo was replayable."); return }
            #expect(access.textAttempts == 2)
        }

        @Test @MainActor func confirmationCallbackRunsBeforeReturnAndSurvivesLateCancellation() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            var canceled = false
            var confirmations = 0
            access.afterTextMutation = { canceled = true }
            let id = controller.beginDelivery(transcriptionID: UUID())
            let target = try access.target()
            let outcome = await target.deliver(
                with: "new",
                shouldCancel: { canceled },
                willAttempt: { try controller.willAttemptDelivery(id) },
                onConfirmed: { edit in
                    confirmations += 1
                    controller.confirmedDelivery(edit, for: id)
                    #expect(controller.isBusy)
                }
            )
            #expect(outcome.isConfirmed)
            #expect(confirmations == 1)
            controller.finishDelivery(outcome, for: id)
            #expect(controller.isAvailable)
            access.afterTextMutation = nil
            #expect(await controller.undo().didRestoreText)
        }

        @Test @MainActor func confirmedWriteWithoutSafeCaretOrRangeSetterDoesNotArmUndo() async throws {
            for missingCaret in [true, false] {
                let access = UndoWritingAccess()
                if missingCaret { access.collapsesCaret = false } else { access.supportsUndoSelection = false }
                let controller = WritingActionUndoController()
                let result = try await deliver("new", using: access, controller: controller)
                #expect(result.isConfirmed)
                #expect(access.value == "prefix new suffix")
                #expect(access.textAttempts == 1)
                #expect(!controller.isAvailable)
            }
        }

        @Test @MainActor func unchangedOutputAndEmptyOriginalSelectionNeverCreateAuthority() async throws {
            let unchanged = UndoWritingAccess()
            let controller = WritingActionUndoController()
            #expect(try await deliver("old", using: unchanged, controller: controller).isConfirmed)
            #expect(!controller.isAvailable)
            let insertion = UndoWritingAccess(value: "prefix  suffix", range: NSRange(location: 7, length: 0))
            #expect(try await deliver("new", using: insertion, controller: controller).isConfirmed)
            #expect(!controller.isAvailable)
            #expect(insertion.value == "prefix new suffix")
        }

        @Test @MainActor func uncertainNativeAttemptRetiresPreviousAuthorityEvenWhenValueDidNotChange() async throws {
            let original = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: original, controller: controller)
            #expect(controller.isAvailable)
            let uncertain = UndoWritingAccess()
            uncertain.textBehavior = .unchanged(.cannotComplete)
            let outcome = try await deliver("different", using: uncertain, controller: controller)
            guard case .attemptedUnconfirmed = outcome else { Issue.record("Native AX attempt was misclassified."); return }
            #expect(uncertain.textAttempts == 1)
            #expect(uncertain.value == "prefix old suffix")
            #expect(!controller.isAvailable)
        }

        @Test @MainActor func rejectedPreparationAndUnauthorizedAttemptPreservePreviousAuthority() async throws {
            let original = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: original, controller: controller)
            let rejected = UndoWritingAccess()
            rejected.validationFailure = .targetChanged
            let outcome = try await deliver("different", using: rejected, controller: controller)
            #expect(!outcome.wasAttempted)
            #expect(rejected.textAttempts == 0)
            #expect(controller.isAvailable)
            let target = try original.target()
            let refused = await target.deliver(with: "blocked", willAttempt: { throw CancellationError() })
            #expect(!refused.wasAttempted)
            #expect(original.textAttempts == 1)
        }

        @Test @MainActor func textCaretWindowProcessAndProtectionDriftRefuseWithoutInverseAttempt() async throws {
            for drift in UndoWritingAccess.Drift.allCases {
                let access = UndoWritingAccess()
                let controller = WritingActionUndoController()
                _ = try await deliver("café 😀", using: access, controller: controller)
                access.apply(drift)
                let value = access.value
                let range = access.range
                let outcome = await controller.undo()
                #expect(!outcome.didRestoreText)
                #expect(access.textAttempts == 1)
                #expect(access.rangeWrites == 0)
                #expect(access.value.utf16.elementsEqual(value.utf16))
                #expect(access.range == range)
                #expect(!controller.isAvailable)
            }
        }

        @Test @MainActor func errorAfterRangeChangeAndTextMutationCanStillConfirmEachPostcondition() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            access.rangeError = .cannotComplete
            access.textBehavior = .replace(.cannotComplete)
            guard case .restored = await controller.undo() else { Issue.record("Observed restoration was discarded after AX error."); return }
            #expect(access.value == "prefix old suffix")
            #expect(access.range == NSRange(location: 7, length: 3))
            #expect(access.textAttempts == 2)
        }

        @Test @MainActor func cancellationAfterOwnedRangeSelectionRestoresCaretWithoutTextAttempt() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("long new", using: access, controller: controller)
            let resultCaret = access.range
            var canceled = false
            access.afterRangeMutation = { canceled = true }
            let outcome = await controller.undo(shouldCancel: { canceled })
            guard case .notAttempted(let error) = outcome else { Issue.record("Canceled Undo attempted text."); return }
            #expect(error is CancellationError)
            #expect(access.value == "prefix long new suffix")
            #expect(access.range == resultCaret)
            #expect(access.textAttempts == 1)
            #expect(controller.isAvailable)
        }

        @Test @MainActor func cancellationBeforeUndoLeavesTextSelectionAndAuthorityUntouched() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            let caret = access.range
            guard case .notAttempted(let error) = await controller.undo(shouldCancel: { true }) else {
                Issue.record("Preflight cancellation did not refuse Undo."); return
            }
            #expect(error is CancellationError)
            #expect(access.value == "prefix new suffix")
            #expect(access.range == caret)
            #expect(access.rangeWrites == 0)
            #expect(access.textAttempts == 1)
            #expect(controller.isAvailable)
        }

        @Test @MainActor func newerStateDuringRangeSelectionIsNeverOverwrittenByCleanup() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            access.afterRangeMutation = {
                access.value = "User's newer document"
                access.range = NSRange(location: 0, length: 0)
                controller.retireForExternalMutation()
            }
            let result = await controller.undo()
            #expect(!result.didRestoreText)
            #expect(access.value == "User's newer document")
            #expect(access.range == NSRange(location: 0, length: 0))
            #expect(access.rangeWrites == 1)
            #expect(access.textAttempts == 1)
            #expect(!controller.isAvailable)
        }

        @Test @MainActor func newerPendingDeliveryCancelsUndoBeforeItsInverseTextAttempt() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("long new", using: access, controller: controller)
            var pending: WritingActionUndoController.DeliveryID?
            access.afterRangeMutation = { pending = controller.beginDelivery(transcriptionID: UUID()) }
            guard case .notAttempted(let error) = await controller.undo() else {
                Issue.record("Superseded Undo performed an inverse text attempt."); return
            }
            #expect(error is CancellationError)
            #expect(access.value == "prefix long new suffix")
            #expect(access.textAttempts == 1)
            #expect(access.rangeWrites == 1)
            #expect(controller.isBusy)
            let newOwner = try #require(pending)
            #expect(controller.isCurrentDelivery(newOwner))
            controller.finishDelivery(.notAttempted(CancellationError()), for: newOwner)
            #expect(!controller.isBusy)
        }

        @Test @MainActor func restoredTextWithUnrestoredSelectionConsumesAuthorityWithoutRepeatingEdit() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            access.refuseRangeWriteNumber = 2
            guard case .textRestoredSelectionUnconfirmed = await controller.undo() else {
                Issue.record("Selection failure was not distinguished from text restoration."); return
            }
            #expect(access.value == "prefix old suffix")
            #expect(access.textAttempts == 2)
            #expect(!controller.isAvailable)
            _ = await controller.undo()
            #expect(access.textAttempts == 2)
        }

        @Test @MainActor func newerOwnerAfterInverseTextAttemptPreventsOldSelectionRestoration() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("long new", using: access, controller: controller)
            access.afterTextMutation = { controller.retireForExternalMutation() }
            guard case .textRestoredSelectionUnconfirmed = await controller.undo() else {
                Issue.record("Old inverse changed selection after losing ownership."); return
            }
            #expect(access.value == "prefix old suffix")
            #expect(access.range == NSRange(location: 10, length: 0))
            #expect(access.rangeWrites == 1)
            #expect(access.textAttempts == 2)
            #expect(!controller.isAvailable)
        }

        @Test @MainActor func uncertainInverseConsumesAuthorityAndDoesNotRetryOrRollback() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            access.textBehavior = .partial("prefix partial suffix", .cannotComplete)
            guard case .attemptedUnconfirmed = await controller.undo() else { Issue.record("Partial inverse was not retained as uncertain."); return }
            #expect(access.value == "prefix partial suffix")
            #expect(access.textAttempts == 2)
            #expect(!controller.isAvailable)
            _ = await controller.undo()
            #expect(access.textAttempts == 2)
        }

        @Test @MainActor func staleDeliveryCannotInstallReceiptOrClearNewerBusyOwner() async throws {
            let first = UndoWritingAccess()
            let second = UndoWritingAccess(value: "two old tail", range: NSRange(location: 4, length: 3))
            let controller = WritingActionUndoController()
            let firstID = controller.beginDelivery(transcriptionID: UUID())
            let firstTarget = try first.target()
            let firstOutcome = await firstTarget.deliver(
                with: "first", willAttempt: { try controller.willAttemptDelivery(firstID) },
                onConfirmed: { controller.confirmedDelivery($0, for: firstID) }
            )
            guard case .confirmed(let firstReceipt) = firstOutcome else { Issue.record("First write failed."); return }
            let secondID = controller.beginDelivery(transcriptionID: UUID())
            let secondTarget = try second.target()
            let secondOutcome = await secondTarget.deliver(
                with: "second", willAttempt: { try controller.willAttemptDelivery(secondID) },
                onConfirmed: { controller.confirmedDelivery($0, for: secondID) }
            )
            controller.confirmedDelivery(firstReceipt, for: firstID)
            controller.finishDelivery(firstOutcome, for: firstID)
            #expect(controller.isBusy)
            #expect(!controller.isAvailable)
            controller.finishDelivery(secondOutcome, for: secondID)
            #expect(await controller.undo().didRestoreText)
            #expect(second.value == "two old tail")
            #expect(first.value == "prefix first suffix")
        }

        @Test @MainActor func pendingDeliveryBlocksUndoAndExternalMutationRetiresOnlyCurrentAuthority() async throws {
            let access = UndoWritingAccess()
            let controller = WritingActionUndoController()
            _ = try await deliver("new", using: access, controller: controller)
            let pending = controller.beginDelivery(transcriptionID: UUID())
            guard case .busy = await controller.undo() else { Issue.record("Undo ran while delivery was busy."); return }
            #expect(access.textAttempts == 1)
            controller.finishDelivery(.notAttempted(CancellationError()), for: pending)
            #expect(controller.isAvailable)
            controller.retireForExternalMutation()
            #expect(!controller.isAvailable)
            guard case .unavailable = await controller.undo() else { Issue.record("Retired authority was usable."); return }
        }

        @Test @MainActor func authorizationIsRepeatableWithinOrdinaryFallbackButStopsAfterConfirmation() throws {
            let controller = WritingActionUndoController()
            let id = controller.beginDelivery(transcriptionID: UUID())
            try controller.willAttemptDelivery(id)
            try controller.willAttemptDelivery(id)
            controller.confirmedDelivery(nil, for: id)
            #expect(throws: CancellationError.self) { try controller.willAttemptDelivery(id) }
            controller.finishDelivery(.confirmed(nil), for: id)
            #expect(!controller.isBusy)
        }

        @Test @MainActor func queuedAutoSendOwnershipSurvivesFinishButNotANewerPendingDelivery() {
            let controller = WritingActionUndoController()
            let first = controller.beginDelivery(transcriptionID: UUID())
            controller.finishDelivery(.confirmed(nil), for: first)
            #expect(controller.isLatestDelivery(first))
            #expect(!controller.isCurrentDelivery(first))
            let second = controller.beginDelivery(transcriptionID: UUID())
            #expect(!controller.isLatestDelivery(first))
            #expect(controller.isLatestDelivery(second))
            controller.finishDelivery(.notAttempted(CancellationError()), for: second)
            controller.finishDelivery(.confirmed(nil), for: first)
            #expect(controller.isLatestDelivery(second))
            #expect(!controller.isLatestDelivery(first))
            controller.retireForExternalMutation()
            #expect(!controller.isLatestDelivery(second))
        }

        @Test func refusedKeyboardAuthorizationBalancesCommandWithoutPostingV() throws {
            let events = try #require(CursorTextContextReader.commandVShortcutEvents(
                source: CGEventSource(stateID: .combinedSessionState)
            ))
            var posted: [CGEvent] = []
            let result = CursorTextContextReader.postCommandVShortcutEvents(
                events, targetIsCurrent: { true }, post: { posted.append($0) },
                willAttempt: { throw CancellationError() }
            )
            #expect(!result)
            #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x37, 0x37])
            #expect(posted.last?.flags == [])
        }

        @MainActor private func deliver(
            _ text: String, using access: UndoWritingAccess, controller: WritingActionUndoController
        ) async throws -> WritingTarget.DeliveryOutcome {
            let target = try access.target()
            let id = controller.beginDelivery(transcriptionID: UUID())
            let outcome = await target.deliver(
                with: text, willAttempt: { try controller.willAttemptDelivery(id) },
                onConfirmed: { controller.confirmedDelivery($0, for: id) }
            )
            controller.finishDelivery(outcome, for: id)
            return outcome
        }
    }
}

@MainActor
private final class UndoWritingAccess: WritingTarget.Access {
    enum TextBehavior {
        case replace(AXError)
        case unchanged(AXError)
        case partial(String, AXError)
    }
    enum Drift: CaseIterable { case text, normalization, caret, window, process, protectedField, terminated }
    var value: String
    var range: NSRange
    var textBehavior: TextBehavior = .replace(.success)
    var collapsesCaret = true
    var supportsUndoSelection = true
    var isUndoTargetAlive = true
    var identityMatches = true
    var validationFailure: WritingTarget.Failure?
    var rangeError: AXError = .success
    var refuseRangeWriteNumber: Int?
    var afterTextMutation: (() -> Void)?
    var afterRangeMutation: (() -> Void)?
    private(set) var textAttempts = 0
    private(set) var rangeWrites = 0

    init(value: String = "prefix old suffix", range: NSRange = NSRange(location: 7, length: 3)) {
        self.value = value
        self.range = range
    }
    func target() throws -> WritingTarget {
        WritingTarget(snapshot: try #require(readSnapshot()), access: self)
    }
    func validate() throws { if let validationFailure { throw validationFailure } }
    func isUndoTargetApplication(_ application: NSRunningApplication) -> Bool { false }
    func readSnapshot() -> WritingTarget.TextSnapshot? { WritingTarget.TextSnapshot(value: value, range: range) }
    func readValue() -> String? { value }
    func validateUndoIdentity() throws {
        try validate()
        guard isUndoTargetAlive, identityMatches, supportsUndoSelection else { throw WritingTarget.Failure.targetChanged }
    }
    func replaceSelection(_ text: String, willAttempt: () throws -> Void) throws -> AXError? {
        let before = try #require(readSnapshot())
        try willAttempt()
        textAttempts += 1
        let error: AXError
        switch textBehavior {
        case .replace(let result):
            value = before.replacement(text)
            range = collapsesCaret ? NSRange(location: before.range.location + text.utf16.count, length: 0)
                : NSRange(location: before.range.location, length: text.utf16.count)
            error = result
        case .unchanged(let result): error = result
        case .partial(let replacement, let result): value = replacement; error = result
        }
        afterTextMutation?()
        return error
    }
    func setSelectedRange(_ selected: NSRange) -> AXError? {
        guard supportsUndoSelection else { return nil }
        rangeWrites += 1
        guard rangeWrites != refuseRangeWriteNumber else { return .cannotComplete }
        range = selected
        afterRangeMutation?()
        return rangeError
    }
    func apply(_ drift: Drift) {
        switch drift {
        case .text: value += " user edit"
        case .normalization: value = value.decomposedStringWithCanonicalMapping
        case .caret: range = NSRange(location: 0, length: 0)
        case .window, .process: identityMatches = false
        case .protectedField: validationFailure = .protectedField
        case .terminated: isUndoTargetAlive = false
        }
    }
}
