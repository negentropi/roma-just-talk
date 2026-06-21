import Foundation
import SwiftData
import VoiceInkCore

class LastTranscriptionService: ObservableObject {
    
    static func getLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            return transcriptions.first { transcription in
                transcription.id != excludedID && VoiceInkTranscriptPresentation.isPasteable(
                    rawText: transcription.text,
                    statusRawValue: transcription.transcriptionStatus
                )
            }
        } catch {
            print("Error fetching last transcription: \(error)")
            return nil
        }
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.noTranscriptionAvailableTitle,
                    type: .error
                )
            }
            return
        }
        
        let textToCopy = VoiceInkTranscriptPresentation.preferredText(
            rawText: lastTranscription.text,
            enhancedText: lastTranscription.enhancedText
        ) ?? lastTranscription.text
        
        let success = ClipboardManager.copyToClipboard(textToCopy)
        
        Task { @MainActor in
            if success {
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.lastTranscriptionCopiedTitle,
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.failedToCopyTranscriptionTitle,
                    type: .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) {
        guard let lastTranscription = getLastTranscription(from: modelContext, excluding: excludedID) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.noTranscriptionAvailableTitle,
                    type: .error
                )
            }
            return
        }
        
        let textToPaste = lastTranscription.text

        Task { @MainActor in
            CursorPaster.pasteAtCursor(textForCursorPaste(textToPaste))
        }
    }
    
    static func pasteLastEnhancement(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.noTranscriptionAvailableTitle,
                    type: .error
                )
            }
            return
        }
        
        let textToPaste = VoiceInkTranscriptPresentation.preferredText(
            rawText: lastTranscription.text,
            enhancedText: lastTranscription.enhancedText
        ) ?? lastTranscription.text

        Task { @MainActor in
            CursorPaster.pasteAtCursor(textForCursorPaste(textToPaste))
        }
    }

    @MainActor
    private static func textForCursorPaste(_ text: String) -> String {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            text,
            shouldLowercase: VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase()
        )
        return plan.text(
            beforeCursor: plan.shouldReadCursorContext ? CursorTextContextReader.textBeforeCursor() : nil
        )
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURL = lastTranscription.existingAudioFileURL() else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.cannotRetryTitle(
                        errorDescription: VoiceInkErrorDescription.text(for: VoiceInkEngineError.audioFileNotFound)
                    ),
                    type: .error
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkErrorDescription.text(for: VoiceInkEngineError.noTranscriptionModelSelected),
                    type: .error
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

                let textToCopy = VoiceInkTranscriptPresentation.preferredText(
                    rawText: newTranscription.text,
                    enhancedText: newTranscription.enhancedText
                ) ?? newTranscription.text
                ClipboardManager.copyToClipboard(textToCopy)

                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.copiedToClipboardTitle,
                    type: .success
                )
            } catch {
                let errorDescription = VoiceInkErrorDescription.text(for: error)
                NotificationManager.shared.showNotification(
                    title: VoiceInkTranscriptPresentation.retryFailedTitle(errorDescription: errorDescription),
                    type: .error
                )
            }
        }
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
