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
        VoiceInkIOSLogger.recording.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.recordingManagerInitializedMessage, privacy: .public)")
        setupCoordinatorCallbacks()
    }
    
    deinit {
        durationTimer?.invalidate()
    }
    
    // MARK: - Coordinator Setup
    private func setupCoordinatorCallbacks() {
        coordinator.onStopRecordingRequested = { [weak self] in
            guard let self = self else { return }

            switch VoiceInkKeyboardStopRecordingRequestPolicy.action(recordingState: self.recordingState) {
            case .handleStopRequest:
                // We need modelContext, so the SwiftUI shell completes the stop from this notification.
                VoiceInkIOSLogger.recording.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.keyboardStopRecordingRequestedMessage, privacy: .public)")
                NotificationCenter.default.post(
                    name: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName,
                    object: nil
                )
            case .ignore:
                break
            }
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        applyPermissionAction(
            VoiceInkRecordingPermissionPolicy.action(for: checkPermissionStatus())
        )
    }

    private func applyPermissionAction(_ action: VoiceInkRecordingPermissionAction) {
        switch action {
        case .startRecording:
            proceedToStartRecording()

        case .presentPermissionDenied:
            activeRecordingAlert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied

        case .requestPermission:
            requestPermission { [weak self] granted in
                self?.applyPermissionAction(
                    VoiceInkRecordingPermissionPolicy.action(afterPermissionRequestGranted: granted)
                )
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
        let stopPlan = flowState.stopRecordingPlan(
            audioFileURL: recorder.currentRecordingURL?.lastPathComponent
        )

        recorder.stopRecording()
        stopDurationTimer()
        flowState = stopPlan.flowStateAfterStop
        coordinator.updateRecordingState(false)

        guard let draft = stopPlan.pendingDraft else { return }

        let note = Transcription(recordingDraft: draft)
        modelContext.insert(note)
        try? modelContext.save()

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
    private func checkPermissionStatus() -> VoiceInkRecordingPermissionStatus {
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
        let url = URL(string: UIApplication.openSettingsURLString)
        let action = VoiceInkRecordingPermissionPolicy.settingsOpenAction(
            hasSettingsURL: url != nil,
            canOpenSettingsURL: url.map { UIApplication.shared.canOpenURL($0) } ?? false
        )

        switch action {
        case .openSettings:
            guard let url else { return }
            UIApplication.shared.open(url)
        case .ignore:
            break
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
                _ = try await TranscriptionRetryService.shared.retranscribe(note: note)
            } catch {
                // Failure state is already applied by the shared record helper.
            }

            await MainActor.run {
                try? modelContext.save()
            }
        }
    }
}
