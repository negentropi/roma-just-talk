import Foundation

/// Handles communication between the main VoiceInk app and the keyboard extension
/// Uses App Groups + Darwin Notifications for reliable iOS-native communication
final class AppGroupCoordinator {
    static let shared = AppGroupCoordinator()
    
    // MARK: - Constants
    private let appGroupIdentifier = "group.com.prakashjoshipax.VoiceInk"
    
    // UserDefaults keys for persistent state
    private enum UserDefaultsKeys {
        static let isRecording = "isRecording"
        static let lastRecordingTimestamp = "lastRecordingTimestamp"
    }
    
    // Darwin notification names for real-time communication
    private enum NotificationNames {
        static let stopRecording = "com.prakashjoshipax.VoiceInk.stopRecording"
        static let recordingStateChanged = "com.prakashjoshipax.VoiceInk.recordingStateChanged"
    }
    
    // MARK: - Properties
    private let sharedDefaults: UserDefaults?
    private let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    
    var onStopRecordingRequested: (() -> Void)?
    
    // MARK: - Initialization
    private init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        setupNotificationObservers()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Interface for Keyboard Extension
    
    /// Call this from the keyboard extension to request recording stop
    func requestStopRecording() {
        let timestamp = Date().timeIntervalSince1970
        sharedDefaults?.set(timestamp, forKey: UserDefaultsKeys.lastRecordingTimestamp)
        
        // Send immediate notification
        postDarwinNotification(NotificationNames.stopRecording)
    }
    
    /// Get current recording state (for keyboard UI updates)
    var isRecording: Bool {
        let storedState = sharedDefaults?.bool(forKey: UserDefaultsKeys.isRecording) ?? false
        let timestamp = sharedDefaults?.double(forKey: UserDefaultsKeys.lastRecordingTimestamp) ?? 0
        let currentTime = Date().timeIntervalSince1970
        
        // If the stored state is more than 30 seconds old, consider it stale
        if storedState && (currentTime - timestamp) > 30 {
            print("⚠️ Recording state appears stale, clearing it")
            updateRecordingState(false)
            return false
        }
        
        return storedState
    }
    
    // MARK: - Public Interface for Main App
    
    /// Call this from the main app to update recording state
    func updateRecordingState(_ isRecording: Bool) {
        sharedDefaults?.set(isRecording, forKey: UserDefaultsKeys.isRecording)
        // Update timestamp whenever state changes
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastRecordingTimestamp)
        
        // Notify keyboard of state change
        postDarwinNotification(NotificationNames.recordingStateChanged)
        
        print("📡 Updated recording state: \(isRecording)")
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
            NotificationNames.stopRecording as CFString,
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
