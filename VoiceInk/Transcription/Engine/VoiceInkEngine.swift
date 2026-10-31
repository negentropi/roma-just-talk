import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore
import VoiceInkQwen
import VoiceInkLip

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    @Published var recordingState: VoiceInkRecordingState = .idle
    @Published var shouldCancelRecording = false
    @Published private(set) var dictationMode = VoiceInkLipDictationPreference.mode(in: .standard)
    var partialTranscript = ""
    var currentSession: TranscriptionSession?
    private weak var qwenRecordingSession: (any TranscriptionSession)?
    private var qwenRecordingModelName: String?

    @MainActor private final class Recording {
        let id = UUID()
        let mode: VoiceInkDictationMode
        let traceToken: VoiceInkLatencyTrace.Token?
        var audioURL: URL?
        var model: (any TranscriptionModel)?
        var audioSession: TranscriptionSession?
        var camera: LipCapture?
        var cameraStartup: Task<Void, Error>?
        var cameraStop: Task<LipCaptureClip, Error>?
        var captureStop: Task<Void, Error>?
        var clip: LipCaptureClip?
        var audioRecognition: Task<String, Error>?
        var lipRecognition: Task<String, Error>?
        var powerModeResolution: Task<PowerModeConfig?, Never>?
        var warmup: Task<Void, Never>?
        var work: Task<Void, Never>?
        var teardown: Task<Void, Never>?
        var transcription: Transcription?
        var stopRequested = false
        var inputsStarted = false
        var canceled = false

        init(mode: VoiceInkDictationMode, traceToken: VoiceInkLatencyTrace.Token?) {
            self.mode = mode
            self.traceToken = traceToken
        }

        var modelDisplayName: String {
            switch mode {
            case .voice: return model?.displayName ?? VoiceInkModelManagementPresentation.noModelSelectedText
            case .lips: return LipRuntime.modelDisplayName
            case .voiceAndLips:
                return "\(model?.displayName ?? "Voice") + \(LipRuntime.modelDisplayName)"
            }
        }
    }

    private var activeRecording: Recording?
    var currentDictationMode: VoiceInkDictationMode {
        activeRecording?.mode ?? VoiceInkLipDictationPreference.mode(in: .standard)
    }
    private var inputPolicyTask: (id: UUID, task: Task<Void, Never>)?
    private var shutdownTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var lastLipPreferenceMode = VoiceInkLipDictationPreference.mode(in: .standard)

    let recorder = Recorder()
    var recordedFile: URL?
    let recordingsDirectory: URL
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
        qwenRuntimeResult: Result<QwenRuntime, Error>,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService
        recordingsDirectory = VoiceInkMacOSStorageDirectories.recordingsDirectory
        serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: qwenRuntimeResult,
            ownsQwenRuntime: true
        )
        pipeline = TranscriptionPipeline(modelContext: modelContext, enhancementService: enhancementService)
        super.init()
        if let enhancementService {
            PowerModeSessionManager.shared.configure(engine: self, enhancementService: enhancementService)
        }
        setupNotifications()
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create recordings directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? { enhancementService }

    func prepareDictationInputs() async {
        await applyIdleInputPolicy()
        guard !isShuttingDown, resetTask == nil else { return }
        if activeRecording == nil, VoiceInkLipDictationPreference.mode(in: .standard).usesMicrophone {
            await recorder.startPreRollBuffering()
        }
        guard !isShuttingDown, resetTask == nil else { return }
        await LipDictationManager.shared.refresh()
    }

    func toggleRecord(powerModeId: UUID? = nil) async {
        guard !isShuttingDown, resetTask == nil else { return }
        if let recording = activeRecording {
            if recording.teardown != nil {
                await recording.work?.value
                guard !isShuttingDown, activeRecording == nil else { return }
            } else if recordingState == .starting {
                recording.stopRequested = true
                VoiceInkLatencyTrace.shared.event("engine.stop.deferred_during_start", token: recording.traceToken)
                if recording.inputsStarted {
                    do { try await stopCapture(recording) }
                    catch { await cancelAndDrain(recording) }
                }
                return
            } else if recordingState.isActivelyRecording {
                recordingState = .transcribing
                let work = Task { await self.stopRecordingAndRunPipeline(recording) }
                recording.work = work
                await work.value
                return
            } else {
                await cancelAndDrain(recording)
                return
            }
        }

        await applyIdleInputPolicy()
        guard !isShuttingDown, resetTask == nil else { return }
        // Another shortcut may have entered while the idle input policy drained.
        if activeRecording != nil {
            await toggleRecord(powerModeId: powerModeId)
            return
        }
        let mode = VoiceInkLipDictationPreference.mode(in: .standard)
        let traceToken = VoiceInkLatencyTrace.shared.ensureStarted(
            event: "engine.toggle_requested", details: "mode=\(String(describing: mode))"
        )
        if mode.usesMicrophone, transcriptionModelManager.currentTranscriptionModel == nil {
            NotificationManager.shared.showNotification(
                title: VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.title, type: .error
            )
            await recorderUIManager?.dismissMiniRecorder()
            VoiceInkLatencyTrace.shared.finish(event: "engine.start.no_model", token: traceToken)
            return
        }

        let recording = Recording(mode: mode, traceToken: traceToken)
        recording.model = mode.usesMicrophone ? transcriptionModelManager.currentTranscriptionModel : nil
        activeRecording = recording
        dictationMode = mode
        shouldCancelRecording = false
        partialTranscript = ""
        recordedFile = nil
        recordingState = .starting
        let work = Task { await self.startRecording(recording, powerModeId: powerModeId) }
        recording.work = work
        await work.value
    }

    private func checkRecording(_ recording: Recording) throws {
        try Task.checkCancellation()
        guard activeRecording === recording, !recording.canceled, !isShuttingDown else {
            throw CancellationError()
        }
    }

    private func startRecording(_ recording: Recording, powerModeId: UUID?) async {
        let trace = VoiceInkLatencyTrace.shared
        let token = recording.traceToken
        let audioRelay = RecordingStartupAudioRelay(latencyTraceToken: token)
        do {
            try checkRecording(recording)
            if recording.mode.usesCamera {
                await LipDictationManager.shared.refresh()
                try checkRecording(recording)
                guard LipDictationManager.shared.readiness == .ready else {
                    presentLipSetupRequired()
                    throw CancellationError()
                }
            }
            if recording.mode.usesMicrophone {
                trace.event("engine.permission.request", token: token)
                let granted = await requestRecordPermission(latencyTraceToken: token)
                try checkRecording(recording)
                trace.event("engine.permission.callback", details: "granted=\(granted)", token: token)
                guard granted else {
                    trace.event("engine.permission.denied", token: token)
                    presentMicrophonePermissionRequired()
                    throw CancellationError()
                }
            } else {
                await recorder.setMicrophoneCaptureEnabled(false)
                try checkRecording(recording)
                let microphone = await recorder.microphoneCaptureStatus()
                try checkRecording(recording)
                guard !microphone.isRecording, !microphone.isPreBuffering, !microphone.hasAudioUnit else {
                    throw LipInputError.microphoneStillActive
                }
                logger.notice("lip_only.input_state id=\(recording.id.uuidString, privacy: .public) recording=false pre_roll=false audio_unit=false")
            }

            let plan = VoiceInkMacOSRecordingStartupOrchestrationPolicy.plan(
                powerModeConfigurationCount: PowerModeManager.shared.configurations.count
            )
            if plan.shouldResolvePowerMode {
                recording.powerModeResolution = Task {
                    guard !Task.isCancelled else { return nil }
                    let configuration = await ActiveWindowService.shared.resolveConfiguration(
                        powerModeId: powerModeId, latencyTraceToken: token
                    )
                    return Task.isCancelled ? nil : configuration
                }
            }
            if recording.mode.usesCamera {
                let camera = LipCapture()
                recording.camera = camera
                recording.cameraStartup = Task { [weak self] in
                    try Task.checkCancellation()
                    try await camera.start(sessionID: recording.id) { [weak self] error in
                        Task { @MainActor in
                            guard let self, self.activeRecording === recording, !recording.canceled else { return }
                            if let cameraError = error as? LipCaptureError,
                               case .recordingLimitReached = cameraError {
                                if self.recordingState == .starting {
                                    recording.stopRequested = true
                                    if recording.inputsStarted {
                                        do { try await self.stopCapture(recording) }
                                        catch { await self.cancelAndDrain(recording) }
                                    }
                                } else if self.recordingState.isActivelyRecording {
                                    self.recordingState = .transcribing
                                    let work = Task { await self.stopRecordingAndRunPipeline(recording) }
                                    recording.work = work
                                    await work.value
                                }
                                return
                            }
                            NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
                            await self.cancelAndDrain(recording)
                            guard self.activeRecording == nil else { return }
                            await self.recorderUIManager?.dismissMiniRecorder()
                        }
                    }
                }
            }
            if recording.mode.usesMicrophone {
                let url = VoiceInkStoredAudioFile.recordingFileURL(in: recordingsDirectory)
                recording.audioURL = url
                recordedFile = url
                recorder.onAudioChunk = { audioRelay.handle($0) }
                if plan.shouldPrepareTranscriptionSessionBeforeRecorder, let model = recording.model {
                    try await prepareRecordingTranscriptionSession(for: model, recording: recording, audioRelay: audioRelay)
                    try checkRecording(recording)
                }
                try await recorder.startRecording(toOutputFile: url, latencyTraceToken: token)
                try checkRecording(recording)
            }
            if let cameraStartup = recording.cameraStartup {
                try await cameraStartup.value
                try checkRecording(recording)
            }
            recording.inputsStarted = true
            if recording.stopRequested {
                try await stopCapture(recording)
                try checkRecording(recording)
            }
            if let configuration = recording.powerModeResolution {
                let resolved = await configuration.value
                try checkRecording(recording)
                await PowerModeManager.shared.activateConfiguration(resolved)
                try checkRecording(recording)
                if recording.mode.usesMicrophone {
                    recording.model = transcriptionModelManager.currentTranscriptionModel
                    guard recording.model != nil else { throw VoiceInkEngineError.noTranscriptionModelSelected }
                }
            }
            if recording.mode.usesMicrophone, let model = recording.model, recording.audioSession == nil {
                if recording.stopRequested, model.supportsRecordedFileTranscription {
                    recording.audioSession = await prepareStartupStopStreamingSession(
                        for: model, recording: recording, audioRelay: audioRelay
                    )
                    try checkRecording(recording)
                    currentSession = recording.audioSession
                } else {
                    try await prepareRecordingTranscriptionSession(for: model, recording: recording, audioRelay: audioRelay)
                    try checkRecording(recording)
                }
            }
            try checkRecording(recording)
            recordingState = .recording
            trace.event("engine.state.recording", details: "session=\(recording.id) mode=\(recording.mode)", token: token)
            enhancementService?.captureClipboardContext()
            recording.warmup = Task { [weak self] in
                guard let self, self.activeRecording === recording, !recording.canceled else { return }
                if let model = recording.model {
                    await self.warmRecordingModel(model, recording: recording)
                }
                guard self.activeRecording === recording, !recording.canceled, !Task.isCancelled else { return }
                await self.enhancementService?.captureScreenContext()
            }
            if recording.stopRequested {
                await stopRecordingAndRunPipeline(recording)
            }
        } catch {
            audioRelay.clear()
            guard activeRecording === recording else { return }
            recording.canceled = true
            logger.error("recording.start_failed id=\(recording.id.uuidString, privacy: .public) type=\(String(describing: type(of: error)), privacy: .public)")
            if !(error is CancellationError) {
                NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
            }
            await finishRecording(recording)
            guard activeRecording == nil else { return }
            await recorderUIManager?.dismissMiniRecorder()
            trace.finish(event: "engine.start.failed", token: token)
        }
    }

    private func prepareRecordingTranscriptionSession(
        for model: any TranscriptionModel,
        recording: Recording,
        audioRelay: RecordingStartupAudioRelay
    ) async throws {
        if model.provider == .qwen {
            await transcriptionModelManager.awaitQwenRecordingSelection()
            try checkRecording(recording)
            guard transcriptionModelManager.currentTranscriptionModel?.name == model.name else { throw CancellationError() }
        }
        try checkRecording(recording)
        let session = serviceRegistry.createSession(for: model, onPartialTranscript: { [weak self] text in
            Task { @MainActor in
                guard let self, self.activeRecording === recording, !recording.canceled,
                      self.recordingState.isRecorderCaptureInProgress, recording.captureStop == nil else { return }
                self.partialTranscript = text
            }
        })
        recording.audioSession = session
        currentSession = session
        trackQwenRecordingSession(session, model: model)
        do {
            let callback = try await session.prepare(model: model, latencyTraceToken: recording.traceToken)
            try checkRecording(recording)
            if let callback {
                audioRelay.installSink(callback)
                recorder.onAudioChunk = callback
            } else {
                audioRelay.clear()
                recorder.onAudioChunk = nil
            }
        } catch {
            session.cancel()
            if activeRecording === recording {
                recording.audioSession = nil
                currentSession = nil
            }
            throw error
        }
    }

    private func prepareStartupStopStreamingSession(
        for model: any TranscriptionModel,
        recording: Recording,
        audioRelay: RecordingStartupAudioRelay
    ) async -> TranscriptionSession? {
        do {
            try await prepareRecordingTranscriptionSession(for: model, recording: recording, audioRelay: audioRelay)
            return recording.audioSession
        } catch {
            guard activeRecording === recording, !recording.canceled else { return nil }
            audioRelay.clear()
            recorder.onAudioChunk = nil
            logger.error("Startup streaming preparation failed; using recorded audio: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func stopCapture(_ recording: Recording) async throws {
        if let stopped = recording.captureStop {
            try await stopped.value
            try checkRecording(recording)
            return
        }
        try checkRecording(recording)
        let stopped = Task {
            if let camera = recording.camera {
                recording.cameraStop = Task {
                    try await recording.cameraStartup?.value
                    try Task.checkCancellation()
                    return try await camera.stop()
                }
            }
            if recording.mode.usesMicrophone {
                await self.recorder.stopRecording(latencyTraceToken: recording.traceToken)
            }
            try self.checkRecording(recording)
            if let stopped = recording.cameraStop {
                let clip = try await stopped.value
                recording.clip = clip
                try self.checkRecording(recording)
            }
        }
        recording.captureStop = stopped
        try await stopped.value
        try checkRecording(recording)
    }

    private func stopRecordingAndRunPipeline(_ recording: Recording) async {
        guard activeRecording === recording, !recording.canceled else { return }
        recording.stopRequested = false
        partialTranscript = ""
        recordingState = .transcribing
        let token = recording.traceToken
        do {
            try await stopCapture(recording)
            try checkRecording(recording)
            let duration = recording.audioURL == nil ? recording.clip?.duration ?? 0 : 0
            let transcription = makeRecordingTranscription(
                audioURL: recording.audioURL, duration: duration,
                modelDisplayName: recording.modelDisplayName, canceled: false
            )
            recording.transcription = transcription
            modelContext.insert(transcription)
            VoiceInkLatencyTrace.shared.event("pipeline.dispatch", details: "session=\(recording.id)", token: token)
            await pipeline.run(
                transcription: transcription,
                modelDisplayName: recording.modelDisplayName,
                recognize: { try await self.recognize(recording) },
                captureDuration: {
                    guard let url = recording.audioURL else { return recording.clip?.duration ?? 0 }
                    let duration = await AudioFileMetadata.tracedDuration(
                        for: url, executorName: "pipeline.audio_duration", latencyTraceToken: token
                    )
                    VoiceInkLatencyTrace.shared.executorResumed(duration.executorCheckpoint)
                    return duration.seconds
                },
                latencyTraceToken: token,
                onStateChange: { [weak self] state in
                    guard let self, self.activeRecording === recording, !recording.canceled else { return }
                    self.recordingState = state
                },
                shouldCancel: { [weak self] in
                    guard let self else { return true }
                    return self.activeRecording !== recording || recording.canceled || self.isShuttingDown
                },
                onCancel: { [weak self] in
                    recording.audioRecognition?.cancel()
                    recording.lipRecognition?.cancel()
                    recording.audioSession?.cancel()
                    guard let self, self.activeRecording === recording else { return }
                    self.currentSession = nil
                },
                onDismiss: { [weak self] in
                    guard let self, self.activeRecording === recording, !recording.canceled else { return }
                    await self.recorderUIManager?.dismissMiniRecorder()
                }
            )
        } catch {
            guard activeRecording === recording else { return }
            if !(error is CancellationError), !recording.canceled {
                NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
            }
            recording.canceled = true
        }
        await finishRecording(recording)
    }

    private func recognize(_ recording: Recording) async throws -> String {
        try checkRecording(recording)
        if let audioURL = recording.audioURL, let model = recording.model {
            let session = recording.audioSession
            recording.audioRecognition = Task {
                try Task.checkCancellation()
                if let session { return try await session.transcribe(audioURL: audioURL) }
                return try await self.serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
        }
        if let clip = recording.clip {
            recording.lipRecognition = Task {
                try Task.checkCancellation()
                return try await LipDictationManager.shared.transcribe(clip)
            }
        }
        let selection = try await RecordingRecognition.resolve(
            voice: recording.audioRecognition, lips: recording.lipRecognition
        )
        try checkRecording(recording)
        switch selection {
        case .voice(let text):
            logger.notice("recognition.selected id=\(recording.id.uuidString, privacy: .public) source=voice chars=\(text.count, privacy: .public)")
            return text
        case .lips(let text):
            logger.notice("recognition.selected id=\(recording.id.uuidString, privacy: .public) source=lips chars=\(text.count, privacy: .public)")
            return text
        case .none:
            return ""
        }
    }

    private func requestCancellation(_ recording: Recording) {
        guard activeRecording === recording else { return }
        recording.canceled = true
        recording.stopRequested = false
        shouldCancelRecording = true
        recording.powerModeResolution?.cancel()
        recording.warmup?.cancel()
        recording.cameraStartup?.cancel()
        recording.cameraStop?.cancel()
        recording.captureStop?.cancel()
        recording.audioRecognition?.cancel()
        recording.lipRecognition?.cancel()
        recording.audioSession?.cancel()
        recording.work?.cancel()
    }

    private func cancelAndDrain(_ recording: Recording) async {
        guard activeRecording === recording else { return }
        requestCancellation(recording)
        // The owner task may still be preparing hardware or saving its canceled record.
        await recording.work?.value
        await finishRecording(recording)
    }

    private func finishRecording(_ recording: Recording) async {
        if let teardown = recording.teardown {
            await teardown.value
            return
        }
        guard activeRecording === recording else { return }
        let teardown = Task { await self.drainRecording(recording) }
        recording.teardown = teardown
        await teardown.value
    }

    private func drainRecording(_ recording: Recording) async {
        guard activeRecording === recording else { return }
        recording.powerModeResolution?.cancel()
        recording.warmup?.cancel()
        recording.cameraStartup?.cancel()
        recording.cameraStop?.cancel()
        recording.captureStop?.cancel()
        recording.audioRecognition?.cancel()
        recording.lipRecognition?.cancel()
        recording.audioSession?.cancel()
        await recording.camera?.cancel()
        _ = await recording.cameraStartup?.result
        _ = await recording.captureStop?.result
        let stopped = await recording.cameraStop?.result
        _ = await recording.audioRecognition?.result
        _ = await recording.lipRecognition?.result
        await recording.powerModeResolution?.value
        await recording.warmup?.value
        guard activeRecording === recording else { return }
        if recording.mode.usesMicrophone {
            await recorder.stopRecording(latencyTraceToken: recording.traceToken)
            guard activeRecording === recording else { return }
        }
        recording.clip?.remove()
        if case .success(let clip) = stopped { clip.remove() }
        if recording.canceled, recording.transcription == nil,
           let url = recording.audioURL, FileManager.default.fileExists(atPath: url.path) {
            let duration = await AudioFileMetadata.tracedDuration(
                for: url, executorName: "engine.cancel_audio_duration", latencyTraceToken: recording.traceToken
            )
            guard activeRecording === recording else { return }
            let transcription = makeRecordingTranscription(
                audioURL: url, duration: duration.seconds,
                modelDisplayName: recording.modelDisplayName, canceled: true
            )
            modelContext.insert(transcription)
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            } catch {
                logger.error("Failed to save canceled recording: \(error.localizedDescription, privacy: .public)")
            }
        }
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        await finishRecorderSession(applicationScope: .init(dictationMode: recording.mode))
        guard activeRecording === recording else { return }
        if recording.canceled {
            await cleanupResources()
            guard activeRecording === recording else { return }
        }
        // Hold the old session until capture and inference drain and the next mode's hardware policy settles.
        while activeRecording === recording {
            let mode = VoiceInkLipDictationPreference.mode(in: .standard)
            await recorder.setMicrophoneCaptureEnabled(!isShuttingDown && mode.usesMicrophone)
            guard activeRecording === recording else { return }
            if mode == VoiceInkLipDictationPreference.mode(in: .standard) {
                dictationMode = mode
                break
            }
        }
        activeRecording = nil
        currentSession = nil
        recordedFile = nil
        shouldCancelRecording = false
        partialTranscript = ""
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        recordingState = .idle
        logger.notice("recording.drained id=\(recording.id.uuidString, privacy: .public) canceled=\(recording.canceled, privacy: .public)")
    }

    func cancelRecording() async {
        if let recording = activeRecording {
            await cancelAndDrain(recording)
        } else {
            currentSession?.cancel()
            currentSession = nil
            shouldCancelRecording = false
            partialTranscript = ""
            recordingState = .idle
            await applyIdleInputPolicy()
        }
    }

    func resetRecordingSession() async {
        if let resetTask { await resetTask.value; return }
        let task = Task { await self.resetRecordingInputs() }
        resetTask = task
        await task.value
        resetTask = nil
    }

    private func resetRecordingInputs() async {
        if let recording = activeRecording { await cancelAndDrain(recording) }
        guard activeRecording == nil else { return }
        currentSession?.cancel()
        currentSession = nil
        await recorder.stopRecording()
        guard activeRecording == nil else { return }
        recordedFile = nil
        partialTranscript = ""
        shouldCancelRecording = false
        recordingState = .idle
        await cleanupResources()
        guard activeRecording == nil else { return }
        await finishRecorderSession()
        guard activeRecording == nil else { return }
        await applyIdleInputPolicy()
    }

    func shutDown() async {
        if let shutdownTask { await shutdownTask.value; return }
        isShuttingDown = true
        let task = Task {
            await self.resetTask?.value
            self.inputPolicyTask?.task.cancel()
            await self.inputPolicyTask?.task.value
            if let recording = self.activeRecording { await self.cancelAndDrain(recording) }
            await self.recorder.setMicrophoneCaptureEnabled(false)
            await LipDictationManager.shared.shutDown()
            await self.cleanupResources()
        }
        shutdownTask = task
        await task.value
    }

    private func applyIdleInputPolicy() async {
        guard activeRecording == nil, !isShuttingDown else { return }
        if let pending = inputPolicyTask {
            await pending.task.value
            return
        }
        let id = UUID()
        let task = Task { @MainActor in
            while !Task.isCancelled, self.activeRecording == nil, !self.isShuttingDown {
                let mode = VoiceInkLipDictationPreference.mode(in: .standard)
                await self.recorder.setMicrophoneCaptureEnabled(mode.usesMicrophone)
                guard self.activeRecording == nil, !self.isShuttingDown else { return }
                if mode == VoiceInkLipDictationPreference.mode(in: .standard) {
                    self.dictationMode = mode
                    return
                }
            }
        }
        inputPolicyTask = (id, task)
        await task.value
        if inputPolicyTask?.id == id { inputPolicyTask = nil }
    }

    @objc private func lipPreferencesChanged() {
        let mode = VoiceInkLipDictationPreference.mode(in: .standard)
        guard mode != lastLipPreferenceMode else { return }
        lastLipPreferenceMode = mode
        if let recording = activeRecording {
            // Master-off takes effect now. Other preference changes apply after this frozen session drains.
            guard recording.mode.usesCamera, !VoiceInkLipDictationPreference.isEnabled() else { return }
            requestCancellation(recording)
            Task { [weak self] in
                guard let self, self.activeRecording === recording else { return }
                await self.cancelAndDrain(recording)
                guard self.activeRecording == nil else { return }
                await self.recorderUIManager?.dismissMiniRecorder()
            }
        } else {
            Task { [weak self] in await self?.applyIdleInputPolicy() }
        }
    }

    private func makeRecordingTranscription(
        audioURL: URL?, duration: TimeInterval, modelDisplayName: String, canceled: Bool
    ) -> Transcription {
        let powerMode = VoiceInkPowerModeTranscriptionMetadata.active(from: PowerModeManager.shared.activeConfiguration)
        let draft: VoiceInkRecordingTranscriptionDraft
        if canceled {
            draft = .canceled(duration: duration, audioFileURL: audioURL?.absoluteString,
                              transcriptionModelName: modelDisplayName,
                              powerModeName: powerMode.name, powerModeEmoji: powerMode.emoji)
        } else {
            draft = .pending(duration: duration, audioFileURL: audioURL?.absoluteString,
                             transcriptionModelName: modelDisplayName,
                             powerModeName: powerMode.name, powerModeEmoji: powerMode.emoji)
        }
        return Transcription(recordingDraft: draft)
    }

    private func requestRecordPermission(latencyTraceToken: VoiceInkLatencyTrace.Token?) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await CaptureAuthorizationDecision.request { decision in
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: decision)
            }
        default: return false
        }
    }

    private func presentMicrophonePermissionRequired() {
        let presentation = VoiceInkRecordingNotificationPresentation.microphonePermissionRequired
        let open: () -> Void = { Task { @MainActor in PermissionGrantCoordinator.openPermissionsAndGrantMicrophone() } }
        NotificationManager.shared.showNotification(
            title: presentation.title, type: .error, duration: presentation.duration,
            onTap: open, actionButton: presentation.actionButtonTitle.map { (label: $0, action: open) }
        )
    }

    private func presentLipSetupRequired() {
        let open: () -> Void = {
            NotificationCenter.default.post(name: .navigateToDestination, object: nil,
                userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .settings))
        }
        NotificationManager.shared.showNotification(
            title: "Set up Lip Dictation in Settings before recording.", type: .error,
            onTap: open, actionButton: (label: "Open Settings", action: open)
        )
    }

    private func finishRecorderSession(applicationScope: VoiceInkPowerModeSessionApplicationScope? = nil) async {
        enhancementService?.clearCapturedContexts()
        await VoiceInkPowerModeRecordingFinishPlan.finishingRecording(
            shouldPersistConfiguredPreferences: VoiceInkPowerModePreference.shouldPersistConfiguredPreferences()
        ).applyRuntimeState(
            endSession: { await PowerModeSessionManager.shared.endSession(applicationScope: applicationScope) },
            clearActiveConfiguration: { PowerModeManager.shared.setActiveConfiguration(nil) }
        )
    }

    func cleanupResources() async {
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
    }

    func trackQwenRecordingSession(_ session: TranscriptionSession, model: any TranscriptionModel) {
        qwenRecordingSession = model.provider == .qwen ? session : nil
        qwenRecordingModelName = model.provider == .qwen ? model.name : nil
    }

    private func warmRecordingModel(_ model: any TranscriptionModel, recording: Recording) async {
        await model.transcriptionRuntimeResourcePlan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                guard self.activeRecording === recording, !recording.canceled, !Task.isCancelled else { return }
                if let file = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                    forModelName: model.name, in: self.whisperModelManager.availableModels
                ), self.whisperModelManager.whisperContext == nil {
                    do { try await self.whisperModelManager.loadModel(file) }
                    catch { self.logger.error("Model warmup failed: \(error.localizedDescription, privacy: .public)") }
                }
            },
            loadLocalFluidAudioModel: {
                guard self.activeRecording === recording, !recording.canceled, !Task.isCancelled,
                      let fluidModel = model as? FluidAudioModel else { return }
                try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidModel)
            },
            loadLocalQwenModel: {
                guard self.activeRecording === recording, !recording.canceled, !Task.isCancelled,
                      recording.audioSession is FileTranscriptionSession else { return }
                await self.transcriptionModelManager.awaitQwenRecordingSelection()
                guard self.activeRecording === recording, !recording.canceled, !Task.isCancelled else { return }
                do { try await self.serviceRegistry.qwenTranscriptionService.loadModel() }
                catch { self.logger.error("Qwen warmup failed: \(error.localizedDescription, privacy: .public)") }
            }
        )
    }

    @objc private func qwenModelSelectionChanged() {
        guard let name = qwenRecordingModelName,
              name != transcriptionModelManager.currentTranscriptionModel?.name,
              let session = qwenRecordingSession else { return }
        // Close a deferred streaming connect before model-selection cleanup can reserve its runtime.
        session.cancel()
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        if let recording = activeRecording {
            requestCancellation(recording)
            Task { [weak self] in
                guard let self, self.activeRecording === recording else { return }
                await self.cancelAndDrain(recording)
            }
        } else {
            currentSession = nil
        }
    }

    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(qwenModelSelectionChanged), name: .didChangeModel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(lipPreferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLicenseStatusChanged), name: .licenseStatusChanged, object: nil)
    }

    @objc func handleLicenseStatusChanged() { pipeline.licenseViewModel = LicenseViewModel() }

    private enum LipInputError: LocalizedError {
        case microphoneStillActive
        var errorDescription: String? {
            "The microphone could not close for lip-only dictation. Try again."
        }
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
