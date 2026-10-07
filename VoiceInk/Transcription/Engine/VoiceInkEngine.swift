import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?
    private var activeRecordingStartID: UUID?
    private var captureReadiness: CaptureReadiness?
    private var isStoppingCapture = false
    private var isPreparingCaptureModel = false
    private var preparationDeadline: Task<Void, Never>?


    private var activePipelineTranscriptionID: UUID?
    private var canceledPipelineTranscriptionIDs = Set<UUID>()

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

    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceInkEngine")

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

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")

        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
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
        createRecordingsDirectoryIfNeeded()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
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
        guard !isStoppingCapture else { return }

        if recordingState == .starting {
            logger.notice("toggleRecord: cancelling in-flight recording start")
            await cancelRecording()
            return
        }

        if recordingState == .recording {
            activeRecordingStartID = nil
            clearCaptureCallbacks()
            partialTranscript = ""
            recorderUIManager?.showCaptureFeedback(.working)
            recordingState = .transcribing
            isStoppingCapture = true
            await recorder.stopRecording()
            isStoppingCapture = false

            if let recordedFile {
                if !shouldCancelRecording {
                    let transcription = makeRecordingTranscription(
                        for: recordedFile,
                        text: "",
                        duration: 0,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await runPipeline(on: transcription, audioURL: recordedFile)
                } else {
                    await finishActiveRecorderCancellation()
                }
            } else {
                cancelCurrentSession()
                if !shouldCancelRecording {
                    logger.error("❌ No recorded file found after stopping recording")
                    recorderUIManager?.showCaptureFeedback(.failed("Recording could not be saved. Try again."))
                }
                recordingState = .idle
                await cleanupResources()
            }
        } else {
            guard !isPreparingCaptureModel else {
                recorderUIManager?.showCaptureFeedback(.failed("Model setup is still finishing. Try again shortly."))
                await recorderUIManager?.dismissMiniRecorder()
                return
            }
            logger.notice("toggleRecord: entering start-recording branch")
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                recorderUIManager?.showCaptureFeedback(.failed("Choose a transcription model in Settings."))
                NotificationManager.shared.showNotification(title: "No AI Model Selected", type: .error)
                await recorderUIManager?.dismissMiniRecorder()
                return
            }
            activePipelineTranscriptionID = nil
            shouldCancelRecording = false
            partialTranscript = ""

            let startID = UUID()
            activeRecordingStartID = startID
            captureReadiness = CaptureReadiness(activationID: startID)
            recordingState = .starting
            recorderUIManager?.showCaptureFeedback(.starting)
            recorder.onCaptureReady = { [weak self] in
                guard let self, self.activeRecordingStartID == startID else { return }
                self.captureReadiness?.receiveLiveAudio()
                self.confirmListening(startID)
            }
            recorder.onRecordingFailure = { [weak self] message in
                Task { @MainActor in await self?.failCapture(message, startID: startID) }
            }
            requestRecordPermission { [self] granted in
                guard self.activeRecordingStartID == startID else { return }
                if granted {
                    Task { @MainActor [self] in
                        guard self.activeRecordingStartID == startID else { return }
                        self.preparationDeadline?.cancel()
                        self.preparationDeadline = Task { [weak self] in
                            try? await Task.sleep(for: .seconds(15))
                            guard !Task.isCancelled else { return }
                            await self?.failCapture("RJT took too long to get ready. Check your model and try again.", startID: startID)
                        }
                        do {
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
                            self.recorder.onAudioChunk = { data in
                                pendingChunks.withLock { $0.append(data) }
                            }

                            self.recordingState = .starting
                            self.logger.notice("toggleRecord: state=starting, starting audio hardware")

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
                                }
                                return
                            }

                            await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)
                            guard self.activeRecordingStartID == startID, !self.shouldCancelRecording else { return }

                            guard let model = self.transcriptionModelManager.currentTranscriptionModel else {
                                await self.failCapture("Choose a transcription model in Settings.", startID: startID)
                                return
                            }
                            if self.recordingState == .starting {
                                try await self.prepareCaptureModel(model, startID: startID)
                                guard self.activeRecordingStartID == startID, !self.shouldCancelRecording else { return }
                                let session = self.serviceRegistry.createSession(
                                    for: model,
                                    onPartialTranscript: { [weak self] partial in
                                        Task { @MainActor in
                                            guard let self, self.activeRecordingStartID == startID else { return }
                                            self.partialTranscript = partial
                                        }
                                    },
                                    onFailure: { [weak self] _ in
                                        Task { @MainActor in
                                            await self?.failCapture("Streaming connection stopped. Check your network and API key.", startID: startID)
                                        }
                                    }
                                )
                                self.currentSession = session
                                let realCallback = try await session.prepare(model: model)
                                guard self.activeRecordingStartID == startID, !self.shouldCancelRecording else {
                                    session.cancel()
                                    return
                                }
                                self.captureReadiness?.prepare()
                                self.preparationDeadline?.cancel()
                                self.preparationDeadline = nil
                                self.recordingState = .recording
                                self.confirmListening(startID)

                                if let realCallback {
                                    self.recorder.onAudioChunk = realCallback
                                    let buffered = pendingChunks.withLock { chunks -> [Data] in
                                        let result = chunks
                                        chunks.removeAll()
                                        return result
                                    }
                                    for chunk in buffered { realCallback(chunk) }
                                } else {
                                    self.recorder.onAudioChunk = nil
                                    pendingChunks.withLock { $0.removeAll() }
                                }
                            }

                            Task { @MainActor [weak self] in
                                guard let self, self.activeRecordingStartID == startID else { return }

                                if let enhancementService = self.enhancementService {
                                    enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                    guard self.activeRecordingStartID == startID else {
                                        enhancementService.clearCapturedContexts()
                                        return
                                    }
                                }
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                            let message: String
                            if let cloudError = error as? CloudTranscriptionError, case .missingAPIKey = cloudError {
                                message = "Add your model API key in Settings."
                            } else if let modelError = error as? VoiceInkEngineError, case .modelLoadFailed = modelError {
                                message = "Model could not load. Select or download a model in Settings."
                            } else {
                                message = "RJT could not get ready. Check your microphone and model."
                            }
                            await self.failCapture(message, startID: startID)
                        }
                    }
                } else {
                    recorderUIManager?.showCaptureFeedback(.failed("Microphone permission required. Open Settings to grant access."))
                    activeRecordingStartID = nil
                    clearCaptureCallbacks()
                    recordingState = .idle
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
                    }
                }
            }
        }
    }

    func confirmPreRollReadiness() async {
        guard recordingState == .idle, recorder.preRollIsHealthy,
              let model = transcriptionModelManager.currentTranscriptionModel else {
            if recordingState == .idle, transcriptionModelManager.currentTranscriptionModel == nil {
                recorderUIManager?.showCaptureFeedback(.failed("Choose a transcription model before speaking."))
            }
            return
        }
        do {
            try validateCaptureConfiguration(model)
            if model.provider == .nativeApple { try await serviceRegistry.nativeAppleTranscriptionService.prepare(model: model) }
            guard recordingState == .idle, recorder.preRollIsHealthy,
                  transcriptionModelManager.currentTranscriptionModel?.id == model.id else { return }
            recorderUIManager?.showCaptureFeedback(.ready)
        } catch {
            guard recordingState == .idle, recorder.preRollIsHealthy else { return }
            recorderUIManager?.showCaptureFeedback(.failed("Pre-roll is capturing, but your model needs setup. Check Settings before speaking."))
        }
    }

    private func validateCaptureConfiguration(_ model: any TranscriptionModel) throws {
        switch model.provider {
        case .whisper:
            guard let file = whisperModelManager.availableModels.first(where: { $0.name == model.name }),
                  FileManager.default.fileExists(atPath: file.url.path) else { throw VoiceInkEngineError.modelLoadFailed }
        case .custom:
            guard let custom = model as? CustomCloudModel,
                  let endpoint = URL(string: custom.apiEndpoint),
                  ["http", "https"].contains(endpoint.scheme ?? ""), endpoint.host != nil,
                  !custom.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceInkEngineError.transcriptionFailed
            }
        case .nativeApple, .fluidAudio:
            break
        default:
            guard let provider = CloudProviderRegistry.provider(for: model.provider),
                  APIKeyManager.shared.hasAPIKey(forProvider: provider.providerKey) else {
                throw CloudTranscriptionError.missingAPIKey
            }
        }
    }

    private func prepareCaptureModel(_ model: any TranscriptionModel, startID: UUID) async throws {
        isPreparingCaptureModel = true
        defer { isPreparingCaptureModel = false }
        try validateCaptureConfiguration(model)
        switch model.provider {
        case .whisper:
            guard let file = whisperModelManager.availableModels.first(where: { $0.name == model.name }) else {
                throw VoiceInkEngineError.modelLoadFailed
            }
            if whisperModelManager.loadedWhisperModel?.name != model.name {
                await whisperModelManager.cleanupResources()
                guard activeRecordingStartID == startID else { throw CancellationError() }
            }
            try await whisperModelManager.loadModel(file)
        case .fluidAudio:
            guard let model = model as? FluidAudioModel else { throw VoiceInkEngineError.modelLoadFailed }
            try await serviceRegistry.fluidAudioTranscriptionService.loadModel(for: model)
        case .nativeApple:
            try await serviceRegistry.nativeAppleTranscriptionService.prepare(model: model)
        default:
            break
        }
    }

    private func confirmListening(_ startID: UUID) {
        guard activeRecordingStartID == startID, captureReadiness?.activationID == startID,
              captureReadiness?.isReady == true, recordingState == .recording else { return }
        recorderUIManager?.showCaptureFeedback(.listening)
    }

    private func clearCaptureCallbacks() {
        preparationDeadline?.cancel()
        preparationDeadline = nil
        recorder.onCaptureReady = nil
        recorder.onRecordingFailure = nil
        captureReadiness = nil
    }

    private func failCapture(_ message: String, startID: UUID) async {
        guard activeRecordingStartID == startID else { return }
        guard !isStoppingCapture else { return }
        isStoppingCapture = true
        defer { isStoppingCapture = false }
        activeRecordingStartID = nil
        clearCaptureCallbacks()
        cancelCurrentSession()
        recorderUIManager?.showCaptureFeedback(.failed(message))
        await recorder.stopRecording()
        await saveFailedRecording(message: message)
        recordedFile = nil
        recordingState = .idle
        await recorderUIManager?.dismissMiniRecorder()
    }

    private func saveFailedRecording(message: String) async {
        guard let recordedFile,
              let attributes = try? FileManager.default.attributesOfItem(atPath: recordedFile.path),
              let bytes = attributes[.size] as? NSNumber, bytes.intValue > 44 else { return }
        let duration = await AudioFileMetadata.duration(for: recordedFile)
        let transcription = makeRecordingTranscription(for: recordedFile, text: message,
                                                       duration: duration, transcriptionStatus: .failed)
        modelContext.insert(transcription)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save interrupted recording: \(error.localizedDescription, privacy: .public)")
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

    private func runPipeline(on transcription: Transcription, audioURL: URL) async {
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.text = "Transcription Failed: No model selected"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            recordingState = .idle
            cancelCurrentSession()
            recorderUIManager?.showCaptureFeedback(.failed("Choose a transcription model in Settings."))
            await recorderUIManager?.dismissMiniRecorder()
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
            onStateChange: { [weak self] state in
                guard let self, self.activePipelineTranscriptionID == transcriptionID else { return }
                self.recordingState = state
                if state == .transcribing || state == .enhancing { self.recorderUIManager?.showCaptureFeedback(.working) }
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
            if transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue {
                recorderUIManager?.showCaptureFeedback(.failed("Transcription failed. Retry from History."))
            } else {
                recorderUIManager?.showCaptureFeedback(.hidden)
            }
        }
        if didFinishActivePipeline {
            await finishRecorderSession()
            await cleanupResources()
            activePipelineTranscriptionID = nil
            currentSession = nil
            recordedFile = nil
            shouldCancelRecording = false
        }
        canceledPipelineTranscriptionIDs.remove(transcriptionID)

        if didFinishActivePipeline &&
            (recordingState == .transcribing || recordingState == .enhancing || recordingState == .busy) {
            recordingState = .idle
        }
    }

    // MARK: - Cancellation

    func cancelRecording() async {
        logger.notice("cancelRecording called – state=\(String(describing: self.recordingState), privacy: .public)")
        guard !isStoppingCapture else { return }
        isStoppingCapture = true
        defer { isStoppingCapture = false }
        clearCaptureCallbacks()
        recorderUIManager?.showCaptureFeedback(.hidden)

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
        guard !isStoppingCapture else { return }
        isStoppingCapture = true
        defer { isStoppingCapture = false }
        cancelCurrentSession()
        clearCaptureCallbacks()
        recorderUIManager?.showCaptureFeedback(.hidden)
        activeRecordingStartID = nil
        activePipelineTranscriptionID = nil
        canceledPipelineTranscriptionIDs.removeAll()
        shouldCancelRecording = false
        partialTranscript = ""
        await recorder.stopRecording()
        recordedFile = nil
        recordingState = .idle
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
        await recorder.stopRecording()
        await saveCanceledRecording()
        recordedFile = nil
        partialTranscript = ""
        recordingState = .idle
        await cleanupResources()
    }

    private func saveCanceledRecording() async {
        guard let recordedFile,
              FileManager.default.fileExists(atPath: recordedFile.path)
        else { return }

        let duration = await AudioFileMetadata.duration(for: recordedFile)
        let transcription = makeRecordingTranscription(
            for: recordedFile,
            text: Transcription.canceledTranscriptionText,
            duration: duration,
            transcriptionStatus: .canceled
        )

        modelContext.insert(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save canceled recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeRecordingTranscription(
        for audioURL: URL,
        text: String,
        duration: TimeInterval,
        transcriptionStatus: TranscriptionStatus
    ) -> Transcription {
        let powerModeMetadata = currentPowerModeMetadata()

        return Transcription(
            text: text,
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: transcriptionModelManager.currentTranscriptionModel?.displayName,
            powerModeName: powerModeMetadata.name,
            powerModeEmoji: powerModeMetadata.emoji,
            transcriptionStatus: transcriptionStatus
        )
    }

    private func currentPowerModeMetadata() -> (name: String?, emoji: String?) {
        guard let powerMode = PowerModeManager.shared.currentActiveConfiguration,
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
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
        await restorePowerModeIfNeeded()
    }

    private func restorePowerModeIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "powerModePersistConfig") else { return }

        await PowerModeSessionManager.shared.endSession()
        PowerModeManager.shared.setActiveConfiguration(nil)
    }

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        activeRecordingStartID = nil
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
            selector: #selector(handlePromptChange),
            name: .promptDidChange,
            object: nil
        )
    }

    @objc func handleLicenseStatusChanged() {
        pipeline.licenseViewModel = LicenseViewModel()
    }

    @objc func handlePromptChange() {
        Task {
            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt")
                ?? whisperModelManager.whisperPrompt.transcriptionPrompt
            if let context = whisperModelManager.whisperContext {
                await context.setPrompt(currentPrompt)
            }
        }
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
