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
                transcription.id != excludedID && isPasteable(transcription)
            }
        } catch {
            print("Error fetching last transcription: \(error)")
            return nil
        }
    }

    private static func isPasteable(_ transcription: Transcription) -> Bool {
        VoiceInkTranscriptPresentation.isPasteable(
            rawText: transcription.text,
            statusRawValue: transcription.transcriptionStatus,
            canceledText: Transcription.canceledTranscriptionText
        )
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
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
                    title: "Last transcription copied",
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: "Failed to copy transcription",
                    type: .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext, excluding excludedID: UUID? = nil) {
        guard let lastTranscription = getLastTranscription(from: modelContext, excluding: excludedID) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
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
                    title: "No transcription available",
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
        guard !UserDefaults.standard.bool(forKey: "LowercaseTranscription") else {
            return text
        }

        guard ContextualCapitalizationFormatter.needsCursorContext(text) else {
            return text
        }

        return ContextualCapitalizationFormatter.format(
            text,
            beforeCursor: CursorTextContextReader.textBeforeCursor()
        )
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(
                    title: "Cannot retry: Audio file not found",
                    type: .error
                )
                return
            }

            guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: "No transcription model selected",
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
                    title: "Copied to clipboard",
                    type: .success
                )
            } catch {
                NotificationManager.shared.showNotification(
                    title: "Retry failed: \(error.localizedDescription)",
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
    private static let emptyTapThreshold: TimeInterval = 0.32
    private static let fallbackLifetime: TimeInterval = 30

    static func shouldFallback(pressDuration: TimeInterval) -> Bool {
        pressDuration < emptyTapThreshold
    }

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

        guard Date().timeIntervalSince(pendingFallback.createdAt) <= fallbackLifetime,
              transcription.transcriptionState == .completed,
              transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              transcription.enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        else {
            return false
        }

        LastTranscriptionService.pasteLastTranscription(from: modelContext, excluding: transcription.id)
        return true
    }
}
