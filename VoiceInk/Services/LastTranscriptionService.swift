import Foundation
import SwiftData
import VoiceInkCore

class LastTranscriptionService: ObservableObject {
    
    static func getLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = VoiceInkLastTranscriptionPolicy.fetchLimit
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            guard let candidate = VoiceInkLastTranscriptionPolicy.firstPasteableCandidate(
                in: transcriptions.map(\.lastTranscriptionCandidate),
                excluding: excludedID
            ) else {
                return nil
            }
            return transcriptions.first { $0.id == candidate.id }
        } catch {
            print(
                VoiceInkLastTranscriptionPolicy.fetchFailedDiagnosticMessage(
                    errorDescription: String(describing: error)
                )
            )
            return nil
        }
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                showNotification(VoiceInkLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToCopy = VoiceInkLastTranscriptionPolicy.pasteText(
            for: lastTranscription.lastTranscriptionCandidate,
            preference: .preferred
        )
        
        let success = ClipboardManager.copyToClipboard(textToCopy)
        
        Task { @MainActor in
            showNotification(VoiceInkLastTranscriptionPolicy.copyCompletionNotification(didCopy: success))
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) {
        guard let lastTranscription = getLastTranscription(from: modelContext, excluding: excludedID) else {
            Task { @MainActor in
                showNotification(VoiceInkLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToPaste = VoiceInkLastTranscriptionPolicy.pasteText(
            for: lastTranscription.lastTranscriptionCandidate,
            preference: .original
        )

        Task { @MainActor in
            CursorPaster.pasteAtCursor(CursorPaster.preparedTextForPaste(textToPaste))
        }
    }
    
    static func pasteLastEnhancement(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                showNotification(VoiceInkLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToPaste = VoiceInkLastTranscriptionPolicy.pasteText(
            for: lastTranscription.lastTranscriptionCandidate,
            preference: .preferred
        )

        Task { @MainActor in
            CursorPaster.pasteAtCursor(CursorPaster.preparedTextForPaste(textToPaste))
        }
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURL = lastTranscription.existingAudioFileURL() else {
                showNotification(
                    VoiceInkLastTranscriptionPolicy.retryPreflightFailureNotification(.missingAudio)
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                showNotification(
                    VoiceInkLastTranscriptionPolicy.retryPreflightFailureNotification(.noTranscriptionModelSelected)
                )
                return
            }

            let transcriptionService = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: serviceRegistry,
                enhancementService: enhancementService
            )
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: currentModel)

                let textToCopy = VoiceInkLastTranscriptionPolicy.pasteText(
                    for: newTranscription.lastTranscriptionCandidate,
                    preference: .preferred
                )
                let didCopy = ClipboardManager.copyToClipboard(textToCopy)

                showNotification(
                    retryCompletionNotification(
                        processingFailureReason: newTranscription.processingFailureReason,
                        didCopy: didCopy
                    )
                )
            } catch {
                if Task.isCancelled || error is CancellationError {
                    showNotification(retryCanceledNotification)
                } else {
                    showNotification(VoiceInkLastTranscriptionPolicy.retryFailureNotification(for: error))
                }
            }
        }
    }

    /// One result notice per retry. A saved retry whose Light/Clarity cleanup failed keeps
    /// the original recognition, so the notice must not read as a cleaned-up success.
    private static func retryCompletionNotification(
        processingFailureReason: String?,
        didCopy: Bool
    ) -> VoiceInkLastTranscriptionNotificationPresentation {
        guard let processingFailureReason else {
            return didCopy
                ? VoiceInkLastTranscriptionPolicy.retrySuccessNotification
                : VoiceInkLastTranscriptionNotificationPresentation(
                    title: VoiceInkTranscriptPresentation.failedToCopyTranscriptionTitle,
                    kind: .error
                )
        }

        let headline = didCopy
            ? "Cleanup didn’t finish. Original transcription copied to clipboard."
            : "Cleanup didn’t finish, and the original transcription couldn’t be copied."
        let reason = processingFailureReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceInkLastTranscriptionNotificationPresentation(
            title: reason.isEmpty ? headline : "\(headline) \(reason)",
            kind: didCopy ? .warning : .error
        )
    }

    private static let retryCanceledNotification = VoiceInkLastTranscriptionNotificationPresentation(
        title: "Retry canceled. Clipboard unchanged.",
        kind: .info
    )

    @MainActor
    private static func showNotification(_ presentation: VoiceInkLastTranscriptionNotificationPresentation) {
        NotificationManager.shared.showNotification(
            title: presentation.title,
            type: presentation.kind
        )
    }
}

private extension Transcription {
    var lastTranscriptionCandidate: VoiceInkLastTranscriptionCandidate<UUID> {
        VoiceInkLastTranscriptionCandidate(
            id: id,
            rawText: text,
            enhancedText: enhancedText,
            status: transcriptionState
        )
    }
}

@MainActor
enum SpecialShortcutEmptyTranscriptionFallback {
    private struct PendingFallback {
        let createdAt: Date
    }

    private static var pendingFallback: PendingFallback?

    static func scheduleFallback() {
        pendingFallback = PendingFallback(createdAt: Date())
    }

    static func clear() {
        pendingFallback = nil
    }

    static func consumeIfNeeded(for transcription: Transcription, modelContext: ModelContext) -> Bool {
        guard let pendingFallback else {
            return false
        }

        self.pendingFallback = nil

        guard VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
            createdAt: pendingFallback.createdAt,
            transcriptionStatus: transcription.transcriptionState,
            rawText: transcription.text,
            enhancedText: transcription.enhancedText
        ) else {
            return false
        }

        LastTranscriptionService.pasteLastTranscription(from: modelContext, excluding: transcription.id)
        return true
    }
}
