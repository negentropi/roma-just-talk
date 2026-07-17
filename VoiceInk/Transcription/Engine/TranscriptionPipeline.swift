import Foundation
import SwiftData
import os
import VoiceInkCore

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionPipeline")

    var licenseViewModel: LicenseViewModel

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called as soon as paste is initiated to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        var finalPastedText: String?
        var promptDetectionResult: VoiceInkPromptDetectionResult?

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService {
                enhancementService.restorePromptDetectionSettings(result)
            }
        }

        func restorePromptDetectionSettingsAndDismiss(afterRestore: () -> Void = {}) async {
            await restorePromptDetectionSettingsIfNeeded()
            afterRestore()
            await onDismiss()
        }

        func finishCanceledTranscription() async {
            await onCancel()
            await restorePromptDetectionSettingsIfNeeded()

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let duration = await AudioFileMetadata.duration(for: audioURL)
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        do {
            let transcriptionStart = Date()
            let rawText: String
            if let session {
                rawText = try await session.transcribe(audioURL: audioURL)
            } else {
                rawText = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let textPlan = VoiceInkTranscriptionRunPreparation.prepareRawTextForEnhancement(
                rawText,
                cleanupConfiguration: cleanupConfiguration
            ) { text in
                DictionaryService.applyWordReplacements(to: text, using: modelContext)
            }
            let text = textPlan.textForEnhancement
            let cleanedText = textPlan.cleanedText
            if shouldCancel() { await finishCanceledTranscription(); return }

            transcription.text = cleanedText
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = cleanedText
            var enhancementResult: VoiceInkAIEnhancementResult?
            var enhancementFailureReason: String?

            if let enhancementService,
               enhancementService.isConfigured,
               enhancementService.hasPromptTriggerWords {
                let detectionResult = enhancementService.analyzePromptTrigger(in: text)
                promptDetectionResult = detectionResult
                enhancementService.applyPromptDetectionResult(detectionResult)
            }

            let enhancementRequest = textPlan.enhancementRequest(
                isEnhancementEnabled: enhancementService?.isEnhancementEnabled == true,
                isEnhancementConfigured: enhancementService?.isConfigured == true,
                promptDetectionResult: promptDetectionResult,
                skipConfiguration: VoiceInkPostProcessingSkipConfiguration.current()
            )

            if let enhancementService,
               let enhancementRequest {
                if shouldCancel() { await finishCanceledTranscription(); return }

                onStateChange(.enhancing)

                do {
                    let enhancement = try await enhancementService.enhance(enhancementRequest.text)
                    enhancementResult = enhancement
                    finalPastedText = enhancement.text
                } catch {
                    let errorDescription = VoiceInkErrorDescription.text(for: error)
                    enhancementFailureReason = errorDescription
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                                reason: errorDescription
                            ),
                            type: .warning
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return }
                }
            }

            let completedDraft = VoiceInkCompletedTranscriptionDraft(
                cleanedText: cleanedText,
                duration: transcription.duration,
                audioFileURL: transcription.audioFileURL,
                transcriptionModelName: model.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeName: transcription.powerModeName,
                powerModeEmoji: transcription.powerModeEmoji,
                enhancementResult: enhancementResult,
                enhancementFailureReason: enhancementFailureReason,
                enhancementFailurePolicy: .storeFailureText
            )
            transcription.applyCompletedDraft(completedDraft)
        } catch {
            let errorDescription = VoiceInkErrorDescription.text(for: error)

            if let nativeAppleError = error as? VoiceInkNativeAppleTranscriptionFailureKind,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.markAsFailedTranscription(reason: errorDescription)
        }

        func saveTranscriptionAndPostCompletion() {
            let shouldRecordSessionMetric = transcription.transcriptionState == .completed
            let didInsertSessionMetric: Bool
            if shouldRecordSessionMetric {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                    didInsertSessionMetric = false
                }
            } else {
                didInsertSessionMetric = false
            }

            var didSaveTranscription = false
            do {
                try modelContext.save()
                didSaveTranscription = true
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
            }

        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        if SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(for: transcription, modelContext: modelContext) {
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss()
        } else if var textToPaste = finalPastedText,
           transcription.transcriptionState == .completed {
            textToPaste = CursorPaster.preparedTextForPaste(textToPaste)

            let isTrialExpired: Bool
            if case .trialExpired = licenseViewModel.licenseState {
                isTrialExpired = true
            } else {
                isTrialExpired = false
            }
            let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
                textToPaste,
                appendTrailingSpace: VoiceInkAppendTrailingSpacePreference.isEnabled(),
                isTrialExpired: isTrialExpired
            )
            _ = await CursorPaster.startPasteAtCursor(pastedText).value
            let autoSendKey = PowerModeManager.shared.activeConfiguration?.autoSendKey
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey,
                   let delayAfterPaste = VoiceInkAutoSendPolicy.delayAfterPasteNanoseconds(for: autoSendKey) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: delayAfterPaste)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
        } else {
            await restorePromptDetectionSettingsAndDismiss()
        }

        if transcription.transcriptionState == .completed,
           transcription.duration <= 0 {
            transcription.duration = await AudioFileMetadata.duration(for: audioURL)
        }

        saveTranscriptionAndPostCompletion()
    }
}
