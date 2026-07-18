import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    @Published var recordingState: VoiceInkRecordingState = .idle
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?
    private var activeRecordingStartID: UUID?
    private var activePipelineTranscriptionID: UUID?
    private var canceledPipelineTranscriptionIDs = Set<UUID>()
    private var stopRequestedDuringStart = false

    let recorder = Recorder()
    var recordedFile: URL? = nil
    let recordingsDirectory: URL

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderUIManager?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    private let pipeline: TranscriptionPipeline

    let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "VoiceInkEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService

        self.recordingsDirectory = VoiceInkMacOSStorageDirectories.recordingsDirectory

        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        self.serviceRegistry = serviceRegistry
        self.pipeline = TranscriptionPipeline(
            modelContext: modelContext,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )

        super.init()

        if let enhancementService {
            PowerModeSessionManager.shared.configure(engine: self, enhancementService: enhancementService)
        }

        setupNotifications()
        createRecordingsDirectoryIfNeeded()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("❌ Error creating recordings directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Toggle Record

    func toggleRecord(powerModeId: UUID? = nil) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.ensureStarted(
            event: "engine.toggle_requested",
            details: "source=non_shortcut state=\(String(describing: recordingState))"
        )
        latencyTrace.event(
            "engine.toggle.enter",
            details: "state=\(String(describing: recordingState))",
            token: traceToken
        )
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")

        if recordingState == .starting {
            latencyTrace.event("engine.stop.deferred_during_start", token: traceToken)
            logger.notice("toggleRecord: deferring stop until in-flight recording start finishes")
            stopRequestedDuringStart = true
            return
        }

        if recordingState.isActivelyRecording {
            latencyTrace.event("engine.stop_path.enter", token: traceToken)
            await stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
        } else {
            latencyTrace.event("engine.start_path.enter", token: traceToken)
            logger.notice("toggleRecord: entering start-recording branch")
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.title,
                    type: .error
                )
                await recorderUIManager?.dismissMiniRecorder()
                latencyTrace.finish(event: "engine.start.no_model", token: traceToken)
                return
            }
            activePipelineTranscriptionID = nil
            shouldCancelRecording = false
            stopRequestedDuringStart = false
            partialTranscript = ""

            let startLifecycleSpan = latencyTrace.begin("engine.start_lifecycle", token: traceToken)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                latencyTrace.event("engine.permission.request", token: traceToken)
                requestRecordPermission(latencyTraceToken: traceToken) { [self] granted in
                    latencyTrace.event(
                        "engine.permission.callback",
                        details: "granted=\(granted)",
                        token: traceToken
                    )
                    if granted {
                        Task { @MainActor [self] in
                            latencyTrace.event("engine.start_task.enter", token: traceToken)
                            defer {
                                latencyTrace.event("engine.start_task.resume_caller", token: traceToken)
                                continuation.resume()
                            }

                        let startID = UUID()
                        self.activeRecordingStartID = startID

                        do {
                            let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(in: self.recordingsDirectory)
                            self.recordedFile = permanentURL

                            let startupAudioRelay = RecordingStartupAudioRelay(
                                latencyTraceToken: traceToken
                            )
                            latencyTrace.event("engine.audio_relay.created", token: traceToken)
                            self.recorder.onAudioChunk = { data in
                                startupAudioRelay.handle(data)
                            }
                            self.recordingState = .starting
                            latencyTrace.event("engine.state.starting", token: traceToken)
                            self.logger.notice("toggleRecord: state=starting, starting audio hardware")
                            let powerModeConfigTask = Task { @MainActor in
                                let span = latencyTrace.begin("power_mode.resolve", token: traceToken)
                                let config = await ActiveWindowService.shared.resolveConfiguration(
                                    powerModeId: powerModeId,
                                    latencyTraceToken: traceToken
                                )
                                latencyTrace.end(span, details: "matched=\(config != nil)")
                                return config
                            }

                            let recorderStartSpan = latencyTrace.begin("recorder.start", token: traceToken)
                            do {
                                try await self.recorder.startRecording(
                                    toOutputFile: permanentURL,
                                    latencyTraceToken: traceToken
                                )
                                latencyTrace.end(recorderStartSpan, details: "result=success")
                            } catch {
                                latencyTrace.end(
                                    recorderStartSpan,
                                    details: "result=failure error=\(String(describing: type(of: error)))"
                                )
                                throw error
                            }

                            guard self.activeRecordingStartID == startID,
                                  self.recorderUIManager?.isRecorderSessionActive ?? true,
                                  !self.shouldCancelRecording else {
                                let shouldKeepRecordingFile = self.shouldCancelRecording
                                if self.activeRecordingStartID == startID {
                                    await self.recorder.stopRecording(latencyTraceToken: traceToken)
                                    if !shouldKeepRecordingFile {
                                        self.recordedFile = nil
                                    }
                                    self.recordingState = .idle
                                    self.activeRecordingStartID = nil
                                    self.stopRequestedDuringStart = false
                                }
                                latencyTrace.finish(
                                    event: "engine.start.aborted",
                                    details: "cancelRequested=\(self.shouldCancelRecording) recorderSessionActive=\(self.recorderUIManager?.isRecorderSessionActive ?? true)",
                                    token: traceToken
                                )
                                return
                            }

                            self.recordingState = .recording
                            latencyTrace.event("engine.state.recording", token: traceToken)
                            self.logger.notice("toggleRecord: recording started successfully, state=recording")

                            let resolvedPowerModeConfig = await powerModeConfigTask.value
                            let powerModeActivationSpan = latencyTrace.begin("power_mode.activate", token: traceToken)
                            await PowerModeManager.shared.activateConfiguration(resolvedPowerModeConfig)
                            latencyTrace.end(powerModeActivationSpan)
                            self.logger.notice("toggleRecord: Power Mode config applied before streaming setup")

                            if self.recordingState.isActivelyRecording,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                if self.stopRequestedDuringStart,
                                   self.activeRecordingStartID == startID,
                                   model.supportsRecordedFileTranscription {
                                    self.stopRequestedDuringStart = false
                                    if let startupStopSession = await self.prepareStartupStopStreamingSession(
                                        for: model,
                                        audioRelay: startupAudioRelay,
                                        latencyTraceToken: traceToken
                                    ) {
                                        self.currentSession = startupStopSession
                                        self.logger.notice("toggleRecord: stopping startup recording with streaming startup session")
                                    } else {
                                        self.currentSession = nil
                                        self.recorder.onAudioChunk = nil
                                        startupAudioRelay.clear()
                                        self.logger.notice("toggleRecord: stopping startup recording before fallback streaming setup")
                                    }
                                    await self.stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
                                    return
                                }

                                let session = self.serviceRegistry.createSession(
                                    for: model,
                                    onPartialTranscript: { [weak self] partial in
                                        Task { @MainActor in
                                            self?.partialTranscript = partial
                                        }
                                    }
                                )
                                self.currentSession = session
                                latencyTrace.event(
                                    "streaming_session.created",
                                    details: "model=\(model.displayName)",
                                    token: traceToken
                                )
                                let sessionPrepareSpan = latencyTrace.begin("streaming_session.prepare", token: traceToken)
                                let realCallback: ((Data) -> Void)?
                                do {
                                    realCallback = try await session.prepare(
                                        model: model,
                                        latencyTraceToken: traceToken
                                    )
                                    latencyTrace.end(
                                        sessionPrepareSpan,
                                        details: "result=success hasAudioSink=\(realCallback != nil)"
                                    )
                                } catch {
                                    latencyTrace.end(
                                        sessionPrepareSpan,
                                        details: "result=failure error=\(String(describing: type(of: error)))"
                                    )
                                    throw error
                                }

                                if let realCallback {
                                    let relayInstallSpan = latencyTrace.begin("audio_relay.install_sink", token: traceToken)
                                    startupAudioRelay.installSink(realCallback)
                                    latencyTrace.end(relayInstallSpan)
                                    self.recorder.onAudioChunk = realCallback
                                } else {
                                    self.recorder.onAudioChunk = nil
                                    startupAudioRelay.clear()
                                }
                            }

                            if self.stopRequestedDuringStart,
                               self.activeRecordingStartID == startID,
                               self.recordingState.isActivelyRecording {
                                self.stopRequestedDuringStart = false
                                latencyTrace.event("engine.deferred_stop.apply", token: traceToken)
                                self.logger.notice("toggleRecord: applying deferred stop after recording start")
                                await self.stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
                                return
                            }

                            Task { @MainActor [weak self] in
                                guard let self else { return }

                                if let model = self.transcriptionModelManager.currentTranscriptionModel {
                                    await model.transcriptionRuntimeResourcePlan.applyRecordingStartupRuntimeState(
                                        loadLocalWhisperModel: {
                                            if let localWhisperModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                                                forModelName: model.name,
                                                in: self.whisperModelManager.availableModels
                                            ),
                                               self.whisperModelManager.whisperContext == nil {
                                                do {
                                                    try await self.whisperModelManager.loadModel(localWhisperModel)
                                                } catch {
                                                    self.logger.error("❌ Model loading failed: \(error.localizedDescription, privacy: .public)")
                                                }
                                            }
                                        },
                                        loadLocalFluidAudioModel: {
                                            if let fluidAudioModel = model as? FluidAudioModel {
                                                try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                            }
                                        }
                                    )
                                }

                                if let enhancementService = self.enhancementService {
                                    enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            latencyTrace.event(
                                "engine.start.failed",
                                details: "error=\(String(describing: type(of: error)))",
                                token: traceToken
                            )
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                            self.recordingState = .idle
                            self.recordedFile = nil
                            self.activeRecordingStartID = nil
                            self.stopRequestedDuringStart = false
                            NotificationManager.shared.showNotification(
                                title: VoiceInkRecordingNotificationPresentation.failedToStart.title,
                                type: .error
                            )
                            self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                            await self.recorderUIManager?.dismissMiniRecorder()
                            latencyTrace.finish(
                                event: "engine.start.failure_complete",
                                details: "error=\(String(describing: type(of: error)))",
                                token: traceToken
                            )
                        }
                    }
                } else {
                    latencyTrace.event("engine.permission.denied", token: traceToken)
                    logger.error("❌ Recording permission denied.")
                    let presentation = VoiceInkRecordingNotificationPresentation.microphonePermissionRequired
                    let openMicrophonePermission: () -> Void = {
                        Task { @MainActor in
                            PermissionGrantCoordinator.openPermissionsAndGrantMicrophone()
                        }
                    }
                    NotificationManager.shared.showNotification(
                        title: presentation.title,
                        type: .error,
                        duration: presentation.duration,
                        onTap: openMicrophonePermission,
                        actionButton: presentation.actionButtonTitle.map { label in
                            (label: label, action: openMicrophonePermission)
                        }
                    )
                    Task { @MainActor [self] in
                        await self.recorderUIManager?.dismissMiniRecorder()
                        latencyTrace.finish(event: "engine.permission.denied_complete", token: traceToken)
                        continuation.resume()
                    }
                }
            }
            }
            latencyTrace.end(startLifecycleSpan)
        }
    }

    private func prepareStartupStopStreamingSession(
        for model: any TranscriptionModel,
        audioRelay: RecordingStartupAudioRelay,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> TranscriptionSession? {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "startup_stop_session.create",
            details: "model=\(model.displayName)",
            token: traceToken
        )
        let session = serviceRegistry.createSession(
            for: model,
            onPartialTranscript: { [weak self] partial in
                Task { @MainActor in
                    self?.partialTranscript = partial
                }
            }
        )

        let prepareSpan = latencyTrace.begin("startup_stop_session.prepare", token: traceToken)
        do {
            guard let callback = try await session.prepare(
                model: model,
                latencyTraceToken: traceToken
            ) else {
                latencyTrace.end(prepareSpan, details: "result=success hasAudioSink=false")
                session.cancel()
                return nil
            }
            latencyTrace.end(prepareSpan, details: "result=success hasAudioSink=true")

            let relaySpan = latencyTrace.begin("startup_stop_audio_relay.install_sink", token: traceToken)
            audioRelay.installSink(callback)
            latencyTrace.end(relaySpan)
            recorder.onAudioChunk = callback
            return session
        } catch {
            latencyTrace.end(
                prepareSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            latencyTrace.event(
                "startup_stop_session.failed",
                details: "error=\(String(describing: type(of: error)))",
                token: traceToken
            )
            session.cancel()
            logger.error("Startup-stop streaming setup failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func stopRecordingAndRunPipeline(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "engine.stop_pipeline.enter",
            details: "hasSession=\(currentSession != nil) hasFile=\(recordedFile != nil)",
            token: traceToken
        )
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        partialTranscript = ""
        recordingState = .transcribing
        latencyTrace.event("engine.state.transcribing", token: traceToken)
        let recorderStopSpan = latencyTrace.begin("recorder.stop", token: traceToken)
        await recorder.stopRecording(latencyTraceToken: traceToken)
        latencyTrace.end(recorderStopSpan)

        if let recordedFile {
            if !shouldCancelRecording {
                let recordCreationSpan = latencyTrace.begin("transcription_record.create", token: traceToken)
                let transcription = makePendingRecordingTranscription(
                    for: recordedFile,
                    duration: 0
                )
                modelContext.insert(transcription)
                latencyTrace.end(recordCreationSpan)

                latencyTrace.event("pipeline.dispatch", token: traceToken)
                await runPipeline(
                    on: transcription,
                    audioURL: recordedFile,
                    latencyTraceToken: traceToken
                )
            } else {
                latencyTrace.event("engine.stop_pipeline.cancelled", token: traceToken)
                await finishActiveRecorderCancellation(latencyTraceToken: traceToken)
            }
        } else {
            latencyTrace.event("engine.stop_pipeline.missing_file", token: traceToken)
            cancelCurrentSession()
            if !shouldCancelRecording {
                logger.error("❌ No recorded file found after stopping recording")
            }
            recordingState = .idle
            await cleanupResources()
            latencyTrace.finish(event: "engine.stop_pipeline.missing_file_complete", token: traceToken)
        }
    }

    private func requestRecordPermission(
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        response: @escaping (Bool) -> Void
    ) {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let span = latencyTrace.begin("permission.authorization_status", token: traceToken)
        let permissionStatus: VoiceInkRecordingPermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionStatus = .granted
        case .notDetermined:
            permissionStatus = .undetermined
        case .denied, .restricted:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .denied
        }
        latencyTrace.end(
            span,
            details: "status=\(String(describing: permissionStatus))"
        )

        VoiceInkRecordingPermissionPolicy.plan(for: permissionStatus).applyRuntimeState(
            startRecording: {
                response(true)
            },
            presentPermissionDenied: {
                response(false)
            },
            requestPermission: { completion in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
            }
        )
    }

    // MARK: - Pipeline Dispatch

    private func runPipeline(
        on transcription: Transcription,
        audioURL: URL,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.markAsFailedTranscription(reason: VoiceInkModelManagementPresentation.noModelSelectedText)
            try? modelContext.save()
            recordingState = .idle
            latencyTrace.finish(event: "pipeline.no_model", token: traceToken)
            return
        }

        let session = currentSession
        let transcriptionID = transcription.id
        activePipelineTranscriptionID = transcriptionID

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            latencyTraceToken: traceToken,
            onStateChange: { [weak self] state in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                self.recordingState = state
            },
            shouldCancel: { [weak self] in
                guard let self else { return false }
                return self.canceledPipelineTranscriptionIDs.contains(transcriptionID)
                    || (self.activePipelineTranscriptionID == transcriptionID && self.shouldCancelRecording)
            },
            onCancel: { [weak self, session] in
                guard let self else { return }
                self.cancelPipelineSession(transcriptionID: transcriptionID, session: session)
            },
            onDismiss: { [weak self] in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                await self.recorderUIManager?.dismissMiniRecorder()
            }
        )
        let didFinishActivePipeline = activePipelineTranscriptionID == transcriptionID
        if didFinishActivePipeline {
            await finishRecorderSession()
            // Keep successful local STT resources warm for the next recording.
            activePipelineTranscriptionID = nil
            currentSession = nil
            recordedFile = nil
            shouldCancelRecording = false
        }
        canceledPipelineTranscriptionIDs.remove(transcriptionID)

        if didFinishActivePipeline,
           recordingState.shouldReturnToIdleWhenActivePipelineFinishes {
            recordingState = .idle
        }
    }

    // MARK: - Cancellation

    func cancelRecording() async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        latencyTrace.event(
            "engine.cancel_requested",
            details: "state=\(String(describing: recordingState))",
            token: traceToken
        )
        logger.notice("cancelRecording called – state=\(String(describing: self.recordingState), privacy: .public)")
        let cancellationPlan = VoiceInkMacOSRecordingCancellationPolicy.plan(
            recordingState: recordingState
        )

        await cancellationPlan.applyRuntimeState(
            clearDeferredStopRequest: {
                stopRequestedDuringStart = false
            },
            requestRecordingCancellation: {
                requestRecordingCancellation()
            },
            finishActiveRecorderCancellation: {
                await finishActiveRecorderCancellation(latencyTraceToken: traceToken)
            },
            clearPartialTranscript: {
                partialTranscript = ""
            },
            clearCancelFlag: {
                shouldCancelRecording = false
            },
            setRecordingState: {
                recordingState = $0
            },
            finishRecorderSessionImmediately: {
                await finishRecorderSession()
            }
        )
    }

    func resetRecordingSession() async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        cancelCurrentSession()
        activeRecordingStartID = nil
        activePipelineTranscriptionID = nil
        canceledPipelineTranscriptionIDs.removeAll()
        shouldCancelRecording = false
        stopRequestedDuringStart = false
        partialTranscript = ""
        await recorder.stopRecording(latencyTraceToken: traceToken)
        recordedFile = nil
        recordingState = .idle
        await cleanupResources()
        await finishRecorderSession()
        latencyTrace.finish(event: "engine.session_reset_complete", token: traceToken)
    }

    private func requestRecordingCancellation() {
        shouldCancelRecording = true

        if recordingState.isPostRecordingProcessing,
           let activePipelineTranscriptionID {
            canceledPipelineTranscriptionIDs.insert(activePipelineTranscriptionID)
        }

        cancelCurrentSession()
    }

    private func finishActiveRecorderCancellation(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await recorder.stopRecording(latencyTraceToken: traceToken)
        await saveCanceledRecording()
        recordedFile = nil
        partialTranscript = ""
        recordingState = .idle
        await cleanupResources()
        latencyTrace.finish(event: "engine.recording_cancelled", token: traceToken)
    }

    private func saveCanceledRecording() async {
        guard let recordedFile,
              FileManager.default.fileExists(atPath: recordedFile.path)
        else { return }

        let duration = await AudioFileMetadata.duration(for: recordedFile)
        let transcription = makeCanceledRecordingTranscription(
            for: recordedFile,
            duration: duration
        )

        modelContext.insert(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save canceled recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makePendingRecordingTranscription(
        for audioURL: URL,
        duration: TimeInterval
    ) -> Transcription {
        let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
            from: PowerModeManager.shared.activeConfiguration
        )

        let draft = VoiceInkRecordingTranscriptionDraft.pending(
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji
        )
        return Transcription(recordingDraft: draft)
    }

    private func makeCanceledRecordingTranscription(
        for audioURL: URL,
        duration: TimeInterval
    ) -> Transcription {
        let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
            from: PowerModeManager.shared.activeConfiguration
        )

        let draft = VoiceInkRecordingTranscriptionDraft.canceled(
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji
        )
        return Transcription(recordingDraft: draft)
    }

    // MARK: - Resource Cleanup

    private func cancelPipelineSession(transcriptionID: UUID, session: TranscriptionSession?) {
        session?.cancel()

        guard activePipelineTranscriptionID == transcriptionID else {
            logger.notice("Skipping stale pipeline cleanup")
            return
        }

        currentSession = nil
    }

    private func cancelCurrentSession() {
        currentSession?.cancel()
        currentSession = nil
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
        await restorePowerModeIfNeeded()
    }

    private func restorePowerModeIfNeeded() async {
        await VoiceInkPowerModeRecordingFinishPlan.finishingRecording(
            shouldPersistConfiguredPreferences: VoiceInkPowerModePreference.shouldPersistConfiguredPreferences()
        ).applyRuntimeState(
            endSession: {
                await PowerModeSessionManager.shared.endSession()
            },
            clearActiveConfiguration: {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        )
    }

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLicenseStatusChanged),
            name: .licenseStatusChanged,
            object: nil
        )
    }

    @objc func handleLicenseStatusChanged() {
        pipeline.licenseViewModel = LicenseViewModel()
    }

}

enum AudioFileMetadata {
    static func duration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
