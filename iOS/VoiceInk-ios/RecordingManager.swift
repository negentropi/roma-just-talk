import SwiftUI
import SwiftData
import AVFoundation
import Combine
import UIKit
import VoiceInkCore

private enum MicrophonePermissionStatus {
    case granted, denied, undetermined
}
 
@MainActor
final class RecordingManager: ObservableObject {
    @Published var activeRecordingAlert: VoiceInkRecordingAlertPresentation?
    @Published private var flowState = VoiceInkRecordingFlowState()
    
    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private var durationTimer: Timer?

    private let coordinator = AppGroupCoordinator.shared
    
    var recordingState: VoiceInkRecordingState {
        flowState.recordingState
    }

    var animate: Bool {
        flowState.animate
    }

    var isRecordingSheetPresented: Bool {
        flowState.isRecordingSheetPresented
    }

    var isRecording: Bool {
        recordingState.isActivelyRecording
    }

    var currentDuration: TimeInterval {
        flowState.currentDuration
    }

    var currentAudioLevels: [Float] {
        recorder.levelsHistory
    }
    
    // MARK: - Initialization
    init() {
        // Simplified initialization - no complex keyboard coordination needed
        print("🎙️ RecordingManager initialized")
        setupCoordinatorCallbacks()
    }
    
    deinit {
        durationTimer?.invalidate()
    }
    
    // MARK: - Coordinator Setup
    private func setupCoordinatorCallbacks() {
        coordinator.onStopRecordingRequested = { [weak self] in
            guard let self = self, self.isRecording else { return }
            // This will be called when keyboard extension requests stop
            print("🛑 Stop recording requested from keyboard extension")
            // We need modelContext, so we'll handle this via a notification instead
            NotificationCenter.default.post(
                name: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName,
                object: nil
            )
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        switch checkPermissionStatus() {
        case .granted:
            proceedToStartRecording()
        case .denied:
            activeRecordingAlert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied
        case .undetermined:
            requestPermission { [weak self] granted in
                if granted {
                    self?.proceedToStartRecording()
                } else {
                    self?.activeRecordingAlert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied
                }
            }
        }
    }
    
    private func proceedToStartRecording() {
        updateFlowState { $0.prepareRecordingStart() }
        
        // Update coordinator state
        coordinator.updateRecordingState(true)
        
        do {
            try recorder.startRecording()
            updateFlowState { $0.completeRecordingStart() }
            startDurationTimer()
        } catch {
            activeRecordingAlert = VoiceInkRecordingAlertPresentation.recordingStartFailure(for: error)
            updateFlowState { $0.failRecordingStart() }
            // Update coordinator state on error
            coordinator.updateRecordingState(false)
        }
    }
    
    func stopRecording(modelContext: ModelContext) {
        // Stop recording and get file info
        recorder.stopRecording()
        stopDurationTimer()
        guard let fileURL = recorder.currentRecordingURL else { return }
        
        // Store relative path and duration
        let audioFileName = fileURL.lastPathComponent
        let recordingDuration = currentDuration
        
        let draft = VoiceInkRecordingTranscriptionDraft.pending(
            duration: recordingDuration,
            audioFileURL: audioFileName
        )
        let note = Transcription(recordingDraft: draft)
        modelContext.insert(note)
        try? modelContext.save()
        
        // Reset UI state immediately so user can continue using the app
        updateFlowState { $0.finishRecording() }
        
        // Update coordinator state
        coordinator.updateRecordingState(false)
        
        // Start background transcription
        transcribeInBackground(note: note, modelContext: modelContext)
    }
    
    func cancelRecording() {
        recorder.discard()
        stopDurationTimer()
        updateFlowState { $0.cancelRecording() }
        
        // Update coordinator state
        coordinator.updateRecordingState(false)
    }
    
    // MARK: - Permissions
    private func checkPermissionStatus() -> MicrophonePermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
    
    private func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
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
    
    // MARK: - Transcription
    private func transcribeInBackground(note: Transcription, modelContext: ModelContext) {
        Task {
            defer { 
                // Clean up recorder state
                recorder.currentRecordingURL = nil
            }

            do {
                _ = try await note.retranscribeStoredAudio { fileURL in
                    try await TranscriptionRetryService.shared.transcribe(fileURL: fileURL)
                }
            } catch {
                // Failure state is already applied by the shared record helper.
            }

            await MainActor.run {
                try? modelContext.save()
            }
        }
    }
}
