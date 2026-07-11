import SwiftUI
import SwiftData
import AVFoundation
import Combine
import OSLog
import UIKit
import VoiceInkCore

@MainActor
final class RecordingManager: ObservableObject {
    @Published var activeRecordingAlert: VoiceInkRecordingAlertPresentation?
    @Published private(set) var flowState = VoiceInkRecordingFlowState()
    @Published private(set) var livePartialTranscript = ""
    @Published private(set) var liveTranscriptionFallbackMessage: String?
    
    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private let transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    private var durationTimer: Timer?
    private var keyboardDictationRequestID: UUID?
    private var activeStreamingService: IOSStreamingTranscriptionService?
    private var activeStreamingRequest: VoiceInkLiveTranscriptionRequest?
    private var activeRunSettings: VoiceInkTranscriptionRunSettings?
    private var activeStreamingStartedAt: Date?
    private var streamingTranscriptCancellable: AnyCancellable?
    private var streamingStartupTask: Task<Void, Never>?

    private let coordinator = AppGroupCoordinator.shared
    
    var currentAudioLevels: [Float] {
        recorder.levelsHistory
    }
    
    // MARK: - Initialization
    init() {
        // Simplified initialization - no complex keyboard coordination needed
        VoiceInkIOSLogger.recording.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.recordingManagerInitializedMessage, privacy: .public)")
        setupCoordinatorCallbacks()
    }
    
    deinit {
        durationTimer?.invalidate()
    }
    
    // MARK: - Coordinator Setup
    private func setupCoordinatorCallbacks() {
        coordinator.onStopRecordingRequested = {
            VoiceInkIOSLogger.recording.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.keyboardStopRecordingRequestedMessage, privacy: .public)")
            NotificationCenter.default.post(
                name: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName,
                object: nil
            )
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        VoiceInkRecordingStartPolicy.plan(modeCount: settings.modes.count).applyRuntimeState(
            startRecording: startRecordingWithPermissionCheck,
            presentAlert: { [weak self] alert in
                self?.activeRecordingAlert = alert
                self?.failActiveKeyboardDictation(message: alert.message)
            }
        )
    }

    func prepareKeyboardDictationRequest() {
        keyboardDictationRequestID = coordinator.pendingKeyboardDictationRequestID()
    }

    private func startRecordingWithPermissionCheck() {
        VoiceInkRecordingPermissionPolicy.plan(for: checkPermissionStatus()).applyRuntimeState(
            startRecording: { [weak self] in
                self?.proceedToStartRecording()
            },
            presentPermissionDenied: { [weak self] in
                let alert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied
                self?.activeRecordingAlert = alert
                self?.failActiveKeyboardDictation(message: alert.message)
            },
            requestPermission: { [weak self] completion in
                self?.requestPermission { granted in
                    completion(granted)
                }
            }
        )
    }
    
    private func proceedToStartRecording() {
        IOSModelPrewarmService.shared.cancelPrewarm()
        updateFlowState { $0.prepareRecordingStart() }
        coordinator.updateRecordingState(true)

        let runSettings = settings.currentTranscriptionRunSettings()
        activeRunSettings = runSettings
        livePartialTranscript = ""
        liveTranscriptionFallbackMessage = nil

        guard let request = VoiceInkLiveTranscriptionPolicy.request(
            for: runSettings.configuration
        ) else {
            startRecorder(streamingService: nil)
            return
        }

        let service = IOSStreamingTranscriptionService()
        activeStreamingService = service
        activeStreamingRequest = request
        streamingTranscriptCancellable = service.$partialTranscript
            .sink { [weak self] transcript in
                self?.livePartialTranscript = transcript
            }

        streamingStartupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.start(
                    request: request,
                    apiKey: settings.apiKey(for: request.provider),
                    language: runSettings.transcriptionLanguage,
                    customVocabulary: VoiceInkCustomVocabularyTerms.normalized(
                        runSettings.customVocabulary,
                        for: .streamingTranscription(request.provider)
                    )
                )
                try Task.checkCancellation()
                activeStreamingStartedAt = Date()
                streamingStartupTask = nil
                startRecorder(streamingService: service)
            } catch is CancellationError {
                service.cancel()
            } catch {
                service.cancel()
                activeStreamingService = nil
                activeStreamingRequest = nil
                streamingStartupTask = nil
                streamingTranscriptCancellable = nil
                liveTranscriptionFallbackMessage = "Live transcript unavailable. Saved audio will be transcribed after you stop."
                startRecorder(streamingService: nil)
            }
        }
    }

    private func startRecorder(streamingService: IOSStreamingTranscriptionService?) {
        do {
            try recorder.startRecording { data in
                streamingService?.sendAudioChunk(data)
            }
            updateFlowState { $0.completeRecordingStart() }
            startDurationTimer()
        } catch {
            let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(for: error)
            activeRecordingAlert = alert
            updateFlowState { $0.failRecordingStart() }
            coordinator.updateRecordingState(false)
            streamingService?.cancel()
            clearStreamingState()
            failActiveKeyboardDictation(message: alert.message)
        }
    }
    
    func stopRecording(
        modelContext: ModelContext,
        completion: IOSTranscriptionTaskCoordinator.RunCompletion? = nil
    ) {
        let streamingService = activeStreamingService
        let streamingRequest = activeStreamingRequest
        let runSettings = activeRunSettings
        let streamingStartedAt = activeStreamingStartedAt
        let stopPlan = flowState.stopRecordingPlan(
            audioFileURL: recorder.currentRecordingURL?.lastPathComponent
        )

        stopPlan.applyRuntimeState(
            stopRecorder: recorder.stopRecording,
            stopDurationTimer: stopDurationTimer,
            setFlowState: { flowState = $0 },
            updateRecordingState: coordinator.updateRecordingState,
            insertPendingDraft: { [self] draft in
                let note = Transcription(recordingDraft: draft)
                modelContext.insert(note)
                try? modelContext.save()

                let keyboardRequestID = keyboardDictationRequestID
                keyboardDictationRequestID = nil
                transcriptionTasks.start(
                    note: note,
                    keyboardRequestID: keyboardRequestID,
                    persist: { try? modelContext.save() },
                    operation: streamingOperation(
                        service: streamingService,
                        request: streamingRequest,
                        runSettings: runSettings,
                        startedAt: streamingStartedAt
                    ),
                    completion: completion
                )
                recorder.currentRecordingURL = nil
            }
        )

        clearStreamingState(cancelService: false)

        if stopPlan.pendingDraft == nil {
            let message = "The recording file is unavailable."
            failActiveKeyboardDictation(message: message)
            completion?(.failed(reason: message))
        }
    }
    
    func cancelRecording() {
        flowState.cancelRecordingPlan().applyRuntimeState(
            discardRecorder: recorder.discard,
            stopDurationTimer: stopDurationTimer,
            setFlowState: { flowState = $0 },
            updateRecordingState: coordinator.updateRecordingState
        )
        clearStreamingState()
        failActiveKeyboardDictation(message: "Recording canceled.")
    }

    private func streamingOperation(
        service: IOSStreamingTranscriptionService?,
        request: VoiceInkLiveTranscriptionRequest?,
        runSettings: VoiceInkTranscriptionRunSettings?,
        startedAt: Date?
    ) -> IOSTranscriptionTaskCoordinator.RunOperation? {
        guard let service, let request, let runSettings else { return nil }

        return { [settings] note in
            do {
                return try await VoiceInkStreamingFallbackPolicy.run(
                    streamingFailed: false,
                    streaming: {
                        let finalText = try await service.stopAndGetFinalText()
                        return await settings.finalizeStreamingTranscript(
                            finalText,
                            for: note,
                            runSettings: runSettings,
                            transcriptionDuration: startedAt.map {
                                Date().timeIntervalSince($0)
                            }
                        )
                    },
                    cancelStreaming: {
                        service.cancel()
                    },
                    fallback: {
                        await settings.retranscribeStoredAudio(note)
                    }
                )
            } catch is CancellationError {
                return .canceled
            } catch {
                return .failed(reason: VoiceInkErrorDescription.text(for: error))
            }
        }
    }

    private func clearStreamingState(cancelService: Bool = true) {
        streamingStartupTask?.cancel()
        streamingStartupTask = nil
        if cancelService {
            activeStreamingService?.cancel()
        }
        activeStreamingService = nil
        activeStreamingRequest = nil
        activeRunSettings = nil
        activeStreamingStartedAt = nil
        streamingTranscriptCancellable = nil
        livePartialTranscript = ""
        liveTranscriptionFallbackMessage = nil
    }
    
    // MARK: - Permissions
    private func checkPermissionStatus() -> VoiceInkRecordingPermissionStatus {
        IOSMicrophonePermissionAdapter.currentStatus()
    }
    
    private func requestPermission(completion: @escaping (Bool) -> Void) {
        IOSMicrophonePermissionAdapter.requestAccess(completion: completion)
    }
    
    func openSettings() {
        IOSMicrophonePermissionAdapter.openSettings()
    }
    
    // MARK: - Duration Timer
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: VoiceInkRecordingFlowState.durationUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFlowState { $0.advanceDuration() }
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func setRecordingSheetPresented(_ isPresented: Bool) {
        updateFlowState { $0.setRecordingSheetPresented(isPresented) }
    }

    private func updateFlowState(_ update: (inout VoiceInkRecordingFlowState) -> Void) {
        var updatedState = flowState
        update(&updatedState)
        flowState = updatedState
    }
    
    private func failActiveKeyboardDictation(message: String) {
        guard let requestID = keyboardDictationRequestID else { return }
        keyboardDictationRequestID = nil
        coordinator.failKeyboardDictation(requestID: requestID, message: message)
    }
}
