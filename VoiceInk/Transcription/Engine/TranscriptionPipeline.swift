import Foundation
import SwiftData
import os
import VoiceInkCore

typealias TranscriptionPipelineDeferredWork = @MainActor () -> Void

struct TranscriptionLatencyTrace: Sendable {
    static let rollingPreloadQuickReleaseOperation = "rolling-preload-quick-release"

    let operation: String
    let startedAt: Date

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    var isRollingPreloadQuickRelease: Bool {
        operation == Self.rollingPreloadQuickReleaseOperation
    }
}

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")
    private static let autoSendAfterPasteDelayNanoseconds: UInt64 = 120_000_000

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
    ///   - deferHistoryInsertUntilSave: Inserts the history record only at the final save boundary.
    ///   - powerModeApplyTask: Applies active-window Power Mode config before paste while STT can run first.
    ///   - preparedCursorTextContext: Pre-read cursor text context for quick-release paste capitalization.
    ///   - preparedPasteContext: Pre-read clipboard context for quick-release clipboard restore.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void,
        audioFileReadyTask: Task<Void, Error>? = nil,
        latencyTrace: TranscriptionLatencyTrace? = nil,
        deferHistoryInsertUntilSave: Bool = false,
        powerModeApplyTask: Task<Void, Never>? = nil,
        preparedCursorTextContext: Task<String?, Never>? = nil,
        preparedPasteContext: Task<CursorPaster.PreparedPasteContext?, Never>? = nil
    ) async -> TranscriptionPipelineDeferredWork? {
        var finalPastedText: String?
        var promptDetectionResult: VoiceInkPromptDetectionResult?
        var didResolveAudioFileReadiness = false
        var audioFileIsReady = audioFileReadyTask == nil
        var shouldInsertHistoryRecordBeforeSave = deferHistoryInsertUntilSave
        var didResolvePowerModeApply = false

        if let latencyTrace {
            logger.notice("Latency trace pipeline started operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
        }

        func insertHistoryRecordBeforeSaveIfNeeded() {
            guard shouldInsertHistoryRecordBeforeSave else { return }
            modelContext.insert(transcription)
            shouldInsertHistoryRecordBeforeSave = false
        }

        func waitForAudioFileReadyIfNeeded() async -> Bool {
            guard !didResolveAudioFileReadiness else {
                return audioFileIsReady
            }

            didResolveAudioFileReadiness = true
            guard let audioFileReadyTask else {
                audioFileIsReady = true
                return true
            }

            let waitStart = Date()
            do {
                try await audioFileReadyTask.value
                audioFileIsReady = true
                logger.notice("Deferred audio file ready elapsed=\(Date().timeIntervalSince(waitStart), format: .fixed(precision: 3), privacy: .public)s")
                if let latencyTrace {
                    logger.notice("Latency trace audio file ready operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
                }
            } catch {
                audioFileIsReady = false
                transcription.audioFileURL = nil
                logger.error("Deferred audio file write failed: \(error.localizedDescription, privacy: .public)")
            }

            return audioFileIsReady
        }

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService {
                enhancementService.restorePromptDetectionSettings(result)
            }
        }

        func waitForPowerModeApplyIfNeeded() async {
            guard !didResolvePowerModeApply else { return }
            didResolvePowerModeApply = true
            guard let powerModeApplyTask else { return }

            let waitStart = Date()
            if let latencyTrace {
                logger.notice("Latency trace waiting for active-window config operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            }
            await powerModeApplyTask.value
            logger.notice("Power Mode active-window config ready elapsed=\(Date().timeIntervalSince(waitStart), format: .fixed(precision: 3), privacy: .public)s")
            if let latencyTrace {
                logger.notice("Latency trace active-window config ready operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
                recordRollingPreloadTiming(latencyTrace, stage: .activeWindowReady)
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
                let audioFileReady = await waitForAudioFileReadyIfNeeded()
                let duration = audioFileReady ? await AudioFileMetadata.duration(for: audioURL) : 0
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                insertHistoryRecordBeforeSaveIfNeeded()
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return nil
        }

        do {
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()
            text = cleanupConfiguration.filterRawOutput(text)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            if let latencyTrace {
                logger.notice("Latency trace transcription ready operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s transcriptionElapsed=\(transcriptionDuration, format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
                recordRollingPreloadTiming(latencyTrace, stage: .transcriptionReady)
            }

            if shouldCancel() { await finishCanceledTranscription(); return nil }

            let preparedRunText = VoiceInkTranscriptionRunPreparation.prepareFilteredText(
                text,
                cleanupConfiguration: cleanupConfiguration
            ) { text in
                WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            }
            text = preparedRunText.wordReplacedText
            let cleanedText = preparedRunText.cleanedText

            transcription.text = cleanedText
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = cleanedText

            if let enhancementService,
               enhancementService.isConfigured,
               enhancementService.hasPromptTriggerWords {
                let detectionResult = enhancementService.analyzePromptTrigger(in: text)
                promptDetectionResult = detectionResult
                enhancementService.applyPromptDetectionResult(detectionResult)
            }

            let shouldSkipEnhancement = preparedRunText.shouldSkipPostProcessing(
                configuration: VoiceInkPostProcessingSkipConfiguration.current(),
                promptTriggerForcesPostProcessing: promptDetectionResult?.shouldEnableAI == true,
                transcriptRole: .wordReplacedText
            )

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await finishCanceledTranscription(); return nil }

                onStateChange(.enhancing)
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let enhancement = try await enhancementService.enhance(textForAI)
                    transcription.enhancedText = enhancement.text
                    transcription.aiEnhancementModelName = enhancement.modelName
                    transcription.promptName = enhancement.promptName
                    transcription.enhancementDuration = enhancement.duration
                    transcription.aiRequestSystemMessage = enhancement.requestSystemMessage
                    transcription.aiRequestUserMessage = enhancement.requestUserMessage
                    finalPastedText = enhancement.text
                } catch {
                    let errorDescription = VoiceInkErrorDescription.text(for: error)
                    transcription.enhancedText = VoiceInkPostProcessingFailurePresentation.enhancementFailureText(
                        reason: errorDescription
                    )
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                                reason: errorDescription
                            ),
                            type: .warning
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return nil }
                }
            }

            transcription.transcriptionState = .completed
        } catch {
            let errorDescription = VoiceInkErrorDescription.text(for: error)

            if let nativeAppleError = error as? NativeAppleTranscriptionService.ServiceError,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.text = VoiceInkTranscriptPresentation.failedTranscriptText(reason: errorDescription)
            transcription.transcriptionState = .failed
        }

        func recordSessionMetricAndNotifyIfNeeded(modelDisplayName: String?) {
            do {
                let didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                    transcription: transcription,
                    modelDisplayName: modelDisplayName,
                    in: modelContext
                )
                guard didInsertSessionMetric else { return }

                try modelContext.save()
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            } catch {
                logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
            }
        }

        func saveTranscriptionAndPostCompletion() {
            insertHistoryRecordBeforeSaveIfNeeded()

            let shouldRecordSessionMetric = transcription.transcriptionState == .completed
            let shouldDeferSessionMetric = shouldRecordSessionMetric && latencyTrace?.isRollingPreloadQuickRelease == true
            let didInsertSessionMetric: Bool
            if shouldRecordSessionMetric, !shouldDeferSessionMetric {
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

            if shouldDeferSessionMetric, didSaveTranscription {
                let modelDisplayName = model.displayName
                Task { @MainActor in
                    recordSessionMetricAndNotifyIfNeeded(modelDisplayName: modelDisplayName)
                }
            }
        }

        func deferredSaveTranscriptionAndPostCompletion() -> TranscriptionPipelineDeferredWork? {
            guard latencyTrace?.isRollingPreloadQuickRelease == true else {
                saveTranscriptionAndPostCompletion()
                if let latencyTrace {
                    logger.notice("Latency trace pipeline saved operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
                    recordRollingPreloadTiming(latencyTrace, stage: .saved)
                }
                return nil
            }

            let trace = latencyTrace
            return {
                saveTranscriptionAndPostCompletion()
                if let trace {
                    self.logger.notice("Latency trace deferred pipeline saved operation=\(trace.operation, privacy: .public) elapsed=\(trace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
                    self.recordRollingPreloadTiming(trace, stage: .saved)
                }
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return nil
        }

        await waitForPowerModeApplyIfNeeded()

        if SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(for: transcription, modelContext: modelContext) {
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss()
        } else if var textToPaste = finalPastedText,
           transcription.transcriptionState == .completed {
            let shouldLowercase = VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase()
            if !shouldLowercase,
               VoiceInkContextualCapitalizationFormatter.needsCursorContext(textToPaste) {
                let beforeCursor = if let preparedCursorTextContext {
                    await preparedCursorTextContext.value
                } else {
                    CursorTextContextReader.textBeforeCursor()
                }
                textToPaste = VoiceInkContextualCapitalizationFormatter.format(
                    textToPaste,
                    beforeCursor: beforeCursor
                )
            }

            if case .trialExpired = licenseViewModel.licenseState {
                textToPaste = """
                    Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                    \n\(textToPaste)
                    """
            }

            let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
            let pastedText = textToPaste + (appendSpace ? " " : "")
            if let latencyTrace {
                logger.notice("Latency trace paste starting operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s chars=\(pastedText.count, privacy: .public)")
                recordRollingPreloadTiming(latencyTrace, stage: .pasteStarting)
            }
            let pasteContext: CursorPaster.PreparedPasteContext? = if let preparedPasteContext {
                await preparedPasteContext.value
            } else {
                nil
            }
            _ = await CursorPaster.startPasteAtCursor(pastedText, preparedContext: pasteContext).value
            if let latencyTrace {
                logger.notice("Latency trace paste completed operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s chars=\(pastedText.count, privacy: .public)")
                recordRollingPreloadTiming(latencyTrace, stage: .pasteCompleted)
            }
            let autoSendKey = PowerModeManager.shared.currentActiveConfiguration?.autoSendKey
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: Self.autoSendAfterPasteDelayNanoseconds)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
        } else {
            await restorePromptDetectionSettingsAndDismiss()
        }

        if transcription.transcriptionState == .completed,
           transcription.duration <= 0 {
            let audioFileReady = await waitForAudioFileReadyIfNeeded()
            if audioFileReady {
                transcription.duration = await AudioFileMetadata.duration(for: audioURL)
            }
        }

        return deferredSaveTranscriptionAndPostCompletion()
    }

    private func recordRollingPreloadTiming(
        _ latencyTrace: TranscriptionLatencyTrace,
        stage: RollingBufferQuickReleaseTimingStage
    ) {
        guard latencyTrace.isRollingPreloadQuickRelease else { return }
        RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseTiming(
            stage: stage,
            elapsedSeconds: latencyTrace.elapsed
        )
    }
}
