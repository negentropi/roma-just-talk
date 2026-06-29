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

            VoiceInkKeyboardStopRecordingRequestPolicy.plan(recordingState: self.recordingState)
                .applyRuntimeState {
                    // We need modelContext, so the SwiftUI shell completes the stop from this notification.
                    VoiceInkIOSLogger.recording.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.keyboardStopRecordingRequestedMessage, privacy: .public)")
                    NotificationCenter.default.post(
                        name: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName,
                        object: nil
                    )
                }
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        VoiceInkRecordingStartPolicy.plan(modeCount: settings.modes.count).applyRuntimeState(
            startRecording: startRecordingWithPermissionCheck,
            presentAlert: { activeRecordingAlert = $0 }
        )
    }

    private func startRecordingWithPermissionCheck() {
        VoiceInkRecordingPermissionPolicy.plan(for: checkPermissionStatus()).applyRuntimeState(
            startRecording: { [weak self] in
                self?.proceedToStartRecording()
            },
            presentPermissionDenied: { [weak self] in
                self?.activeRecordingAlert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied
            },
            requestPermission: { [weak self] completion in
                self?.requestPermission { granted in
                    completion(granted)
                }
            }
        )
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

        stopPlan.applyRuntimeState(
            stopRecorder: recorder.stopRecording,
            stopDurationTimer: stopDurationTimer,
            setFlowState: { flowState = $0 },
            updateRecordingState: coordinator.updateRecordingState,
            insertPendingDraft: { draft in
                let note = Transcription(recordingDraft: draft)
                modelContext.insert(note)
                try? modelContext.save()

                transcribeInBackground(note: note, modelContext: modelContext)
            }
        )
    }
    
    func cancelRecording() {
        flowState.cancelRecordingPlan().applyRuntimeState(
            discardRecorder: recorder.discard,
            stopDurationTimer: stopDurationTimer,
            setFlowState: { flowState = $0 },
            updateRecordingState: coordinator.updateRecordingState
        )
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
        VoiceInkRecordingPermissionPolicy.settingsOpenPlan(
            settingsURL: URL(string: UIApplication.openSettingsURLString),
            canOpenURL: UIApplication.shared.canOpenURL
        ).applyRuntimeState { url in
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

            _ = await settings.retranscribeStoredAudio(note)

            await MainActor.run {
                try? modelContext.save()
            }
        }
    }
}
