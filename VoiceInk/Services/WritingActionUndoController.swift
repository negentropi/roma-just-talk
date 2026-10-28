import AppKit
import Combine
import Foundation

/// One live edit capability, owned by the engine rather than a recording session.
@MainActor
final class WritingActionUndoController: NSObject, ObservableObject {
    struct DeliveryID: Equatable {
        fileprivate let value = UUID()
        let transcriptionID: UUID
    }

    @Published private(set) var isAvailable = false
    @Published private(set) var isBusy = false

    private var edit: WritingTarget.ConfirmedEdit?
    private var activeDelivery: DeliveryID?
    private var latestDeliveryID: DeliveryID?
    private var attemptedDelivery: DeliveryID?
    private var confirmedDeliveryID: DeliveryID?
    private var activeUndo: UUID?

    override init() {
        super.init()
        // Selector observers are not retained by NotificationCenter and expire with this owner.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(targetApplicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
    }

    func beginDelivery(transcriptionID: UUID) -> DeliveryID {
        let id = DeliveryID(transcriptionID: transcriptionID)
        activeDelivery = id
        latestDeliveryID = id
        activeUndo = nil
        attemptedDelivery = nil
        confirmedDeliveryID = nil
        publishAvailability()
        return id
    }

    func isCurrentDelivery(_ id: DeliveryID) -> Bool { activeDelivery == id }
    func isLatestDelivery(_ id: DeliveryID) -> Bool { latestDeliveryID == id }

    func willAttemptDelivery(_ id: DeliveryID) throws {
        guard isCurrentDelivery(id), confirmedDeliveryID != id else { throw CancellationError() }
        if attemptedDelivery == id { return }
        // A failed preparation leaves the previous capability; an actual text attempt retires it.
        edit = nil
        activeUndo = nil
        attemptedDelivery = id
        publishAvailability()
    }

    func confirmedDelivery(_ confirmedEdit: WritingTarget.ConfirmedEdit?, for id: DeliveryID) {
        guard activeDelivery == id, attemptedDelivery == id else { return }
        edit = confirmedEdit
        confirmedDeliveryID = id
        publishAvailability()
    }

    func finishDelivery(_ outcome: WritingTarget.DeliveryOutcome, for id: DeliveryID) {
        guard activeDelivery == id else { return }
        activeDelivery = nil
        attemptedDelivery = nil
        confirmedDeliveryID = nil
        if case .attemptedUnconfirmed = outcome { edit = nil }
        publishAvailability()
    }

    /// Ordinary dictation and Paste Last retire writing authority before their editor attempt.
    func retireForExternalMutation() {
        edit = nil
        activeDelivery = nil
        latestDeliveryID = nil
        attemptedDelivery = nil
        confirmedDeliveryID = nil
        activeUndo = nil
        publishAvailability()
    }

    func undo(shouldCancel: @escaping () -> Bool = { false }) async -> WritingTarget.UndoOutcome {
        guard !isBusy else { return .busy }
        guard let candidate = edit else { return .unavailable }
        guard candidate.isTargetAlive else {
            edit = nil
            publishAvailability()
            return .unavailable
        }
        let operationID = UUID()
        activeUndo = operationID
        publishAvailability()
        let outcome = await candidate.undo(
            shouldCancel: { self.activeUndo != operationID || shouldCancel() },
            ownsOperation: { self.activeUndo == operationID },
            willAttempt: {
                guard self.activeUndo == operationID else { throw CancellationError() }
                self.edit = nil
                self.publishAvailability()
            }
        )
        // A newer delivery owns its own busy state and must survive this late completion.
        guard activeUndo == operationID else { return outcome }
        activeUndo = nil
        if edit === candidate, !candidate.matchesCurrentResult() { edit = nil }
        publishAvailability()
        return outcome
    }

    @objc nonisolated private func targetApplicationTerminated(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        Task { @MainActor [weak self] in
            guard let self, let edit = self.edit,
                  !edit.isTargetAlive || application.map({ edit.belongs(to: $0) }) == true else { return }
            self.edit = nil
            self.activeUndo = nil
            self.publishAvailability()
        }
    }

    private func publishAvailability() {
        isBusy = activeDelivery != nil || activeUndo != nil
        isAvailable = edit != nil && !isBusy
    }
}
