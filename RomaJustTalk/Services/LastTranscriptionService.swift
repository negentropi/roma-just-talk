import Foundation
import SwiftData
import RomaCore

class LastTranscriptionService: ObservableObject {
    
    static func getLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = RomaLastTranscriptionPolicy.fetchLimit
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            guard let candidate = RomaLastTranscriptionPolicy.firstPasteableCandidate(
                in: transcriptions.map(\.lastTranscriptionCandidate),
                excluding: excludedID
            ) else {
                return nil
            }
            return transcriptions.first { $0.id == candidate.id }
        } catch {
            print(
                RomaLastTranscriptionPolicy.fetchFailedDiagnosticMessage(
                    errorDescription: String(describing: error)
                )
            )
            return nil
        }
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                showNotification(RomaLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToCopy = RomaLastTranscriptionPolicy.pasteText(
            for: lastTranscription.lastTranscriptionCandidate,
            preference: .preferred
        )
        
        let success = ClipboardManager.copyToClipboard(textToCopy)
        
        Task { @MainActor in
            showNotification(RomaLastTranscriptionPolicy.copyCompletionNotification(didCopy: success))
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) {
        guard let lastTranscription = getLastTranscription(from: modelContext, excluding: excludedID) else {
            Task { @MainActor in
                showNotification(RomaLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToPaste = RomaLastTranscriptionPolicy.pasteText(
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
                showNotification(RomaLastTranscriptionPolicy.noTranscriptionNotification)
            }
            return
        }
        
        let textToPaste = RomaLastTranscriptionPolicy.pasteText(
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
                    RomaLastTranscriptionPolicy.retryPreflightFailureNotification(.missingAudio)
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                showNotification(
                    RomaLastTranscriptionPolicy.retryPreflightFailureNotification(.noTranscriptionModelSelected)
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

                let textToCopy = RomaLastTranscriptionPolicy.pasteText(
                    for: newTranscription.lastTranscriptionCandidate,
                    preference: .preferred
                )
                ClipboardManager.copyToClipboard(textToCopy)

                showNotification(RomaLastTranscriptionPolicy.retrySuccessNotification)
            } catch {
                showNotification(RomaLastTranscriptionPolicy.retryFailureNotification(for: error))
            }
        }
    }

    @MainActor
    private static func showNotification(_ presentation: RomaLastTranscriptionNotificationPresentation) {
        NotificationManager.shared.showNotification(
            title: presentation.title,
            type: presentation.kind
        )
    }
}

private extension Transcription {
    var lastTranscriptionCandidate: RomaLastTranscriptionCandidate<UUID> {
        RomaLastTranscriptionCandidate(
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

    static func resetForTesting() {
        pendingFallback = nil
    }

    static func consumeIfNeeded(for transcription: Transcription, modelContext: ModelContext) -> Bool {
        guard let pendingFallback else {
            return false
        }

        self.pendingFallback = nil

        guard RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
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
