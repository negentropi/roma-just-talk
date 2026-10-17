import Combine
import Foundation
import UIKit
import RomaCore

enum IOSKeyboardDictationDeliveryText {
    static func text(
        _ text: String,
        defaults: UserDefaults = .standard
    ) -> String {
        RomaTranscriptionPasteOutputPolicy.finalPastedText(
            text,
            appendTrailingSpace: RomaAppendTrailingSpacePreference.isEnabled(from: defaults)
        )
    }
}

struct RomaIOSBackgroundExecution {
    struct Token: Equatable {
        let identifier: UIBackgroundTaskIdentifier
    }

    typealias ExpirationHandler = @MainActor @Sendable () -> Void

    let begin: @MainActor (_ name: String, _ expirationHandler: @escaping ExpirationHandler) -> Token?
    let end: @MainActor (_ token: Token) -> Void

    static let live = RomaIOSBackgroundExecution(
        begin: { name, expirationHandler in
            let identifier = UIApplication.shared.beginBackgroundTask(
                withName: name,
                expirationHandler: expirationHandler
            )
            guard identifier != .invalid else { return nil }
            return Token(identifier: identifier)
        },
        end: { token in
            UIApplication.shared.endBackgroundTask(token.identifier)
        }
    )
}

@MainActor
final class IOSTranscriptionTaskCoordinator: ObservableObject {
    static let shared = IOSTranscriptionTaskCoordinator()

    typealias Retranscribe = @MainActor (Transcription) async -> RomaStoredAudioRetranscriptionOutcome
    typealias KeyboardCompletion = @MainActor (_ requestID: UUID, _ text: String) -> Void
    typealias KeyboardFailure = @MainActor (_ requestID: UUID, _ message: String) -> Void
    typealias RunCompletion = @MainActor (RomaStoredAudioRetranscriptionOutcome) -> Void
    typealias RunOperation = @MainActor (Transcription) async -> RomaStoredAudioRetranscriptionOutcome

    @Published private(set) var activeNoteIDs: Set<UUID> = []

    private final class ActiveRun {
        let id = UUID()
        let note: Transcription
        let keyboardRequestID: UUID?
        let persist: @MainActor () -> Void
        let completion: RunCompletion?
        var task: Task<Void, Never>?
        var backgroundToken: RomaIOSBackgroundExecution.Token?

        init(
            note: Transcription,
            keyboardRequestID: UUID?,
            persist: @escaping @MainActor () -> Void,
            completion: RunCompletion?
        ) {
            self.note = note
            self.keyboardRequestID = keyboardRequestID
            self.persist = persist
            self.completion = completion
        }

        nonisolated deinit {}
    }

    private let backgroundExecution: RomaIOSBackgroundExecution
    private let retranscribe: Retranscribe
    private let completeKeyboard: KeyboardCompletion
    private let failKeyboard: KeyboardFailure
    private var runs: [UUID: ActiveRun] = [:]

    init(
        backgroundExecution: RomaIOSBackgroundExecution = .live,
        retranscribe: @escaping Retranscribe = { note in
            await AppSettings.shared.retranscribeStoredAudio(note)
        },
        completeKeyboard: @escaping KeyboardCompletion = { requestID, text in
            AppGroupCoordinator.shared.completeKeyboardDictation(
                requestID: requestID,
                text: IOSKeyboardDictationDeliveryText.text(text),
                shouldLowercase: AppSettings.shared.transcriptionCleanupSettings.lowercaseTranscription,
                shouldInsertReturn: RomaIOSKeyboardAutoSendPreference.isEnabled()
            )
        },
        failKeyboard: @escaping KeyboardFailure = { requestID, message in
            AppGroupCoordinator.shared.failKeyboardDictation(
                requestID: requestID,
                message: message
            )
        }
    ) {
        self.backgroundExecution = backgroundExecution
        self.retranscribe = retranscribe
        self.completeKeyboard = completeKeyboard
        self.failKeyboard = failKeyboard
    }

    // Xcode 26.1-26.3 corrupts actor-isolated deinit back-deployment on Simulator.
    nonisolated deinit {}

