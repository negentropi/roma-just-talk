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
    private var activePasteTasks: [UUID: Task<CursorPaster.PasteResult, Never>] = [:]
    private var activeProcessingTasks: [UUID: Task<DictationPostprocessingPlan.Output?, Error>] = [:]
    private var activeWritingTasks: [UUID: Task<VoiceInkAIEnhancementResult, Error>] = [:]
    private var activeOperationCancellations: [UUID: Bool] = [:]
    private let reportProcessingFailure: @MainActor (String) -> Void
    private let reportWritingSaveFailure: @MainActor (String) -> Void
    private let autoSend: @MainActor (VoiceInkAutoSendKey) -> Void
    let writingActionUndoController: WritingActionUndoController

    var hasActiveOperations: Bool { !activeOperationCancellations.isEmpty }

    var licenseViewModel: LicenseViewModel

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?,
        writingActionUndoController: WritingActionUndoController? = nil,
        reportProcessingFailure: @escaping @MainActor (String) -> Void = {
            NotificationManager.shared.showNotification(title: $0, type: .warning, duration: 6)
        },
        reportWritingSaveFailure: @escaping @MainActor (String) -> Void = {
            NotificationManager.shared.showNotification(title: $0, type: .error, duration: 6)
        },
        autoSend: @escaping @MainActor (VoiceInkAutoSendKey) -> Void = {
            CursorPaster.performAutoSend($0)
        }
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
        self.writingActionUndoController = writingActionUndoController ?? WritingActionUndoController()
        self.reportProcessingFailure = reportProcessingFailure
        self.reportWritingSaveFailure = reportWritingSaveFailure
        self.autoSend = autoSend
        self.licenseViewModel = LicenseViewModel()
    }

    func cancelDelivery(for transcriptionID: UUID) {
        if activeOperationCancellations[transcriptionID] != nil {
            activeOperationCancellations[transcriptionID] = true
        }
        activeProcessingTasks[transcriptionID]?.cancel()
        activeWritingTasks[transcriptionID]?.cancel()
        activePasteTasks[transcriptionID]?.cancel()
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
        writingSession: WritingActionSession? = nil,
        spokenSnippets: [VoiceInkSpokenSnippet]? = nil,
        cleanupProfile: VoiceInkDictationProfile = .current(),
        dictationPlan: DictationPostprocessingPlan? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        shouldCancel: @escaping () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        activeOperationCancellations[transcription.id] = false
        defer {
            activeOperationCancellations[transcription.id] = nil
            activeProcessingTasks[transcription.id] = nil
            activeWritingTasks[transcription.id] = nil
        }
        let deliveryID = writingActionUndoController.beginDelivery(transcriptionID: transcription.id)
        let capturedProfile = writingSession == nil ? (dictationPlan?.profile ?? cleanupProfile) : .custom
        if writingSession == nil, capturedProfile != .custom { SpecialShortcutEmptyTranscriptionFallback.clear() }
        let alreadyCanceled = Task.isCancelled || shouldCancel()
        let plan: DictationPostprocessingPlan = writingSession == nil && !alreadyCanceled
            ? (dictationPlan ?? .capture(profile: capturedProfile, using: modelContext, enhancementService: enhancementService))
            : .custom
        let customSnippets = writingSession == nil && capturedProfile == .custom && !alreadyCanceled
            ? (spokenSnippets ?? VoiceInkSpokenSnippets.load()) : []
        let parentCancellation = OSAllocatedUnfairLock(initialState: false)
        await withTaskCancellationHandler {
            await runOperation(
                transcription: transcription, audioURL: audioURL, model: model, session: session,
                writingSession: writingSession, capturedProfile: capturedProfile,
                plan: plan, customSnippets: customSnippets, deliveryID: deliveryID,
                latencyTraceToken: latencyTraceToken, onStateChange: onStateChange,
                shouldCancel: shouldCancel, onCancel: onCancel, onDismiss: onDismiss,
                parentCancellation: parentCancellation
            )
        } onCancel: {
            parentCancellation.withLock { $0 = true }
        }
    }

    private func runOperation(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        writingSession: WritingActionSession?,
        capturedProfile: VoiceInkDictationProfile,
        plan: DictationPostprocessingPlan,
        customSnippets: [VoiceInkSpokenSnippet],
        deliveryID: WritingActionUndoController.DeliveryID,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        shouldCancel: @escaping () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void,
        parentCancellation: OSAllocatedUnfairLock<Bool>
    ) async {
        func isCanceled() -> Bool {
            parentCancellation.withLock { $0 } || shouldCancel() || Task.isCancelled
                || activeOperationCancellations[transcription.id] == true
        }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "pipeline.enter",
            details: "model=\(model.displayName) hasStreamingSession=\(session != nil)",
            token: traceToken
        )
        var finalPastedText: String?
        var literalOutput: String?
        var promptDetectionResult: VoiceInkPromptDetectionResult?
        var processingFailureReason: String?
        var didDeliverOrdinaryText = false
        var writingDeliveryWasAttempted = false
        var writingDeliveryWasConfirmed = false
        var deliveryOutcome: WritingTarget.DeliveryOutcome = .notAttempted(CancellationError())
        var pipelineFinished = false
        var suppressAutoSend = false
        defer {
            suppressAutoSend = isCanceled()
            pipelineFinished = true
            writingActionUndoController.finishDelivery(deliveryOutcome, for: deliveryID)
        }

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
                let durationResult = await AudioFileMetadata.tracedDuration(
                    for: audioURL,
                    executorName: "pipeline.cancel_audio_duration",
                    latencyTraceToken: traceToken
                )
                latencyTrace.executorResumed(durationResult.executorCheckpoint)
                canceledDuration = durationResult.seconds > 0 ? durationResult.seconds : nil
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
            latencyTrace.finish(
                event: "pipeline.cancelled",
                details: "model=\(model.displayName)",
                token: traceToken
            )
        }

        if isCanceled() {
            await finishCanceledTranscription()
            return
        }
        let cursorContextCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.cursor_context_prefetch",
            token: traceToken
        )
        let preparedCursorTextContext = Task { @MainActor in
            guard writingSession == nil else { return nil as CursorTextContextReader.PreparedContext? }
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
            return context
        }
        defer { preparedCursorTextContext.cancel() }
        let pasteAuthorizationCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.paste_authorization_preflight",
            token: traceToken
        )
        let pasteAuthorizationPreflight = Task { @MainActor in
            guard writingSession == nil else { return }
            latencyTrace.executorResumed(pasteAuthorizationCheckpoint)
            let span = latencyTrace.begin(
                "pipeline.paste_authorization_preflight",
                token: traceToken
            )
            let isTrusted = CursorPaster.preflightPasteAuthorization()
            latencyTrace.end(span, details: "trusted=\(isTrusted)")
        }

        do {
            let transcriptionStart = Date()
            let rawText: String
            let transcriptionSpan = latencyTrace.begin("pipeline.transcribe", token: traceToken)
            do {
                if let session {
                    rawText = try await session.transcribe(audioURL: audioURL)
                } else {
                    rawText = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
                }
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
            if isCanceled() {
                await finishCanceledTranscription()
                return
            }
            if let writingSession {
                transcription.text = rawText
                transcription.transcriptionModelName = model.displayName
                transcription.transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
                transcription.promptName = writingSession.kind.title
                onStateChange(.enhancing)
                do {
                    guard let enhancementService else { throw VoiceInkAIEnhancementError.notConfigured }
                    let request = try writingSession.request(transcript: rawText)
                    _ = try await VoiceInkWritingActionExecution.run(
                        request: request,
                        shouldCancel: isCanceled,
                        perform: { request in
                            let requestTask = Task { @MainActor in
                                try Task.checkCancellation()
                                return try await enhancementService.performWritingAction(request, using: writingSession.provider)
                            }
                            self.activeWritingTasks[transcription.id] = requestTask
                            defer { self.activeWritingTasks[transcription.id] = nil }
                            let result = try await withTaskCancellationHandler {
                                try await requestTask.value
                            } onCancel: {
                                requestTask.cancel()
                            }
                            // Preserve generated text even when the captured destination changed.
                            transcription.enhancedText = result.text
                            transcription.aiEnhancementModelName = result.modelName
                            transcription.promptName = result.promptName
                            transcription.enhancementDuration = result.duration
                            transcription.aiRequestSystemMessage = result.requestSystemMessage
                            transcription.aiRequestUserMessage = result.requestUserMessage
                            return result
                        },
                        deliver: { text in
                            let outcome = await writingSession.target.deliver(
                                with: text,
                                shouldCancel: { isCanceled() || !self.writingActionUndoController.isCurrentDelivery(deliveryID) },
                                willAttempt: {
                                    if isCanceled() { throw CancellationError() }
                                    try self.writingActionUndoController.willAttemptDelivery(deliveryID)
                                    writingDeliveryWasAttempted = true
                                },
                                onConfirmed: { edit in
                                    // External delivery is committed before the caller can suspend or cancel.
                                    writingDeliveryWasConfirmed = true
                                    let undoEdit = writingSession.kind == .rewriteSelection ? edit : nil
                                    deliveryOutcome = .confirmed(undoEdit)
                                    self.writingActionUndoController.confirmedDelivery(undoEdit, for: deliveryID)
                                }
                            )
                            if !writingDeliveryWasConfirmed { deliveryOutcome = outcome }
                            if let failure = outcome.failure, !writingDeliveryWasConfirmed { throw failure }
                        }
                    )
                    transcription.transcriptionState = .completed
                } catch {
                    if !writingDeliveryWasAttempted, isCanceled() || error is CancellationError {
                        await finishCanceledTranscription()
                        return
                    }
                    transcription.transcriptionState = .failed
                    let advice = writingDeliveryWasAttempted
                        ? "Roma Just Talk couldn’t confirm whether the original field was changed. Check that field before making more changes. The recording and generated text are kept for History."
                        : "The recording and any generated text are kept for History."
                    reportProcessingFailure("\(error.localizedDescription) \(advice)")
                }
            } else if capturedProfile != .custom {
                if isCanceled() { await finishCanceledTranscription(); return }
                // Register before suspension so cancellation owns provider work as well as delivery.
                let processingTask = Task { @MainActor in
                    try Task.checkCancellation()
                    return try await plan.process(
                        recognitionText: rawText,
                        using: enhancementService,
                        shouldCancel: isCanceled,
                        willRequestClarity: { onStateChange(.enhancing) }
                    )
                }
                activeProcessingTasks[transcription.id] = processingTask
                let processed = try await withTaskCancellationHandler {
                    try await processingTask.value
                } onCancel: {
                    processingTask.cancel()
                }
                activeProcessingTasks[transcription.id] = nil
                if isCanceled() { await finishCanceledTranscription(); return }
                guard let processed else { preconditionFailure("A non-Custom plan must produce an outcome.") }
                literalOutput = processed.literalOutput
                finalPastedText = processed.literalOutput
                processingFailureReason = processed.fallbackReason
                transcription.applyCompletedDraft(VoiceInkCompletedTranscriptionDraft(
                    cleanedText: processed.preparedText,
                    duration: transcription.duration,
                    audioFileURL: transcription.audioFileURL,
                    transcriptionModelName: model.displayName,
                    transcriptionDuration: Date().timeIntervalSince(transcriptionStart),
                    powerModeName: transcription.powerModeName,
                    powerModeEmoji: transcription.powerModeEmoji,
                    enhancementResult: processed.enhancementResult,
                    recognitionText: processed.recognitionText,
                    dictationProfile: capturedProfile,
                    clarityStyle: plan.clarityStyle,
                    processingFailureReason: processed.fallbackReason
                ))
            } else {
                let snippetExpansion = VoiceInkSpokenSnippets.expansion(of: rawText, using: customSnippets)
                if snippetExpansion.didExpand {
                    // Snippet utterances stay literal so cleanup cannot rewrite saved content or its trigger.
                    literalOutput = snippetExpansion.text
                    finalPastedText = snippetExpansion.text
                    transcription.text = rawText
                    transcription.enhancedText = snippetExpansion.text
                    transcription.transcriptionModelName = model.displayName
                    transcription.transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
                    transcription.transcriptionState = .completed
                    transcription.recognitionText = rawText
                    transcription.dictationProfileRawValue = capturedProfile.rawValue
                    transcription.clarityStyleRawValue = nil
                    transcription.processingFailureReason = nil
                } else {
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
                    if isCanceled() { await finishCanceledTranscription(); return }

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
                        if isCanceled() { await finishCanceledTranscription(); return }

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
                            if isCanceled() { await finishCanceledTranscription(); return }
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
                        enhancementFailurePolicy: .storeFailureText,
                        recognitionText: rawText,
                        dictationProfile: capturedProfile
                    )
                    transcription.applyCompletedDraft(completedDraft)
                }
            }
        } catch {
            if !writingDeliveryWasAttempted, isCanceled() || error is CancellationError {
                await finishCanceledTranscription()
                return
            }
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

            if writingDeliveryWasAttempted {
                transcription.transcriptionState = writingDeliveryWasConfirmed ? .completed : .failed
                reportProcessingFailure("\(errorDescription) Roma Just Talk won’t try to change the original field again. Check that field before making more changes. The generated text is kept for History.")
            } else {
                transcription.markAsFailedTranscription(reason: errorDescription)
            }
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

            do {
                try modelContext.save()
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
                if writingDeliveryWasAttempted {
                    let delivery = writingDeliveryWasConfirmed
                        ? "The original field was updated, but History couldn’t be saved."
                        : "Roma Just Talk couldn’t confirm whether the original field was changed, and History couldn’t be saved. Check that field before making more changes."
                    reportWritingSaveFailure("\(delivery) \(error.localizedDescription)")
                }
            }

        }

        if isCanceled(), !writingDeliveryWasAttempted {
            await finishCanceledTranscription()
            return
        }

        let pasteDecision = VoiceInkTranscriptionPasteOutputPolicy.decision(
            text: finalPastedText,
            transcriptionCompleted: transcription.transcriptionState == .completed
        )
        if writingSession != nil {
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss()
        } else if capturedProfile == .custom,
                  SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(
            for: transcription,
            modelContext: modelContext,
            writingActionUndoController: writingActionUndoController
        ) {
            latencyTrace.event("pipeline.empty_transcription_fallback", token: traceToken)
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss()
        } else if var textToPaste = pasteDecision.textToPaste {
            let pastePreparationSpan = latencyTrace.begin("pipeline.paste_prepare", token: traceToken)
            if literalOutput == nil {
                textToPaste = await CursorPaster.preparedTextForPaste(
                    textToPaste,
                    preparedCursorTextContext: preparedCursorTextContext
                )
            }

            let isTrialExpired: Bool
            if case .trialExpired = licenseViewModel.licenseState {
                isTrialExpired = true
            } else {
                isTrialExpired = false
            }
            let pastedText = literalOutput ?? VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
                textToPaste,
                appendTrailingSpace: VoiceInkAppendTrailingSpacePreference.isEnabled(),
                isTrialExpired: isTrialExpired
            )
            latencyTrace.end(pastePreparationSpan, details: "chars=\(pastedText.count)")
            let pasteSpan = latencyTrace.begin("pipeline.paste_command", token: traceToken)
            await pasteAuthorizationPreflight.value
            if isCanceled() {
                latencyTrace.end(pasteSpan, details: "result=cancelled_before_post")
                await finishCanceledTranscription()
                return
            }
            var ordinaryMutationAuthorized = false
            let pasteTask = CursorPaster.startPasteAtCursor(
                pastedText,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: traceToken,
                willAttempt: {
                    if isCanceled() { throw CancellationError() }
                    guard self.writingActionUndoController.isCurrentDelivery(deliveryID) else { throw CancellationError() }
                    if !ordinaryMutationAuthorized {
                        try self.writingActionUndoController.willAttemptDelivery(deliveryID)
                        ordinaryMutationAuthorized = true
                    }
                }
            )
            activePasteTasks[transcription.id] = pasteTask
            let pasteResult = await withTaskCancellationHandler {
                await pasteTask.value
            } onCancel: {
                pasteTask.cancel()
            }
            activePasteTasks[transcription.id] = nil
            if ordinaryMutationAuthorized {
                deliveryOutcome = pasteResult == .textInserted ? .confirmed(nil)
                    : .attemptedUnconfirmed(WritingTarget.Failure.replacementUnconfirmed)
            }
            didDeliverOrdinaryText = pasteResult.didDeliverText
            latencyTrace.end(
                pasteSpan,
                details: "textDelivered=\(pasteResult.didDeliverText) result=\(String(describing: pasteResult))"
            )
            if pasteResult == .commandNotPosted,
               pasteTask.isCancelled || isCanceled() {
                await finishCanceledTranscription()
                return
            }
            let autoSendKey = PowerModeManager.shared.activeConfiguration?.autoSendKey
            let stopSoundSpan = latencyTrace.begin("pipeline.stop_sound", token: traceToken)
            SoundManager.shared.play(.stop)
            latencyTrace.end(stopSoundSpan)
            let dismissSpan = latencyTrace.begin("pipeline.dismiss_recorder", token: traceToken)
            await restorePromptDetectionSettingsAndDismiss {
                if pasteResult.didDeliverText,
                   !pasteTask.isCancelled,
                   !Task.isCancelled,
                   !isCanceled(),
                   let autoSendKey,
                   let delayAfterPaste = VoiceInkAutoSendPolicy.delayAfterPasteNanoseconds(for: autoSendKey) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: delayAfterPaste)
                        // Normal engine cleanup ends run ownership; it is not a delayed user cancellation.
                        guard !Task.isCancelled, !(pipelineFinished ? suppressAutoSend : isCanceled()),
                              self.writingActionUndoController.isLatestDelivery(deliveryID) else { return }
                        self.autoSend(autoSendKey)
                    }
                }
            }
            latencyTrace.end(dismissSpan)
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

        if isCanceled(), writingSession == nil ? !didDeliverOrdinaryText : !writingDeliveryWasAttempted {
            await finishCanceledTranscription()
            return
        }

        if transcription.transcriptionState == .completed || writingSession != nil,
           transcription.duration <= 0 {
            let durationSpan = latencyTrace.begin("pipeline.audio_duration", token: traceToken)
            let durationResult = await AudioFileMetadata.tracedDuration(
                for: audioURL,
                executorName: "pipeline.audio_duration",
                latencyTraceToken: traceToken
            )
            latencyTrace.executorResumed(durationResult.executorCheckpoint)
            transcription.duration = durationResult.seconds
            latencyTrace.end(durationSpan)
        }

        if isCanceled(), writingSession == nil ? !didDeliverOrdinaryText : !writingDeliveryWasAttempted {
            await finishCanceledTranscription()
            return
        }
        if let processingFailureReason, !isCanceled() {
            let recovery = didDeliverOrdinaryText
                ? "The original was inserted."
                : "The original was retained."
            reportProcessingFailure("Dictation processing failed. \(recovery) \(processingFailureReason)")
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

}
