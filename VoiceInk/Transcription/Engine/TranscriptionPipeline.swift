import Foundation
import SwiftData
import os
import VoiceInkCore

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionPipeline")

    var licenseViewModel: LicenseViewModel

    #if DEBUG
    var cursorContextPreparedForTesting: (() async -> Void)?
    var pasteAuthorizationPreparedForTesting: (() async -> Void)?
    var autoSendDelayStartedForTesting: (() -> Void)?
    #endif

    init(
        modelContext: ModelContext,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - modelDisplayName: The recognition model name stored with the transcription.
    ///   - recognize: Produces text from the captured input.
    ///   - captureDuration: Reads the capture duration when the record has none.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - cancellation: Returns the pending cancellation, if any.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called as soon as paste is initiated to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        modelDisplayName: String,
        recognize: () async throws -> String,
        captureDuration: () async -> TimeInterval,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        cancellation: () -> RecordingCancellation?,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "pipeline.enter",
            details: "model=\(modelDisplayName)",
            token: traceToken
        )
        var finalPastedText: String?
        var promptDetectionResult: VoiceInkPromptDetectionResult?

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService {
                enhancementService.restorePromptDetectionSettings(result)
            }
        }

        func restorePromptDetectionSettingsAndDismiss() async {
            await restorePromptDetectionSettingsIfNeeded()
            await onDismiss()
        }

        func finishCanceledTranscription(_ cancellation: RecordingCancellation) async {
            await onCancel()
            await restorePromptDetectionSettingsIfNeeded()

            if cancellation == .accidentalShortcut {
                discard(transcription)
                latencyTrace.finish(event: "pipeline.cancelled", details: "model=\(modelDisplayName) discarded=true", token: traceToken)
                return
            }

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let duration = await captureDuration()
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? modelDisplayName
            )

            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
            latencyTrace.finish(
                event: "pipeline.cancelled",
                details: "model=\(modelDisplayName)",
                token: traceToken
            )
        }

        if let cancellation = cancellation() {
            await finishCanceledTranscription(cancellation)
            return
        }

        let cursorContextCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.cursor_context_prefetch",
            token: traceToken
        )
        let preparedCursorTextContext = Task { @MainActor in
            latencyTrace.executorResumed(cursorContextCheckpoint)
            let span = latencyTrace.begin(
                "pipeline.cursor_context_prefetch",
                token: traceToken
            )
            let context = CursorTextContextReader.prepareTextBeforeCursor()
            if VoiceInkPasteMethod.current() == .standard {
                CursorTextContextReader.prepareCommandVMenuItem(
                    for: context,
                    latencyTraceToken: traceToken
                )
            }
            latencyTrace.end(
                span,
                details: "available=\(context != nil)"
            )
            #if DEBUG
            if let cursorContextPreparedForTesting = self.cursorContextPreparedForTesting {
                await cursorContextPreparedForTesting()
            }
            #endif
            return context
        }
        defer { preparedCursorTextContext.cancel() }
        let pasteAuthorizationCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.paste_authorization_preflight",
            token: traceToken
        )
        let pasteAuthorizationPreflight = Task { @MainActor in
            latencyTrace.executorResumed(pasteAuthorizationCheckpoint)
            let span = latencyTrace.begin(
                "pipeline.paste_authorization_preflight",
                token: traceToken
            )
            let isTrusted = CursorPaster.preflightPasteAuthorization()
            latencyTrace.end(span, details: "trusted=\(isTrusted)")
            #if DEBUG
            if let pasteAuthorizationPreparedForTesting = self.pasteAuthorizationPreparedForTesting {
                await pasteAuthorizationPreparedForTesting()
            }
            #endif
        }

        do {
            let transcriptionStart = Date()
            let rawText: String
            let transcriptionSpan = latencyTrace.begin("pipeline.transcribe", token: traceToken)
            do {
                rawText = try await recognize()
                latencyTrace.end(
                    transcriptionSpan,
                    details: "result=success rawChars=\(rawText.count)"
                )
            } catch {
                latencyTrace.end(
                    transcriptionSpan,
                    details: "result=failure error=\(String(describing: type(of: error)))"
                )
                throw error
            }
            let cleanupSpan = latencyTrace.begin("pipeline.cleanup", token: traceToken)
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
            latencyTrace.end(
                cleanupSpan,
                details: "cleanedChars=\(cleanedText.count) enhancementInputChars=\(text.count)"
            )
            if let cancellation = cancellation() { await finishCanceledTranscription(cancellation); return }

            transcription.text = cleanedText
            transcription.transcriptionModelName = modelDisplayName
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
                if let cancellation = cancellation() { await finishCanceledTranscription(cancellation); return }

                onStateChange(.enhancing)

                let enhancementSpan = latencyTrace.begin("pipeline.enhancement", token: traceToken)
                do {
                    let enhancement = try await enhancementService.enhance(enhancementRequest.text)
                    latencyTrace.end(
                        enhancementSpan,
                        details: "result=success chars=\(enhancement.text.count)"
                    )
                    enhancementResult = enhancement
                    finalPastedText = enhancement.text
                } catch {
                    latencyTrace.end(
                        enhancementSpan,
                        details: "result=failure error=\(String(describing: type(of: error)))"
                    )
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
                    if let cancellation = cancellation() { await finishCanceledTranscription(cancellation); return }
                }
            }

            let completedDraft = VoiceInkCompletedTranscriptionDraft(
                cleanedText: cleanedText,
                duration: transcription.duration,
                audioFileURL: transcription.audioFileURL,
                transcriptionModelName: modelDisplayName,
                transcriptionDuration: transcriptionDuration,
                powerModeName: transcription.powerModeName,
                powerModeEmoji: transcription.powerModeEmoji,
                enhancementResult: enhancementResult,
                enhancementFailureReason: enhancementFailureReason,
                enhancementFailurePolicy: .storeFailureText
            )
            transcription.applyCompletedDraft(completedDraft)
        } catch {
            latencyTrace.event(
                "pipeline.transcription_failed",
                details: "error=\(String(describing: type(of: error)))",
                token: traceToken
            )
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
                        modelDisplayName: modelDisplayName,
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

        if let cancellation = cancellation() {
            await finishCanceledTranscription(cancellation)
            return
        }

        let pasteDecision = VoiceInkTranscriptionPasteOutputPolicy.decision(
            text: finalPastedText,
            transcriptionCompleted: transcription.transcriptionState == .completed
        )
        if SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(for: transcription, modelContext: modelContext) {
            latencyTrace.event("pipeline.empty_transcription_fallback", token: traceToken)
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss()
        } else if var textToPaste = pasteDecision.textToPaste {
            let pastePreparationSpan = latencyTrace.begin("pipeline.paste_prepare", token: traceToken)
            textToPaste = await CursorPaster.preparedTextForPaste(
                textToPaste,
                preparedCursorTextContext: preparedCursorTextContext
            )
            if let cancellation = cancellation() {
                latencyTrace.end(pastePreparationSpan, details: "result=cancelled")
                await finishCanceledTranscription(cancellation)
                return
            }

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
            latencyTrace.end(pastePreparationSpan, details: "chars=\(pastedText.count)")
            let pasteSpan = latencyTrace.begin("pipeline.paste_command", token: traceToken)
            await pasteAuthorizationPreflight.value
            if let cancellation = cancellation() {
                latencyTrace.end(pasteSpan, details: "result=cancelled")
                await finishCanceledTranscription(cancellation)
                return
            }
            let pasteTask = CursorPaster.startPasteAtCursor(
                pastedText,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: traceToken
            )
            // Awaiting an unstructured task does not forward cancellation.
            let pasteResult = await withTaskCancellationHandler {
                await pasteTask.value
            } onCancel: {
                pasteTask.cancel()
            }
            latencyTrace.end(
                pasteSpan,
                details: "textDelivered=\(pasteResult.didDeliverText) result=\(String(describing: pasteResult))"
            )
            if !pasteResult.didDeliverText,
               let cancellation = cancellation() ?? (Task.isCancelled ? .userRequested : nil) {
                await finishCanceledTranscription(cancellation)
                return
            }
            let autoSendKey = PowerModeManager.shared.activeConfiguration?.autoSendKey
            let stopSoundSpan = latencyTrace.begin("pipeline.stop_sound", token: traceToken)
            SoundManager.shared.play(.stop)
            latencyTrace.end(stopSoundSpan)
            let dismissSpan = latencyTrace.begin("pipeline.dismiss_recorder", token: traceToken)
            await restorePromptDetectionSettingsAndDismiss()
            latencyTrace.end(dismissSpan)
            if pasteResult.didDeliverText,
               let autoSendKey,
               let delayAfterPaste = VoiceInkAutoSendPolicy.delayAfterPasteNanoseconds(for: autoSendKey) {
                #if DEBUG
                autoSendDelayStartedForTesting?()
                #endif
                do {
                    try await Task.sleep(nanoseconds: delayAfterPaste)
                    if !Task.isCancelled, cancellation() == nil {
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                } catch {
                    latencyTrace.event("pipeline.auto_send_cancelled", token: traceToken)
                }
            }
        } else {
            latencyTrace.event(
                "pipeline.no_paste",
                details: "state=\(transcription.transcriptionState) pasteableText=\(pasteDecision.textToPaste != nil)",
                token: traceToken
            )
            if pasteDecision.shouldPlayCompletionSoundWithoutPaste {
                SoundManager.shared.play(.stop)
            }
            await restorePromptDetectionSettingsAndDismiss()
        }

        if VoiceInkEmptyTranscriptionPolicy.isEmptyCompletion(
            status: transcription.transcriptionState,
            rawText: transcription.text,
            enhancedText: transcription.enhancedText
        ) {
            discard(transcription)
            latencyTrace.finish(event: "pipeline.empty_discarded", token: traceToken)
            return
        }

        if transcription.transcriptionState == .completed,
           transcription.duration <= 0 {
            let durationSpan = latencyTrace.begin("pipeline.capture_duration", token: traceToken)
            transcription.duration = await captureDuration()
            latencyTrace.end(durationSpan)
        }

        let saveSpan = latencyTrace.begin("pipeline.save", token: traceToken)
        saveTranscriptionAndPostCompletion()
        latencyTrace.end(saveSpan)
        latencyTrace.finish(
            event: "pipeline.complete",
            details: "state=\(transcription.transcriptionState) finalChars=\(finalPastedText?.count ?? 0)",
            token: traceToken
        )
    }

    /// Treats the recording as if it never happened: no History row, no audio, no metrics.
    private func discard(_ transcription: Transcription) {
        let audioFileURL = transcription.audioFileURL
        modelContext.delete(transcription)
        do {
            try modelContext.save()
        } catch {
            // Keep the audio so a surviving row never points at a missing file.
            logger.error("Failed to discard transcription: \(error.localizedDescription, privacy: .public)")
            return
        }
        VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(for: audioFileURL) { message in
            logger.error("\(message, privacy: .public)")
        }
        NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
    }
}
