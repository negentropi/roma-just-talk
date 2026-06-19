import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore

struct RollingBufferPreloadClaim {
    let preloaded: RollingBufferPreloadedSession
    let modelName: String
    let language: String?

    func matches(model: any TranscriptionModel, language: String?) -> Bool {
        modelName == model.name && self.language == language
    }
}

private struct PreparedQuickReleaseContext {
    let powerModeId: UUID?
    let powerModeTask: Task<PowerModeConfig?, Never>
    let cursorContextTask: Task<String?, Never>
    let pasteContextTask: Task<CursorPaster.PreparedPasteContext?, Never>

    func matches(powerModeId: UUID?) -> Bool {
        self.powerModeId == powerModeId
    }
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

    let recorder = Recorder()
    var recordedFile: URL? = nil
    let recordingsDirectory: URL

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderUIManager?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    private let rollingBufferPreloadCoordinator: RollingBufferPreloadCoordinator
    let enhancementService: AIEnhancementService?
    private let pipeline: TranscriptionPipeline
    private var preparedQuickReleaseContext: PreparedQuickReleaseContext?

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

        let appSupportDirectory = VoiceInkAppIdentity.macOSApplicationSupportDirectory(
            in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
        self.recordingsDirectory = VoiceInkStoredAudioFile.recordingsDirectory(in: appSupportDirectory)

        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        self.serviceRegistry = serviceRegistry
        self.rollingBufferPreloadCoordinator = RollingBufferPreloadCoordinator(
            serviceRegistry: serviceRegistry,
            transcriptionModelManager: transcriptionModelManager
        )
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
        recorder.onRollingAudioChunk = rollingBufferPreloadCoordinator.audioChunkHandler
        rollingBufferPreloadCoordinator.start()
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
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")

        if recordingState == .starting {
            logger.notice("toggleRecord: deferring stop until in-flight recording start finishes")
            stopRequestedDuringStart = true
            return
        }

        if recordingState.isActivelyRecording {
            await stopRecordingAndRunPipeline()
        } else {
            logger.notice("toggleRecord: entering start-recording branch")
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.title,
                    type: .error
                )
                await recorderUIManager?.dismissMiniRecorder()
                return
            }
            activePipelineTranscriptionID = nil
            shouldCancelRecording = false
            stopRequestedDuringStart = false
            partialTranscript = ""

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                requestRecordPermission { [self] granted in
                if granted {
                    Task { @MainActor [self] in
                        defer { continuation.resume() }

                        let startID = UUID()
                        self.activeRecordingStartID = startID

                        do {
                            let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(in: self.recordingsDirectory)
                            self.recordedFile = permanentURL

                            let startupAudioRelay = RecordingStartupAudioRelay()
                            self.recorder.onAudioChunk = { data in
                                startupAudioRelay.handle(data)
                            }
                            self.rollingBufferPreloadCoordinator.prepareForRecordingStart()

                            self.recordingState = .starting
                            self.logger.notice("toggleRecord: state=starting, starting audio hardware")
                            let powerModeConfigTask = Task { @MainActor in
                                await ActiveWindowService.shared.resolveConfiguration(powerModeId: powerModeId)
                            }

                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            guard self.activeRecordingStartID == startID,
                                  self.recorderUIManager?.isRecorderSessionActive ?? true,
                                  !self.shouldCancelRecording else {
                                let shouldKeepRecordingFile = self.shouldCancelRecording
                                if self.activeRecordingStartID == startID {
                                    await self.recorder.stopRecording()
                                    if !shouldKeepRecordingFile {
                                        self.recordedFile = nil
                                    }
                                    self.recordingState = .idle
                                    self.activeRecordingStartID = nil
                                    self.stopRequestedDuringStart = false
                                    self.rollingBufferPreloadCoordinator.recordingSessionDidFinish()
                                }
                                return
                            }

                            self.recordingState = .recording
                            self.logger.notice("toggleRecord: recording started successfully, state=recording")

                            let resolvedPowerModeConfig = await powerModeConfigTask.value
                            await ActiveWindowService.shared.applyResolvedConfiguration(resolvedPowerModeConfig)
                            self.logger.notice("toggleRecord: Power Mode config applied before streaming setup")

                            var claimedPreload: RollingBufferPreloadClaim?
                            if let model = self.transcriptionModelManager.currentTranscriptionModel,
                               let preloaded = await self.rollingBufferPreloadCoordinator.claimPreloadedSession(for: model) {
                                claimedPreload = RollingBufferPreloadClaim(
                                    preloaded: preloaded,
                                    modelName: model.name,
                                    language: preloaded.language
                                )
                            }

                            if self.recordingState.isActivelyRecording,
                               let model = self.transcriptionModelManager.currentTranscriptionModel {
                                if let claim = claimedPreload,
                                   claim.matches(model: model, language: VoiceInkTranscriptionLanguagePreference.storedLanguage()) {
                                    self.currentSession = claim.preloaded.session
                                    startupAudioRelay.installSink(claim.preloaded.audioChunkHandler)
                                    self.recorder.onAudioChunk = claim.preloaded.audioChunkHandler
                                } else {
                                    if let claim = claimedPreload {
                                        claim.preloaded.session.cancel()
                                        self.currentSession = nil
                                        self.recorder.onAudioChunk = { data in
                                            startupAudioRelay.handle(data)
                                        }
                                    }
                                    self.rollingBufferPreloadCoordinator.cancelUnclaimedPreload(reason: "recording-start-fallback")
                                    if self.stopRequestedDuringStart,
                                       self.activeRecordingStartID == startID,
                                       model.supportsRecordedFileTranscription {
                                        self.stopRequestedDuringStart = false
                                        if let startupStopSession = await self.prepareStartupStopStreamingSession(
                                            for: model,
                                            audioRelay: startupAudioRelay
                                        ) {
                                            self.currentSession = startupStopSession
                                            self.logger.notice("toggleRecord: stopping startup recording with streaming startup session")
                                        } else {
                                            self.currentSession = nil
                                            self.recorder.onAudioChunk = nil
                                            startupAudioRelay.clear()
                                            self.logger.notice("toggleRecord: stopping startup recording before fallback streaming setup")
                                        }
                                        await self.stopRecordingAndRunPipeline()
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
                                    let realCallback = try await session.prepare(model: model)

                                    if let realCallback {
                                        startupAudioRelay.installSink(realCallback)
                                        self.recorder.onAudioChunk = realCallback
                                    } else {
                                        self.recorder.onAudioChunk = nil
                                        startupAudioRelay.clear()
                                    }
                                }
                            }

                            if self.stopRequestedDuringStart,
                               self.activeRecordingStartID == startID,
                               self.recordingState.isActivelyRecording {
                                self.stopRequestedDuringStart = false
                                self.logger.notice("toggleRecord: applying deferred stop after recording start")
                                await self.stopRecordingAndRunPipeline()
                                return
                            }

                            Task { @MainActor [weak self] in
                                guard let self else { return }

                                if let model = self.transcriptionModelManager.currentTranscriptionModel {
                                    switch model.transcriptionRuntimeResourcePlan.recordingStartupLoadAction {
                                    case .loadLocalWhisperModel:
                                        if let localWhisperModel = self.whisperModelManager.availableModels.first(where: { $0.name == model.name }),
                                           self.whisperModelManager.whisperContext == nil {
                                            do {
                                                try await self.whisperModelManager.loadModel(localWhisperModel)
                                            } catch {
                                                self.logger.error("❌ Model loading failed: \(error.localizedDescription, privacy: .public)")
                                            }
                                        }
                                    case .loadLocalFluidAudioModel:
                                        if let fluidAudioModel = model as? FluidAudioModel {
                                            try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                        }
                                    case .none:
                                        break
                                    }
                                }

                                if let enhancementService = self.enhancementService {
                                    enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                            self.recordingState = .idle
                            self.recordedFile = nil
                            self.activeRecordingStartID = nil
                            self.stopRequestedDuringStart = false
                            self.rollingBufferPreloadCoordinator.recordingSessionDidFinish()
                            NotificationManager.shared.showNotification(
                                title: VoiceInkRecordingNotificationPresentation.failedToStart.title,
                                type: .error
                            )
                            self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                            await self.recorderUIManager?.dismissMiniRecorder()
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                    NotificationManager.shared.showNotification(
                        title: "Microphone permission required",
                        type: .error,
                        duration: 8.0,
                        onTap: {
                            Task { @MainActor in
                                PermissionGrantCoordinator.openPermissionsAndGrantMicrophone()
                            }
                        },
                        actionButton: (
                            label: "Grant",
                            action: {
                                Task { @MainActor in
                                    PermissionGrantCoordinator.openPermissionsAndGrantMicrophone()
                                }
                            }
                        )
                    )
                    Task { @MainActor [self] in
                        await self.recorderUIManager?.dismissMiniRecorder()
                        continuation.resume()
                    }
                }
            }
            }
        }
    }

    private func prepareStartupStopStreamingSession(
        for model: any TranscriptionModel,
        audioRelay: RecordingStartupAudioRelay
    ) async -> TranscriptionSession? {
        let session = serviceRegistry.createSession(
            for: model,
            onPartialTranscript: { [weak self] partial in
                Task { @MainActor in
                    self?.partialTranscript = partial
                }
            }
        )

        do {
            guard let callback = try await session.prepare(model: model) else {
                session.cancel()
                return nil
            }

            audioRelay.installSink(callback)
            recorder.onAudioChunk = callback
            return session
        } catch {
            session.cancel()
            logger.error("Startup-stop streaming setup failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func stopRecordingAndRunPipeline() async {
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        partialTranscript = ""
        recordingState = .transcribing
        await recorder.stopRecording()

        if let recordedFile {
            if !shouldCancelRecording {
                let transcription = makePendingRecordingTranscription(
                    for: recordedFile,
                    duration: 0
                )
                modelContext.insert(transcription)

                await runPipeline(on: transcription, audioURL: recordedFile)
            } else {
                await finishActiveRecorderCancellation()
            }
        } else {
            cancelCurrentSession()
            if !shouldCancelRecording {
                logger.error("❌ No recorded file found after stopping recording")
            }
            recordingState = .idle
            await cleanupResources()
        }
    }

    func commitReadyRollingBufferPreload(powerModeId: UUID? = nil) async -> Bool {
        let latencyTrace = TranscriptionLatencyTrace(
            operation: TranscriptionLatencyTrace.rollingPreloadQuickReleaseOperation,
            startedAt: Date()
        )

        guard recordingState == .idle else {
            discardPreparedQuickReleaseContext()
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .unavailable,
                reason: "state-\(recordingState)",
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.notice("Latency trace preload commit unavailable operation=\(latencyTrace.operation, privacy: .public) reason=state elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            return false
        }

        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            discardPreparedQuickReleaseContext()
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .unavailable,
                reason: "no-model",
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.notice("Latency trace preload commit unavailable operation=\(latencyTrace.operation, privacy: .public) reason=no-model elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            return false
        }

        if let claimedPreload = await rollingBufferPreloadCoordinator.claimPreloadedSession(for: model) {
            return await commitClaimedRollingBufferPreload(
                claimedPreload,
                model: model,
                powerModeId: powerModeId,
                latencyTrace: latencyTrace
            )
        }

        guard RollingBufferBufferedSnapshotTranscriptionPolicy.strategy(for: model) == .recordedFile else {
            discardPreparedQuickReleaseContext()
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .unavailable,
                reason: "no-claim-nonbatch-model",
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.notice("Latency trace preload commit unavailable operation=\(latencyTrace.operation, privacy: .public) reason=no-claim-nonbatch-model elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            return false
        }

        guard let audioSnapshot = rollingBufferPreloadCoordinator.claimBufferedAudioSnapshot() else {
            discardPreparedQuickReleaseContext()
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .unavailable,
                reason: "no-claim",
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.notice("Latency trace preload commit unavailable operation=\(latencyTrace.operation, privacy: .public) reason=no-claim elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            return false
        }

        return await commitBufferedRollingAudioSnapshot(
            audioSnapshot,
            model: model,
            powerModeId: powerModeId,
            latencyTrace: latencyTrace
        )
    }

    private func commitClaimedRollingBufferPreload(
        _ claimedPreload: RollingBufferPreloadedSession,
        model: any TranscriptionModel,
        powerModeId: UUID?,
        latencyTrace: TranscriptionLatencyTrace
    ) async -> Bool {
        logger.notice("Latency trace preload claimed operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")

        let claim = RollingBufferPreloadClaim(
            preloaded: claimedPreload,
            modelName: model.name,
            language: claimedPreload.language
        )
        let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(in: recordingsDirectory)
        let audioData = claimedPreload.audioData
        let audioFileReadyTask = Task.detached(priority: .utility) {
            try PCM16WAVFileWriter.writeMono16k(audioData, to: permanentURL)
        }
        logger.notice("Latency trace deferred audio write scheduled operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s bytes=\(audioData.count, privacy: .public)")

        let preparedContext = takePreparedQuickReleaseContext(powerModeId: powerModeId)
        let powerModeApplyTask = startPowerModeConfigurationApply(powerModeId: powerModeId, preparedContext: preparedContext)
        logger.notice("Latency trace active window apply scheduled operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")

        guard let currentModel = transcriptionModelManager.currentTranscriptionModel,
              claim.matches(model: currentModel, language: VoiceInkTranscriptionLanguagePreference.storedLanguage()) else {
            claimedPreload.session.cancel()
            rollingBufferPreloadCoordinator.recordingSessionDidFinish()
            discardDeferredAudioFile(audioFileReadyTask, at: permanentURL)
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .invalidated,
                reason: "model-or-language-changed",
                audioBytes: claimedPreload.audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )
            return false
        }

        do {
            if let streamingSession = claimedPreload.session as? StreamingTranscriptionSession {
                streamingSession.setFallbackAudioReadyTask(audioFileReadyTask)
            } else {
                try await audioFileReadyTask.value
            }
            logger.notice("Latency trace deferred audio write attached operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s bytes=\(audioData.count, privacy: .public)")
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .readyPreload,
                audioBytes: audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )

            let transcription = makePendingRecordingTranscription(
                for: permanentURL,
                duration: VoiceInkPCM16Audio.duration(forMono16kData: audioData)
            )

            recordedFile = permanentURL
            currentSession = claimedPreload.session
            activeRecordingStartID = nil
            stopRequestedDuringStart = false
            shouldCancelRecording = false
            partialTranscript = ""
            recordingState = .transcribing

            await runPipeline(
                on: transcription,
                audioURL: permanentURL,
                audioFileReadyTask: audioFileReadyTask,
                latencyTrace: latencyTrace,
                deferHistoryInsertUntilSave: true,
                powerModeApplyTask: powerModeApplyTask,
                preparedCursorTextContext: preparedContext?.cursorContextTask,
                preparedPasteContext: preparedContext?.pasteContextTask
            )
            return true
        } catch {
            claimedPreload.session.cancel()
            rollingBufferPreloadCoordinator.recordingSessionDidFinish()
            discardDeferredAudioFile(audioFileReadyTask, at: permanentURL)
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .failed,
                reason: "ready-preload-error",
                audioBytes: claimedPreload.audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.error("commitReadyRollingBufferPreload failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func commitBufferedRollingAudioSnapshot(
        _ audioSnapshot: RollingBufferAudioSnapshot,
        model: any TranscriptionModel,
        powerModeId: UUID?,
        latencyTrace: TranscriptionLatencyTrace
    ) async -> Bool {
        logger.notice("Latency trace buffered audio claimed operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s bytes=\(audioSnapshot.audioData.count, privacy: .public)")
        let permanentURL = VoiceInkStoredAudioFile.recordingFileURL(in: recordingsDirectory)
        let audioData = audioSnapshot.audioData
        let audioFileReadyTask = Task.detached(priority: .utility) {
            try PCM16WAVFileWriter.writeMono16k(audioData, to: permanentURL)
        }
        logger.notice("Latency trace buffered audio file write scheduled operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s bytes=\(audioData.count, privacy: .public)")

        let preparedContext = takePreparedQuickReleaseContext(powerModeId: powerModeId)
        let powerModeApplyTask = startPowerModeConfigurationApply(powerModeId: powerModeId, preparedContext: preparedContext)
        logger.notice("Latency trace active window apply scheduled operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")

        guard let currentModel = transcriptionModelManager.currentTranscriptionModel,
              currentModel.name == model.name,
              audioSnapshot.language == VoiceInkTranscriptionLanguagePreference.storedLanguage() else {
            rollingBufferPreloadCoordinator.recordingSessionDidFinish()
            discardDeferredAudioFile(audioFileReadyTask, at: permanentURL)
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .invalidated,
                reason: "model-or-language-changed",
                audioBytes: audioSnapshot.audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )
            return false
        }

        do {
            try await audioFileReadyTask.value
            logger.notice("Latency trace buffered audio file ready operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s bytes=\(audioData.count, privacy: .public)")
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .bufferedAudioSnapshot,
                audioBytes: audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )

            let transcription = makePendingRecordingTranscription(
                for: permanentURL,
                duration: VoiceInkPCM16Audio.duration(forMono16kData: audioData)
            )

            recordedFile = permanentURL
            currentSession = nil
            activeRecordingStartID = nil
            stopRequestedDuringStart = false
            shouldCancelRecording = false
            partialTranscript = ""
            recordingState = .transcribing

            await runPipeline(
                on: transcription,
                audioURL: permanentURL,
                latencyTrace: latencyTrace,
                deferHistoryInsertUntilSave: true,
                powerModeApplyTask: powerModeApplyTask,
                preparedCursorTextContext: preparedContext?.cursorContextTask,
                preparedPasteContext: preparedContext?.pasteContextTask
            )
            return true
        } catch {
            rollingBufferPreloadCoordinator.recordingSessionDidFinish()
            discardDeferredAudioFile(audioFileReadyTask, at: permanentURL)
            RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseClaim(
                strategy: .failed,
                reason: "buffered-audio-error",
                audioBytes: audioSnapshot.audioData.count,
                elapsedSeconds: latencyTrace.elapsed
            )
            logger.error("commitBufferedRollingAudioSnapshot failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func discardDeferredAudioFile(_ audioFileReadyTask: Task<Void, Error>, at url: URL) {
        audioFileReadyTask.cancel()
        Task.detached(priority: .utility) {
            _ = try? await audioFileReadyTask.value
            try? FileManager.default.removeItem(at: url)
        }
    }

    func prepareQuickReleaseContext(powerModeId: UUID? = nil) {
        preparedQuickReleaseContext = PreparedQuickReleaseContext(
            powerModeId: powerModeId,
            powerModeTask: Task { @MainActor in
                await ActiveWindowService.shared.resolveConfiguration(
                    powerModeId: powerModeId,
                    updateCurrentApplication: false
                )
            },
            cursorContextTask: Task { @MainActor in
                CursorTextContextReader.textBeforeCursor()
            },
            pasteContextTask: Task { @MainActor in
                CursorPaster.preparePasteContext()
            }
        )
    }

    func discardPreparedQuickReleaseContext() {
        preparedQuickReleaseContext = nil
    }

    private func takePreparedQuickReleaseContext(powerModeId: UUID?) -> PreparedQuickReleaseContext? {
        defer { preparedQuickReleaseContext = nil }
        guard let preparedQuickReleaseContext,
              preparedQuickReleaseContext.matches(powerModeId: powerModeId) else {
            return nil
        }
        return preparedQuickReleaseContext
    }

    private func applyPowerModeConfiguration(
        powerModeId: UUID?,
        preparedContext: PreparedQuickReleaseContext?
    ) async {
        if let preparedContext {
            let config = await preparedContext.powerModeTask.value
            await ActiveWindowService.shared.applyResolvedConfiguration(config)
            return
        }

        await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)
    }

    private func startPowerModeConfigurationApply(
        powerModeId: UUID?,
        preparedContext: PreparedQuickReleaseContext?
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await applyPowerModeConfiguration(powerModeId: powerModeId, preparedContext: preparedContext)
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            response(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    response(granted)
                }
            }
        case .denied, .restricted:
            response(false)
        @unknown default:
            response(false)
        }
    }

    // MARK: - Pipeline Dispatch

    private func runPipeline(
        on transcription: Transcription,
        audioURL: URL,
        audioFileReadyTask: Task<Void, Error>? = nil,
        latencyTrace: TranscriptionLatencyTrace? = nil,
        deferHistoryInsertUntilSave: Bool = false,
        powerModeApplyTask: Task<Void, Never>? = nil,
        preparedCursorTextContext: Task<String?, Never>? = nil,
        preparedPasteContext: Task<CursorPaster.PreparedPasteContext?, Never>? = nil
    ) async {
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            if deferHistoryInsertUntilSave {
                modelContext.insert(transcription)
            }
            transcription.markAsFailedTranscription(reason: VoiceInkModelManagementPresentation.noModelSelectedText)
            try? modelContext.save()
            recordingState = .idle
            return
        }

        let session = currentSession
        let transcriptionID = transcription.id
        activePipelineTranscriptionID = transcriptionID

        let deferredPipelineWork = await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
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
            },
            audioFileReadyTask: audioFileReadyTask,
            latencyTrace: latencyTrace,
            deferHistoryInsertUntilSave: deferHistoryInsertUntilSave,
            powerModeApplyTask: powerModeApplyTask,
            preparedCursorTextContext: preparedCursorTextContext,
            preparedPasteContext: preparedPasteContext
        )
        recordRollingPreloadTiming(latencyTrace, stage: .pipelineReturned)
        if let latencyTrace, latencyTrace.isRollingPreloadQuickRelease {
            logger.notice("Latency trace pipeline returned operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
        }

        let didFinishActivePipeline = activePipelineTranscriptionID == transcriptionID
        let shouldDeferRecorderSessionFinish = latencyTrace?.isRollingPreloadQuickRelease == true
        if didFinishActivePipeline {
            if !shouldDeferRecorderSessionFinish {
                await finishRecorderSession()
            }
            // Keep successful local STT resources warm for the next recording/preload.
            // Cancellation, reset, and Power Mode model changes still release them.
            activePipelineTranscriptionID = nil
            currentSession = nil
            recordedFile = nil
            shouldCancelRecording = false
            rollingBufferPreloadCoordinator.recordingSessionDidFinish()
        }
        canceledPipelineTranscriptionIDs.remove(transcriptionID)

        if didFinishActivePipeline &&
            (recordingState == .transcribing || recordingState == .enhancing || recordingState == .busy) {
            recordingState = .idle
        }
        if didFinishActivePipeline {
            recordRollingPreloadTiming(latencyTrace, stage: .idle)
            if let latencyTrace, latencyTrace.isRollingPreloadQuickRelease {
                logger.notice("Latency trace engine idle operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
            }
        }

        if didFinishActivePipeline, shouldDeferRecorderSessionFinish {
            Task { @MainActor in
                await self.finishRecorderSession()
                self.recordRollingPreloadTiming(latencyTrace, stage: .sessionFinished)
                if let latencyTrace, latencyTrace.isRollingPreloadQuickRelease {
                    self.logger.notice("Latency trace recorder session finished operation=\(latencyTrace.operation, privacy: .public) elapsed=\(latencyTrace.elapsed, format: .fixed(precision: 3), privacy: .public)s")
                }
            }
        }

        if let deferredPipelineWork {
            Task { @MainActor in
                deferredPipelineWork()
            }
        }
    }

    private func recordRollingPreloadTiming(
        _ latencyTrace: TranscriptionLatencyTrace?,
        stage: RollingBufferQuickReleaseTimingStage
    ) {
        guard let latencyTrace, latencyTrace.isRollingPreloadQuickRelease else { return }
        RollingBufferPreloadRuntimeDiagnostics.shared.recordQuickReleaseTiming(
            stage: stage,
            elapsedSeconds: latencyTrace.elapsed
        )
    }

    // MARK: - Cancellation

    func cancelRecording() async {
        logger.notice("cancelRecording called – state=\(String(describing: self.recordingState), privacy: .public)")
        stopRequestedDuringStart = false

        let shouldFinishSessionImmediately: Bool
        switch recordingState {
        case .starting, .recording:
            requestRecordingCancellation()
            await finishActiveRecorderCancellation()
            shouldFinishSessionImmediately = true
        case .transcribing, .enhancing:
            requestRecordingCancellation()
            partialTranscript = ""
            recordingState = .idle
            shouldFinishSessionImmediately = false
        case .idle, .busy:
            partialTranscript = ""
            shouldCancelRecording = false
            recordingState = .idle
            shouldFinishSessionImmediately = true
        }

        if shouldFinishSessionImmediately {
            await finishRecorderSession()
        }
    }

    func resetRecordingSession() async {
        cancelCurrentSession()
        activeRecordingStartID = nil
        activePipelineTranscriptionID = nil
        canceledPipelineTranscriptionIDs.removeAll()
        shouldCancelRecording = false
        stopRequestedDuringStart = false
        partialTranscript = ""
        await recorder.stopRecording()
        recordedFile = nil
        recordingState = .idle
        rollingBufferPreloadCoordinator.recordingSessionDidFinish()
        await cleanupResources()
        await finishRecorderSession()
    }

    private func requestRecordingCancellation() {
        shouldCancelRecording = true

        if (recordingState == .transcribing || recordingState == .enhancing),
           let activePipelineTranscriptionID {
            canceledPipelineTranscriptionIDs.insert(activePipelineTranscriptionID)
        }

        cancelCurrentSession()
    }

    private func finishActiveRecorderCancellation() async {
        activeRecordingStartID = nil
        stopRequestedDuringStart = false
        await recorder.stopRecording()
        await saveCanceledRecording()
        recordedFile = nil
        partialTranscript = ""
        recordingState = .idle
        rollingBufferPreloadCoordinator.recordingSessionDidFinish()
        await cleanupResources()
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
        let powerModeMetadata = currentPowerModeMetadata()

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
        let powerModeMetadata = currentPowerModeMetadata()

        let draft = VoiceInkRecordingTranscriptionDraft.canceled(
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji
        )
        return Transcription(recordingDraft: draft)
    }

    private func currentPowerModeMetadata() -> (name: String?, emoji: String?) {
        guard let powerMode = PowerModeManager.shared.activeConfiguration,
              powerMode.isEnabled else {
            return (nil, nil)
        }

        return (powerMode.name, powerMode.emoji)
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
        rollingBufferPreloadCoordinator.cancelUnclaimedPreload(reason: "engine-session-cancel")
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
        await restorePowerModeIfNeeded()
    }

    private func restorePowerModeIfNeeded() async {
        guard !VoiceInkPowerModePreference.shouldPersistConfiguredPreferences() else { return }

        await PowerModeSessionManager.shared.endSession()
        PowerModeManager.shared.setActiveConfiguration(nil)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppSettingsDidChange),
            name: .AppSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRollingBufferPreloadPartialTranscript(_:)),
            name: .rollingBufferPreloadPartialTranscript,
            object: nil
        )
    }

    @objc func handleLicenseStatusChanged() {
        pipeline.licenseViewModel = LicenseViewModel()
    }

    @objc func handleAppSettingsDidChange() {
        rollingBufferPreloadCoordinator.settingsDidChange()
        Task { [weak self] in
            await self?.recorder.reloadRollingBufferSettings()
        }
    }

    @objc func handleRollingBufferPreloadPartialTranscript(_ notification: Notification) {
        guard recordingState.acceptsRollingBufferPreloadPreview,
              let text = notification.userInfo?["text"] as? String else { return }
        partialTranscript = text
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