    @discardableResult
    func start(
        note: Transcription,
        keyboardRequestID: UUID? = nil,
        persist: @escaping @MainActor () -> Void,
        operation: RunOperation? = nil,
        completion: RunCompletion? = nil
    ) -> Bool {
        guard runs[note.id] == nil else { return false }

        note.transcriptionStatus = .pending
        note.transcriptionError = nil
        persist()

        let run = ActiveRun(
            note: note,
            keyboardRequestID: keyboardRequestID,
            persist: persist,
            completion: completion
        )
        runs[note.id] = run
        activeNoteIDs.insert(note.id)

        let noteID = note.id
        let runID = run.id
        let backgroundToken = backgroundExecution.begin(
            "Transcribe \(note.id.uuidString)"
        ) { [weak self] in
            self?.expire(noteID: noteID, runID: runID)
        }

        // UIKit may invoke expiration immediately when it cannot grant time.
        guard runs[note.id]?.id == run.id else {
            if let backgroundToken {
                backgroundExecution.end(backgroundToken)
            }
            return false
        }
        run.backgroundToken = backgroundToken

        let operation = operation ?? retranscribe
        run.task = Task { [weak self, weak run] in
            guard let self, let run else { return }
            let outcome = await operation(run.note)
            self.complete(run: run, outcome: outcome)
        }
        return true
    }

    func isActive(noteID: UUID) -> Bool {
        activeNoteIDs.contains(noteID)
    }

    @discardableResult
    func cancel(noteID: UUID) -> Bool {
        guard let run = runs[noteID] else { return false }

        run.task?.cancel()
        run.note.markTranscriptionCanceled()
        run.persist()
        run.completion?(.canceled)
        failKeyboardIfNeeded(
            run,
            message: RomaTranscriptPresentation.canceledTranscriptionText
        )
        finish(run)
        return true
    }

    func recoverInterruptedTranscriptions(
        _ notes: [Transcription],
        persist: @MainActor () -> Void
    ) {
        let interrupted = notes.filter {
            $0.transcriptionStatus == .pending && !activeNoteIDs.contains($0.id)
        }
        guard !interrupted.isEmpty else { return }

        for note in interrupted {
            note.markTranscriptionFailed(
                RomaTranscriptPresentation.interruptedProcessingError
            )
        }
        persist()
    }

    private func complete(
        run: ActiveRun,
        outcome: RomaStoredAudioRetranscriptionOutcome
    ) {
        guard runs[run.note.id]?.id == run.id else { return }

        switch outcome {
        case .succeeded(let text):
            if let requestID = run.keyboardRequestID {
                completeKeyboard(requestID, text)
            }
        case .failed(let reason):
            run.note.markTranscriptionFailed(reason)
            failKeyboardIfNeeded(run, message: reason)
        case .canceled:
            run.note.markTranscriptionCanceled()
            failKeyboardIfNeeded(
                run,
                message: RomaTranscriptPresentation.canceledTranscriptionText
            )
        }

        run.persist()
        run.completion?(outcome)
        finish(run)
    }

    private func expire(noteID: UUID, runID: UUID) {
        guard let run = runs[noteID], run.id == runID else { return }

        run.task?.cancel()
        let message = RomaTranscriptPresentation.backgroundProcessingExpiredError
        run.note.markTranscriptionFailed(message)
        run.persist()
        run.completion?(.failed(reason: message))
        failKeyboardIfNeeded(run, message: message)
        finish(run)
    }

    private func failKeyboardIfNeeded(_ run: ActiveRun, message: String) {
        guard let requestID = run.keyboardRequestID else { return }
        failKeyboard(requestID, message)
    }

    private func finish(_ run: ActiveRun) {
        guard runs[run.note.id]?.id == run.id else { return }

        runs.removeValue(forKey: run.note.id)
        activeNoteIDs.remove(run.note.id)
        run.task = nil

        if let backgroundToken = run.backgroundToken {
            run.backgroundToken = nil
            backgroundExecution.end(backgroundToken)
        }
    }
}
