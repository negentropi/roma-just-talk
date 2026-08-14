import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore

struct VoiceInkRecordingStartLifecycle {
    private var inFlightID: UUID?
    private var discardedID: UUID?

    mutating func begin(_ id: UUID) -> Bool {
        guard inFlightID == nil else { return false }
        inFlightID = id
        return true
    }

    mutating func markDiscard(_ id: UUID?) {
        guard id == inFlightID else { return }
        discardedID = id
    }

    mutating func finish(_ id: UUID) {
        guard inFlightID == id else { return }
        inFlightID = nil
        discardedID = nil
    }

    func canContinue(
        _ id: UUID,
        activeID: UUID?,
        recorderSessionActive: Bool,
        cancellationRequested: Bool
    ) -> Bool {
        inFlightID == id
            && discardedID != id
            && activeID == id
            && recorderSessionActive
            && !cancellationRequested
    }

    func shouldDeleteOutput(for id: UUID) -> Bool {
        discardedID == id
    }

    var hasInFlightStart: Bool {
        inFlightID != nil
    }
}

private enum VoiceInkRecordingStartError: Error {
    case invalidated(String)
}

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
    private var recordingStartLifecycle = VoiceInkRecordingStartLifecycle()

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
            let startID = UUID()
            guard recordingStartLifecycle.begin(startID) else {
                latencyTrace.finish(event: "engine.start.in_flight", token: traceToken)
                await recorderUIManager?.dismissMiniRecorder()
                return
            }
            defer { recordingStartLifecycle.finish(startID) }
            activeRecordingStartID = startID

            let startLifecycleSpan = latencyTrace.begin("engine.start_lifecycle", token: traceToken)
            latencyTrace.event("engine.permission.request", token: traceToken)
            let granted = await requestRecordPermission(latencyTraceToken: traceToken)
            latencyTrace.event(
                "engine.permission.callback",
                details: "granted=\(granted)",
                token: traceToken
            )
            guard recordingStartCanContinue(startID) else {
                let wasDiscarded = recordingStartLifecycle.shouldDeleteOutput(for: startID)
                if activeRecordingStartID == startID {
                    activeRecordingStartID = nil
                }
                latencyTrace.finish(
                    event: wasDiscarded
                        ? "engine.start.discarded_before_authorization"
                        : "engine.start.invalidated_before_authorization",
                    token: traceToken
                )
                latencyTrace.end(startLifecycleSpan)
                return
            }
            if granted {
                latencyTrace.event("engine.start_authorized.enter", token: traceToken)
                defer {
                    latencyTrace.event("engine.start_authorized.complete", token: traceToken)
                }

                        var powerModeConfigTask: Task<PowerModeConfig?, Never>?
                        let startupAudioRelay = RecordingStartupAudioRelay(
                            latencyTraceToken: traceToken
                        )
                        let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(
                            in: self.recordingsDirectory
                        )
                        latencyTrace.event("engine.audio_relay.created", token: traceToken)

                        do {
                            self.recordedFile = permanentURL

                            self.currentSession?.cancel()
                            self.currentSession = nil
                            self.recorder.onAudioChunk = { data in
                                startupAudioRelay.handle(data)
                            }
                            self.recordingState = .starting
                            latencyTrace.event("engine.state.starting", token: traceToken)
                            self.logger.notice("toggleRecord: state=starting, starting audio hardware")

                            let startupPlan = VoiceInkMacOSRecordingStartupOrchestrationPolicy.plan(
                                powerModeConfigurationCount: PowerModeManager.shared.configurations.count
                            )
                            latencyTrace.event(
                                "engine.start_orchestration.plan",
                                details: "resolvePowerMode=\(startupPlan.shouldResolvePowerMode) prepareSessionBeforeRecorder=\(startupPlan.shouldPrepareTranscriptionSessionBeforeRecorder)",
                                token: traceToken
                            )

                            if startupPlan.shouldResolvePowerMode {
                                powerModeConfigTask = Task { @MainActor in
                                    guard !Task.isCancelled else { return nil }
                                    let span = latencyTrace.begin("power_mode.resolve", token: traceToken)
                                    let config = await ActiveWindowService.shared.resolveConfiguration(
                                        powerModeId: powerModeId,
                                        latencyTraceToken: traceToken
                                    )
                                    latencyTrace.end(span, details: "matched=\(config != nil)")
                                    guard !Task.isCancelled else {
                                        latencyTrace.event("power_mode.resolve.discarded", details: "reason=cancelled", token: traceToken)
                                        return nil
                                    }
                                    return config
                                }
                            } else {
                                powerModeConfigTask = nil
                                latencyTrace.event("power_mode.resolve.skipped", details: "reason=no_configurations", token: traceToken)
                            }

                            if startupPlan.shouldPrepareTranscriptionSessionBeforeRecorder,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                guard try await self.prepareRecordingTranscriptionSession(
                                    for: model,
                                    audioRelay: startupAudioRelay,
                                    latencyTraceToken: traceToken,
                                    startID: startID
                                ) else {
                                    throw VoiceInkRecordingStartError.invalidated("session_prepare")
                                }
                            }

                            guard self.recordingStartCanContinue(startID) else {
                                throw VoiceInkRecordingStartError.invalidated("before_recorder")
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
                            guard self.recordingStartCanContinue(startID) else {
                                throw VoiceInkRecordingStartError.invalidated("after_recorder")
                            }

                            self.recordingState = .recording
                            latencyTrace.event("engine.state.recording", token: traceToken)
                            self.logger.notice("toggleRecord: recording started successfully, state=recording")

                            if let powerModeConfigTask {
                                let resolvedPowerModeConfig = await powerModeConfigTask.value
                                guard self.recordingStartCanContinue(startID),
                                      self.recordingState.isActivelyRecording else {
                                    throw VoiceInkRecordingStartError.invalidated("power_mode_resolve")
                                }
                                let powerModeActivationSpan = latencyTrace.begin("power_mode.activate", token: traceToken)
                                await PowerModeManager.shared.activateConfiguration(resolvedPowerModeConfig)
                                latencyTrace.end(powerModeActivationSpan)
                                guard self.recordingStartCanContinue(startID),
                                      self.recordingState.isActivelyRecording else {
                                    throw VoiceInkRecordingStartError.invalidated("power_mode_activate")
                                }
                                self.logger.notice("toggleRecord: Power Mode config applied before streaming setup")
                            }

                            if self.recordingState.isActivelyRecording,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                if self.stopRequestedDuringStart,
                                   self.activeRecordingStartID == startID,
                                   model.supportsRecordedFileTranscription {
                                    self.stopRequestedDuringStart = false
                                    if self.currentSession == nil {
                                        if let startupStopSession = await self.prepareStartupStopStreamingSession(
                                            for: model,
                                            audioRelay: startupAudioRelay,
                                            latencyTraceToken: traceToken
                                        ) {
                                            self.currentSession = startupStopSession
                                            self.logger.notice("toggleRecord: stopping startup recording with streaming startup session")
                                        } else {
                                            self.recorder.onAudioChunk = nil
                                            startupAudioRelay.clear()
                                            self.logger.notice("toggleRecord: stopping startup recording before fallback streaming setup")
                                        }
                                    }
                                    await self.stopRecordingAndRunPipeline(latencyTraceToken: traceToken)
                                    return
                                }

                                if self.currentSession == nil {
                                    guard try await self.prepareRecordingTranscriptionSession(
                                        for: model,
                                        audioRelay: startupAudioRelay,
                                        latencyTraceToken: traceToken,
                                        startID: startID
                                    ) else {
                                        throw VoiceInkRecordingStartError.invalidated("streaming_prepare")
                                    }
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

                            guard self.recordingStartCanContinue(startID),
                                  self.recordingState.isActivelyRecording else {
                                throw VoiceInkRecordingStartError.invalidated("startup_complete")
                            }

                            Task { @MainActor [weak self] in
                                guard let self,
                                      self.activeRecordingStartID == startID,
                                      self.recordingState.isActivelyRecording else { return }

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

                                guard self.activeRecordingStartID == startID,
                                      self.recordingState.isActivelyRecording else { return }

                                if let enhancementService = self.enhancementService {
                                    enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch VoiceInkRecordingStartError.invalidated(let reason) {
                            await self.abortRecordingStart(
                                startID: startID,
                                permanentURL: permanentURL,
                                audioRelay: startupAudioRelay,
                                powerModeConfigTask: powerModeConfigTask,
                                latencyTraceToken: traceToken,
                                reason: reason
                            )
                        } catch {
                            await self.abortRecordingStart(
                                startID: startID,
                                permanentURL: permanentURL,
                                audioRelay: startupAudioRelay,
                                powerModeConfigTask: powerModeConfigTask,
                                latencyTraceToken: traceToken,
                                reason: "error"
                            )
                            latencyTrace.event(
                                "engine.start.failed",
                                details: "error=\(String(describing: type(of: error)))",
                                token: traceToken
                            )
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
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
            } else {
                if activeRecordingStartID == startID {
                    activeRecordingStartID = nil
                }
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
                await self.recorderUIManager?.dismissMiniRecorder()
                latencyTrace.finish(event: "engine.permission.denied_complete", token: traceToken)
            }
            latencyTrace.end(startLifecycleSpan)
        }
    }

    private func recordingStartCanContinue(_ startID: UUID) -> Bool {
        recordingStartLifecycle.canContinue(
            startID,
            activeID: activeRecordingStartID,
            recorderSessionActive: recorderUIManager?.isRecorderSessionActive ?? true,
            cancellationRequested: shouldCancelRecording
        )
    }

    private func abortRecordingStart(
        startID: UUID,
        permanentURL: URL,
        audioRelay: RecordingStartupAudioRelay,
        powerModeConfigTask: Task<PowerModeConfig?, Never>?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        reason: String
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let wasDiscarded = recordingStartLifecycle.shouldDeleteOutput(for: startID)
        let shouldDeleteOutput = wasDiscarded
            || !shouldCancelRecording
        powerModeConfigTask?.cancel()
        latencyTrace.event(
            "power_mode.resolve.cancelled",
            details: "reason=start_aborted phase=\(reason)",
            token: latencyTraceToken
        )

        // This task owns the only in-flight recorder start. Stop again after its
        // await resumes: an earlier cancellation may have run before capture began.
        await recorder.stopRecording(latencyTraceToken: latencyTraceToken)
        currentSession?.cancel()
        currentSession = nil
        recorder.onAudioChunk = nil
        audioRelay.clear()
        recordingState = .idle
        if activeRecordingStartID == startID {
            activeRecordingStartID = nil
        }
        stopRequestedDuringStart = false
        await cleanupResources()

        if shouldDeleteOutput {
            VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(
                for: permanentURL.absoluteString
            ) { message in
                logger.error("Failed to discard aborted recording start: \(message, privacy: .public)")
            }
            if recordedFile == permanentURL {
                recordedFile = nil
            }
        }

        latencyTrace.finish(
            event: wasDiscarded ? "engine.start.discarded" : "engine.start.aborted",
            details: "phase=\(reason) outputDeleted=\(shouldDeleteOutput)",
            token: latencyTraceToken
        )
    }

    private func prepareRecordingTranscriptionSession(
        for model: any TranscriptionModel,
        audioRelay: RecordingStartupAudioRelay,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        startID: UUID
    ) async throws -> Bool {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let session = serviceRegistry.createSession(
            for: model,
            onPartialTranscript: { [weak self] partial in
                Task { @MainActor in
                    self?.partialTranscript = partial
                }
            }
        )
        currentSession = session
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
            session.cancel()
            currentSession = nil
            throw error
        }

        guard recordingStartCanContinue(startID) else {
            session.cancel()
            if currentSession === session {
                currentSession = nil
            }
            audioRelay.clear()
            recorder.onAudioChunk = nil
            return false
        }

        if let realCallback {
            let relayInstallSpan = latencyTrace.begin("audio_relay.install_sink", token: traceToken)
            audioRelay.installSink(realCallback)
            latencyTrace.end(relayInstallSpan)
            recorder.onAudioChunk = realCallback
        } else {
            recorder.onAudioChunk = nil
            audioRelay.clear()
        }
        return true
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
                await finishActiveRecorderCancellation(
                    latencyTraceToken: traceToken,
                    preservingCanceledRecording: true
                )
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
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> Bool {
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

        switch permissionStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
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
        await cancelRecording(preservingCanceledRecording: true)
    }

    func discardRecording() async {
        recordingStartLifecycle.markDiscard(activeRecordingStartID)
        await cancelRecording(preservingCanceledRecording: false)
    }

    private func cancelRecording(preservingCanceledRecording: Bool) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        let requestEvent = preservingCanceledRecording ? "engine.cancel_requested" : "engine.discard_requested"
        latencyTrace.event(
            requestEvent,
            details: "state=\(String(describing: recordingState))",
            token: traceToken
        )
        logger.notice("cancelRecording called – preserve=\(preservingCanceledRecording, privacy: .public) state=\(String(describing: self.recordingState), privacy: .public)")
        if !preservingCanceledRecording {
            activeRecordingStartID = nil
        }
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
                await finishActiveRecorderCancellation(
                    latencyTraceToken: traceToken,
                    preservingCanceledRecording: preservingCanceledRecording
                )
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
        if !preservingCanceledRecording {
            shouldCancelRecording = false
        }
    }

    func resetRecordingSession() async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.currentToken()
        cancelCurrentSession()
        recordingStartLifecycle.markDiscard(activeRecordingStartID)
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
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        preservingCanceledRecording: Bool
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let discardedStartStillInFlight = !preservingCanceledRecording
            && recordingStartLifecycle.hasInFlightStart
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await recorder.stopRecording(latencyTraceToken: traceToken)
        if preservingCanceledRecording {
            await saveCanceledRecording(latencyTraceToken: traceToken)
            recordedFile = nil
        } else {
            discardRecordedFile()
        }
        partialTranscript = ""
        recordingState = .idle
        await cleanupResources()
        if !discardedStartStillInFlight {
            latencyTrace.finish(
                event: preservingCanceledRecording ? "engine.recording_cancelled" : "engine.recording_discarded",
                token: traceToken
            )
        }
    }

    private func discardRecordedFile() {
        guard let recordedFile else { return }
        VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(
            for: recordedFile.absoluteString
        ) { message in
            logger.error("Failed to discard recording: \(message, privacy: .public)")
        }
        self.recordedFile = nil
    }

    private func saveCanceledRecording(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async {
        guard let recordedFile,
              FileManager.default.fileExists(atPath: recordedFile.path)
        else { return }

        let durationResult = await AudioFileMetadata.tracedDuration(
            for: recordedFile,
            executorName: "engine.cancel_audio_duration",
            latencyTraceToken: latencyTraceToken
        )
        VoiceInkLatencyTrace.shared.executorResumed(durationResult.executorCheckpoint)
        let transcription = makeCanceledRecordingTranscription(
            for: recordedFile,
            duration: durationResult.seconds
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
    struct DurationResult: Sendable {
        let seconds: TimeInterval
        let executorCheckpoint: VoiceInkLatencyTrace.ExecutorCheckpoint?
    }

    static func tracedDuration(
        for url: URL,
        executorName: String,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> DurationResult {
        let asset = AVURLAsset(url: url)
        let seconds: TimeInterval
        if let duration = try? await asset.load(.duration) {
            let loadedSeconds = CMTimeGetSeconds(duration)
            seconds = loadedSeconds.isFinite ? loadedSeconds : 0
        } else {
            seconds = 0
        }
        let checkpoint = VoiceInkLatencyTrace.shared.executorEnqueued(
            executorName,
            token: latencyTraceToken
        )
        return DurationResult(
            seconds: seconds,
            executorCheckpoint: checkpoint
        )
    }
}
