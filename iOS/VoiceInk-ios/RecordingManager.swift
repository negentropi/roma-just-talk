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
    
    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private let transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    private var durationTimer: Timer?
    private var keyboardDictationRequestID: UUID?

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
        updateFlowState { $0.prepareRecordingStart() }
        
        // Update coordinator state
        coordinator.updateRecordingState(true)
        
        do {
            try recorder.startRecording()
            updateFlowState { $0.completeRecordingStart() }
            startDurationTimer()
        } catch {
            let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(for: error)
            activeRecordingAlert = alert
            updateFlowState { $0.failRecordingStart() }
            // Update coordinator state on error
            coordinator.updateRecordingState(false)
            failActiveKeyboardDictation(message: alert.message)
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
            insertPendingDraft: { [self] draft in
                let note = Transcription(recordingDraft: draft)
                modelContext.insert(note)
                try? modelContext.save()

                let keyboardRequestID = keyboardDictationRequestID
                keyboardDictationRequestID = nil
                transcriptionTasks.start(
                    note: note,
                    keyboardRequestID: keyboardRequestID,
                    persist: { try? modelContext.save() }
                )
                recorder.currentRecordingURL = nil
            }
        )

        if stopPlan.pendingDraft == nil {
            failActiveKeyboardDictation(message: "The recording file is unavailable.")
        }
    }
    
    func cancelRecording() {
        flowState.cancelRecordingPlan().applyRuntimeState(
            discardRecorder: recorder.discard,
            stopDurationTimer: stopDurationTimer,
            setFlowState: { flowState = $0 },
            updateRecordingState: coordinator.updateRecordingState
        )
        failActiveKeyboardDictation(message: "Recording canceled.")
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
    
    private func failActiveKeyboardDictation(message: String) {
        guard let requestID = keyboardDictationRequestID else { return }
        keyboardDictationRequestID = nil
        coordinator.failKeyboardDictation(requestID: requestID, message: message)
    }
}
