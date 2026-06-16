import SwiftUI
import SwiftData
import AVFoundation
import Combine
import UIKit
import VoiceInkCore

extension Notification.Name {
    static let stopRecordingFromKeyboard = Notification.Name("stopRecordingFromKeyboard")
}

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case completed(String)
    case error(String)
}

private enum MicrophonePermissionStatus {
    case granted, denied, undetermined
}

enum ActiveRecordingAlert: Identifiable {
    case permissionDenied
    case busy
    case generic(Error)
    
    var id: String {
        switch self {
        case .permissionDenied: return "permissionDenied"
        case .busy: return "busy"
        case .generic(let error): return "generic-\(error.localizedDescription)"
        }
    }
}
 
@MainActor
final class RecordingManager: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var animate = false
    @Published var isRecordingSheetPresented = false
    @Published var activeRecordingAlert: ActiveRecordingAlert?
    @Published var currentRecordingNote: Transcription?
    @Published var currentDuration: Double = 0
    
    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private var durationTimer: Timer?

    private let sessionManager = AudioSessionManager.shared
    private let coordinator = AppGroupCoordinator.shared
    
    var isRecording: Bool {
        recordingState == .recording
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
            NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        switch checkPermissionStatus() {
        case .granted:
            proceedToStartRecording()
        case .denied:
            activeRecordingAlert = .permissionDenied
        case .undetermined:
            requestPermission { [weak self] granted in
                if granted {
                    self?.proceedToStartRecording()
                } else {
                    self?.activeRecordingAlert = .permissionDenied
                }
            }
        }
    }
    
    private func proceedToStartRecording() {
        recordingState = .recording
        animate = true
        
        // Update coordinator state
        coordinator.updateRecordingState(true)
        
        settings.selectedModeId = settings.modes.repairedSelectedModeId(settings.selectedModeId)
        
        do {
            try recorder.startRecording()
            startDurationTimer()
            isRecordingSheetPresented = true
        } catch {
            activeRecordingAlert = .generic(error)
            recordingState = .idle
            animate = false
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
        
        // IMMEDIATELY create and insert the note with pending status
        let note = Transcription(
            text: "",
            duration: recordingDuration,
            audioFileURL: audioFileName,
            transcriptionStatus: .pending
        )
        modelContext.insert(note)
        try? modelContext.save()
        
        // Reset UI state immediately so user can continue using the app
        recordingState = .idle
        animate = false
        currentRecordingNote = note
        isRecordingSheetPresented = false
        
        // Update coordinator state
        coordinator.updateRecordingState(false)
        
        // Start background transcription
        transcribeInBackground(note: note, modelContext: modelContext)
    }
    
    func cancelRecording() {
        recorder.discard()
        stopDurationTimer()
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
        currentDuration = 0
        
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
        currentDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentDuration += 0.1
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    // MARK: - Transcription
    private func transcribeInBackground(note: Transcription, modelContext: ModelContext) {
        guard let fileURL = note.resolvedAudioFileURL else {
            note.transcriptionStatus = .failed
            note.transcriptionError = TranscriptionError.audioFileNotFound.localizedDescription
            try? modelContext.save()
            return
        }

        Task {
            defer { 
                // Clean up recorder state
                recorder.currentRecordingURL = nil
                recorder.currentDuration = 0
            }

            do {
                let result = try await TranscriptionRetryService.shared.transcribe(fileURL: fileURL)
                
                // Update the existing note on main thread
                await MainActor.run {
                    note.text = result.cleanedText
                    note.enhancedText = result.enhancedText
                    note.transcriptionModelName = result.transcriptionModelName
                    note.aiEnhancementModelName = result.aiEnhancementModelName
                    note.transcriptionStatus = .completed
                    note.transcriptionError = result.postProcessingError
                    try? modelContext.save()
                }
                
            } catch {
                // Update note with error on main thread
                await MainActor.run {
                    note.transcriptionStatus = .failed
                    note.transcriptionError = error.localizedDescription
                    try? modelContext.save()
                }
            }
        }
    }
}
