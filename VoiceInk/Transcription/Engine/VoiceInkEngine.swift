import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os
import VoiceInkCore
import VoiceInkQwen
import VoiceInkLip

enum RecordingCancellation {
    /// Esc, the cancel button, or dismissing the recorder: keep a canceled row and any captured audio.
    case userRequested
    /// The recording shortcut turned out to be part of a larger key chord: leave no row and no audio.
    case accidentalShortcut
    /// Settings, shutdown, or reset ended capture: retain voice audio, without creating camera-only history.
    case sessionEnded

    func retainsCapturedHistory(audioURL: URL?) -> Bool {
        switch self {
        case .userRequested: return true
        case .accidentalShortcut: return false
        case .sessionEnded: return audioURL != nil
        }
    }
}

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    @Published var recordingState: VoiceInkRecordingState = .idle
    @Published private(set) var dictationMode = VoiceInkLipDictationPreference.mode(in: .standard)
    var partialTranscript = ""
    private(set) var currentSession: TranscriptionSession?
    private weak var qwenRecordingSession: (any TranscriptionSession)?
    private var qwenRecordingModelName: String?

    @MainActor private final class Recording {
        let id = UUID()
        let mode: VoiceInkDictationMode
        let traceToken: VoiceInkLatencyTrace.Token?
        let recorderUISessionID: UUID?
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
        var cancellation: RecordingCancellation?
        // Retain a deleted reservation until drain so later cancellation cannot recreate its row.
        var cancellationTranscription: Transcription?
        var failure: Error?
        var captureStartedAt: Date?
        var captureEndedAt: Date?

        init(mode: VoiceInkDictationMode, traceToken: VoiceInkLatencyTrace.Token?, recorderUISessionID: UUID?) {
            self.mode = mode
            self.traceToken = traceToken
            self.recorderUISessionID = recorderUISessionID
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
    private(set) var recordedFile: URL?
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

    #if DEBUG
    var recordingCancellationForTesting: RecordingCancellation? { activeRecording?.cancellation }

    func installCapturedRecordingForTesting(
        audioURL: URL?, model: (any TranscriptionModel)?, session: TranscriptionSession?, mode: VoiceInkDictationMode
    ) {
        precondition(activeRecording == nil)
        let recording = Recording(mode: mode, traceToken: nil, recorderUISessionID: recorderUIManager?.recorderSessionID)
        recording.audioURL = audioURL
        recording.model = model
        recording.audioSession = session
        recording.inputsStarted = true
        recording.captureStartedAt = Date()
        activeRecording = recording
        dictationMode = mode
        recordedFile = audioURL
        currentSession = session
        if let session, let model { trackQwenRecordingSession(session, model: model) }
        recordingState = .recording
    }
    #endif

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
                    catch { await cancelAndDrain(recording, cancellation: .sessionEnded) }
                }
                return
            } else if recordingState.isActivelyRecording {
                recordingState = .transcribing
                let work = Task { await self.stopRecordingAndRunPipeline(recording) }
                recording.work = work
                await work.value
                return
            } else {
                await cancelAndDrain(recording, cancellation: .userRequested)
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

        let recording = Recording(
            mode: mode, traceToken: traceToken, recorderUISessionID: recorderUIManager?.recorderSessionID
        )
        recording.model = mode.usesMicrophone ? transcriptionModelManager.currentTranscriptionModel : nil
        activeRecording = recording
        dictationMode = mode
        partialTranscript = ""
        recordedFile = nil
        recordingState = .starting
        let work = Task { await self.startRecording(recording, powerModeId: powerModeId) }
        recording.work = work
        await work.value
    }

    private func checkRecording(_ recording: Recording) throws {
        try Task.checkCancellation()
        guard activeRecording === recording, recording.cancellation == nil, recording.failure == nil, !isShuttingDown else {
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
                            guard let self, self.activeRecording === recording, recording.cancellation == nil else { return }
                            if let cameraError = error as? LipCaptureError,
                               case .recordingLimitReached = cameraError {
                                if self.recordingState == .starting {
                                    recording.stopRequested = true
                                    if recording.inputsStarted {
                                        do { try await self.stopCapture(recording) }
                                        catch { await self.cancelAndDrain(recording, cancellation: .sessionEnded) }
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
                            await self.cancelAndDrain(recording, cancellation: .sessionEnded)
                            guard self.activeRecording == nil else { return }
                            await self.recorderUIManager?.dismissRecorderSession(recording.recorderUISessionID)
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
            recording.captureStartedAt = Date()
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
                guard let self, self.activeRecording === recording, recording.cancellation == nil else { return }
                if let model = recording.model {
                    await self.warmRecordingModel(model, recording: recording)
                }
                guard self.activeRecording === recording, recording.cancellation == nil, !Task.isCancelled else { return }
                await self.enhancementService?.captureScreenContext()
            }
            if recording.stopRequested {
                await stopRecordingAndRunPipeline(recording)
            }
        } catch {
            audioRelay.clear()
            if let url = recording.audioURL { discardUnreferencedRecordedAudio(at: url) }
            guard activeRecording === recording else { return }
            recording.failure = error
            logger.error("recording.start_failed id=\(recording.id.uuidString, privacy: .public) type=\(String(describing: type(of: error)), privacy: .public)")
            if !(error is CancellationError) {
                NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
            }
            await finishRecording(recording)
            guard activeRecording == nil else { return }
            await recorderUIManager?.dismissRecorderSession(recording.recorderUISessionID)
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
                guard let self, self.activeRecording === recording, recording.cancellation == nil,
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
            if recording.audioSession === session { recording.audioSession = nil }
            if activeRecording === recording, currentSession === session { currentSession = nil }
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
            guard activeRecording === recording, recording.cancellation == nil else { return nil }
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
        recording.captureEndedAt = Date()
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
        guard activeRecording === recording, recording.cancellation == nil else { return }
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
                    guard let self, self.activeRecording === recording, recording.cancellation == nil else { return }
                    self.recordingState = state
                },
                cancellation: { [weak self] in
                    guard let self else { return .accidentalShortcut }
                    guard self.activeRecording === recording, !self.isShuttingDown else {
                        return recording.cancellation ?? .accidentalShortcut
                    }
                    return recording.cancellation
                },
                onCancel: { [weak self] in
                    recording.audioRecognition?.cancel()
                    recording.lipRecognition?.cancel()
                    recording.audioSession?.cancel()
                    guard let self, self.activeRecording === recording else { return }
                    self.currentSession = nil
                },
                onDismiss: { [weak self] in
                    guard let self, self.activeRecording === recording, recording.cancellation == nil else { return }
                    await self.recorderUIManager?.dismissRecorderSession(recording.recorderUISessionID)
                }
            )
        } catch {
            guard activeRecording === recording else { return }
            if !(error is CancellationError), recording.cancellation == nil {
                NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
            }
            recording.failure = error
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

    private func requestCancellation(_ recording: Recording, cancellation: RecordingCancellation) {
        guard activeRecording === recording else { return }
        switch (recording.cancellation, cancellation) {
        case (.some(.accidentalShortcut), _), (.some(.userRequested), .sessionEnded): break
        default: recording.cancellation = cancellation
        }
        recording.stopRequested = false
        if recording.captureEndedAt == nil { recording.captureEndedAt = Date() }
        reserveCanceledRecording(recording)
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

    private func reserveCanceledRecording(_ recording: Recording) {
        guard activeRecording === recording,
              recording.cancellation?.retainsCapturedHistory(audioURL: recording.audioURL) == true,
              recording.transcription == nil, recording.cancellationTranscription == nil,
              recording.audioURL != nil || (recording.mode == .lips && recording.inputsStarted) else { return }
        let transcription = makeRecordingTranscription(
            audioURL: recording.audioURL, duration: recording.clip?.duration ?? 0,
            modelDisplayName: recording.modelDisplayName, canceled: true
        )
        // A failed startup may resume at the first await; pending inserts already own their audio.
        modelContext.insert(transcription)
        recording.cancellationTranscription = transcription
    }

    private func finishCancellationHistory(_ recording: Recording) async -> Bool {
        guard activeRecording === recording else { return false }
        guard let transcription = recording.cancellationTranscription else { return true }
        guard !transcription.isDeleted, transcription.modelContext != nil else {
            return true
        }
        let hasCapture = recording.audioURL.map { FileManager.default.fileExists(atPath: $0.path) }
            ?? recording.inputsStarted
        guard recording.cancellation?.retainsCapturedHistory(audioURL: recording.audioURL) == true, hasCapture else {
            return discardCancellationHistory(recording)
        }
        var duration = recording.clip?.duration ?? recording.captureStartedAt.map {
            max(0, (recording.captureEndedAt ?? Date()).timeIntervalSince($0))
        } ?? 0
        if let url = recording.audioURL {
            let result = await AudioFileMetadata.tracedDuration(
                for: url, executorName: "engine.cancel_audio_duration", latencyTraceToken: recording.traceToken
            )
            VoiceInkLatencyTrace.shared.executorResumed(result.executorCheckpoint)
            guard activeRecording === recording else { return false }
            duration = result.seconds
        }
        guard !transcription.isDeleted, transcription.modelContext != nil else {
            return true
        }
        guard recording.cancellation?.retainsCapturedHistory(audioURL: recording.audioURL) == true else {
            return discardCancellationHistory(recording)
        }
        transcription.duration = duration
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            return true
        } catch {
            logger.error("Failed to save canceled recording: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func discardCancellationHistory(_ recording: Recording) -> Bool {
        guard let transcription = recording.cancellationTranscription else { return true }
        guard !transcription.isDeleted, transcription.modelContext != nil else {
            return true
        }
        modelContext.delete(transcription)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            return true
        } catch {
            logger.error("Failed to discard canceled recording: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func discardUnreferencedRecordedAudio(at url: URL) {
        let storedURL: String? = url.absoluteString
        let referencing = FetchDescriptor<Transcription>(predicate: #Predicate { $0.audioFileURL == storedURL })
        guard (try? modelContext.fetchCount(referencing)) == 0 else { return }
        VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(for: storedURL) { message in
            logger.error("\(message, privacy: .public)")
        }
    }

    private func cancelAndDrain(_ recording: Recording, cancellation: RecordingCancellation) async {
        guard activeRecording === recording else { return }
        requestCancellation(recording, cancellation: cancellation)
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
        reserveCanceledRecording(recording)
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
        let canDiscardAudio = await finishCancellationHistory(recording)
        guard activeRecording === recording else { return }
        if canDiscardAudio, recording.cancellation == .accidentalShortcut || recording.failure != nil,
           let url = recording.audioURL { discardUnreferencedRecordedAudio(at: url) }
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        await finishRecorderSession(applicationScope: .init(dictationMode: recording.mode))
        guard activeRecording === recording else { return }
        if recording.cancellation != nil || recording.failure != nil {
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
        partialTranscript = ""
        qwenRecordingSession = nil
        qwenRecordingModelName = nil
        recordingState = .idle
        logger.notice("recording.drained id=\(recording.id.uuidString, privacy: .public) canceled=\(recording.cancellation != nil || recording.failure != nil, privacy: .public) cancellation=\(String(describing: recording.cancellation), privacy: .public)")
    }

    func cancelRecording(_ cancellation: RecordingCancellation) async {
        if let recording = activeRecording {
            await cancelAndDrain(recording, cancellation: cancellation)
        } else {
            currentSession?.cancel()
            currentSession = nil
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
        if let recording = activeRecording { await cancelAndDrain(recording, cancellation: .sessionEnded) }
        guard activeRecording == nil else { return }
        currentSession?.cancel()
        currentSession = nil
        await recorder.stopRecording()
        guard activeRecording == nil else { return }
        recordedFile = nil
        partialTranscript = ""
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
        if let recording = activeRecording { requestCancellation(recording, cancellation: .sessionEnded) }
        let task = Task {
            await self.resetTask?.value
            self.inputPolicyTask?.task.cancel()
            await self.inputPolicyTask?.task.value
            if let recording = self.activeRecording { await self.cancelAndDrain(recording, cancellation: .sessionEnded) }
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
            requestCancellation(recording, cancellation: .sessionEnded)
            Task { [weak self] in
                guard let self, self.activeRecording === recording else { return }
                await self.cancelAndDrain(recording, cancellation: .sessionEnded)
                guard self.activeRecording == nil else { return }
                await self.recorderUIManager?.dismissRecorderSession(recording.recorderUISessionID)
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
                guard self.activeRecording === recording, recording.cancellation == nil, !Task.isCancelled else { return }
                if let file = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                    forModelName: model.name, in: self.whisperModelManager.availableModels
                ), self.whisperModelManager.whisperContext == nil {
                    do { try await self.whisperModelManager.loadModel(file) }
                    catch { self.logger.error("Model warmup failed: \(error.localizedDescription, privacy: .public)") }
                }
            },
            loadLocalFluidAudioModel: {
                guard self.activeRecording === recording, recording.cancellation == nil, !Task.isCancelled,
                      let fluidModel = model as? FluidAudioModel else { return }
                try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidModel)
            },
            loadLocalQwenModel: {
                guard self.activeRecording === recording, recording.cancellation == nil, !Task.isCancelled,
                      recording.audioSession is FileTranscriptionSession else { return }
                await self.transcriptionModelManager.awaitQwenRecordingSelection()
                guard self.activeRecording === recording, recording.cancellation == nil, !Task.isCancelled else { return }
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
            requestCancellation(recording, cancellation: .sessionEnded)
            Task { [weak self] in
                guard let self, self.activeRecording === recording else { return }
                await self.cancelAndDrain(recording, cancellation: .sessionEnded)
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
