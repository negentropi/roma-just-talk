import Foundation
import OSLog
import VoiceInkCore

/// Handles communication between the main VoiceInk app and the keyboard extension
/// Uses App Groups + Darwin Notifications for reliable iOS-native communication
final class AppGroupCoordinator {
    static let shared = AppGroupCoordinator()
    
    // MARK: - Properties
    private let sharedDefaults: UserDefaults?
    private let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    
    var onStopRecordingRequested: (() -> Void)?
    
    // MARK: - Initialization
    private init() {
        sharedDefaults = VoiceInkAppGroupRecordingBridge.sharedDefaults()
        setupNotificationObservers()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Interface for Keyboard Extension
    
    /// Call this from the keyboard extension to request recording stop
    func requestStopRecording() {
        let mutationPlan = VoiceInkAppGroupRecordingBridge.markStopRequested(in: sharedDefaults)
        
        // Send immediate notification
        postDarwinNotification(mutationPlan.darwinNotificationName)
    }
    
    /// Get current recording state (for keyboard UI updates)
    var isRecording: Bool {
        let readPlan = VoiceInkAppGroupRecordingBridge.recordingStateReadPlan(in: sharedDefaults)
        if let mutationPlan = readPlan.staleStateRepairMutationPlan {
            VoiceInkIOSLogger.appGroup.warning("\(VoiceInkAppGroupRecordingDiagnostics.staleRecordingStateClearedMessage, privacy: .public)")
            VoiceInkAppGroupRecordingBridge.apply(mutationPlan, to: sharedDefaults)
            postDarwinNotification(mutationPlan.darwinNotificationName)
        }

        return readPlan.state.isRecording
    }
    
    // MARK: - Public Interface for Main App
    
    /// Call this from the main app to update recording state
    func updateRecordingState(_ isRecording: Bool) {
        let mutationPlan = VoiceInkAppGroupRecordingBridge.writeRecordingState(isRecording, to: sharedDefaults)
        
        // Notify keyboard of state change
        postDarwinNotification(mutationPlan.darwinNotificationName)
        
        VoiceInkIOSLogger.appGroup.notice("\(VoiceInkAppGroupRecordingDiagnostics.updatedRecordingStateMessage(isRecording: isRecording), privacy: .public)")
    }
    
    // MARK: - Darwin Notifications (Real-time Communication)
    
    private func setupNotificationObservers() {
        guard let center = notificationCenter else { return }

        // Observe stop recording notifications
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let coordinator = Unmanaged<AppGroupCoordinator>.fromOpaque(observer).takeUnretainedValue()
                coordinator.handleStopRecordingNotification()
            },
            VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }
    
    private func removeNotificationObservers() {
        guard let center = notificationCenter else { return }
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func postDarwinNotification(_ name: String) {
        guard let center = notificationCenter else { return }
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
    
    // MARK: - Notification Handlers
    
    private func handleStopRecordingNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.onStopRecordingRequested?()
        }
    }
    
}
