import Foundation
import OSLog
import VoiceInkCore

enum VoiceInkAppGroupRecordingBridge {
    static let appGroupIdentifier = VoiceInkAppIdentity.iOSAppGroupIdentifier

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func recordingStateReadPlan(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateReadPlan {
        VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: defaults?.bool(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            ) ?? false,
            lastRecordingTimestamp: defaults?.double(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
            ) ?? 0,
            now: now
        )
    }

    static func apply(
        _ plan: VoiceInkAppGroupRecordingStateWritePlan,
        to defaults: UserDefaults?
    ) {
        plan.applyRuntimeState(
            setIsRecording: {
                defaults?.set(
                    $0,
                    forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
                )
            },
            setLastRecordingTimestamp: {
                defaults?.set(
                    $0,
                    forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
                )
            }
        )
    }
}

/// Handles communication between the main VoiceInk app and the keyboard extension
/// Uses App Groups + Darwin Notifications for reliable iOS-native communication
final class AppGroupCoordinator {
    static let shared = AppGroupCoordinator()
    
    // MARK: - Properties
    private let sharedDefaults: UserDefaults?
    private let keyboardDictationStore: VoiceInkKeyboardDictationExchangeStore
    private let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    
    var onStopRecordingRequested: (() -> Void)?
    var onKeyboardReadinessReported: ((VoiceInkIOSKeyboardReadinessObservation) -> Void)?
    
    // MARK: - Initialization
    private init() {
        let sharedDefaults = VoiceInkAppGroupRecordingBridge.sharedDefaults()
        self.sharedDefaults = sharedDefaults
        self.keyboardDictationStore = VoiceInkKeyboardDictationExchangeStore(defaults: sharedDefaults)
        setupNotificationObservers()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Interface for Keyboard Extension
    
    /// Call this from the keyboard extension to request recording stop
    func requestStopRecording() {
        let mutationPlan = VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan()
        
        // Send immediate notification
        apply(mutationPlan)
    }
    
    /// Get current recording state (for keyboard UI updates)
    var isRecording: Bool {
        let readPlan = VoiceInkAppGroupRecordingBridge.recordingStateReadPlan(in: sharedDefaults)
        let state = readPlan.applyRuntimeState { mutationPlan in
            VoiceInkIOSLogger.appGroup.warning("\(VoiceInkAppGroupRecordingDiagnostics.staleRecordingStateClearedMessage, privacy: .public)")
            apply(mutationPlan)
        }

        return state.isRecording
    }

    func beginKeyboardDictation(
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String?,
        surroundingTextAfterCursor: String?
    ) -> UUID? {
        keyboardDictationStore.begin(
            documentIdentifier: documentIdentifier,
            surroundingTextBeforeCursor: surroundingTextBeforeCursor,
            surroundingTextAfterCursor: surroundingTextAfterCursor
        )
    }

    func reportKeyboardReadiness(hasFullAccess: Bool) {
        postDarwinNotification(
            hasFullAccess
                ? VoiceInkAppIdentity.iOSKeyboardActivatedWithFullAccessDarwinNotificationName
                : VoiceInkAppIdentity.iOSKeyboardActivatedDarwinNotificationName
        )
    }

    func takePendingKeyboardDictationRequest() -> VoiceInkKeyboardDictationRequest? {
        keyboardDictationStore.takePendingRequest()
    }

    func keyboardDictationStatus(
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String?,
        surroundingTextAfterCursor: String?
    ) -> VoiceInkKeyboardDictationExchangeStatus {
        keyboardDictationStore.status(
            for: documentIdentifier,
            surroundingTextBeforeCursor: surroundingTextBeforeCursor,
            surroundingTextAfterCursor: surroundingTextAfterCursor
        )
    }

    func takeCompletedKeyboardDictation(
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String?,
        surroundingTextAfterCursor: String?,
        confirmDocumentChange: Bool = false
    ) -> VoiceInkKeyboardDictationDelivery? {
        keyboardDictationStore.takeCompletedResult(
            for: documentIdentifier,
            surroundingTextBeforeCursor: surroundingTextBeforeCursor,
            surroundingTextAfterCursor: surroundingTextAfterCursor,
            confirmDocumentChange: confirmDocumentChange
        )
    }

    @discardableResult
    func completeKeyboardDictation(
        requestID: UUID,
        text: String,
        shouldLowercase: Bool,
        shouldInsertReturn: Bool
    ) -> Bool {
        keyboardDictationStore.complete(
            requestID: requestID,
            text: text,
            shouldLowercase: shouldLowercase,
            shouldInsertReturn: shouldInsertReturn
        )
    }

    @discardableResult
    func failKeyboardDictation(requestID: UUID, message: String) -> Bool {
        keyboardDictationStore.fail(requestID: requestID, message: message)
    }

    @discardableResult
    func clearKeyboardDictation(requestID: UUID) -> Bool {
        keyboardDictationStore.clear(requestID: requestID)
    }
    
    // MARK: - Public Interface for Main App
    
    /// Call this from the main app to update recording state
    func updateRecordingState(_ isRecording: Bool) {
        let mutationPlan = VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: isRecording
        )
        
        // Notify keyboard of state change
        apply(mutationPlan)
        
        VoiceInkIOSLogger.appGroup.notice("\(VoiceInkAppGroupRecordingDiagnostics.updatedRecordingStateMessage(isRecording: isRecording), privacy: .public)")
    }

    private func apply(_ mutationPlan: VoiceInkAppGroupRecordingStateMutationPlan) {
        mutationPlan.applyRuntimeState(
            applyWritePlan: {
                VoiceInkAppGroupRecordingBridge.apply($0, to: sharedDefaults)
            },
            postDarwinNotification: postDarwinNotification
        )
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

        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, _, _, _) in
                guard let observer else { return }
                let coordinator = Unmanaged<AppGroupCoordinator>.fromOpaque(observer).takeUnretainedValue()
                coordinator.handleKeyboardReadinessNotification(hasFullAccess: false)
            },
            VoiceInkAppIdentity.iOSKeyboardActivatedDarwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )

        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, _, _, _) in
                guard let observer else { return }
                let coordinator = Unmanaged<AppGroupCoordinator>.fromOpaque(observer).takeUnretainedValue()
                coordinator.handleKeyboardReadinessNotification(hasFullAccess: true)
            },
            VoiceInkAppIdentity.iOSKeyboardActivatedWithFullAccessDarwinNotificationName as CFString,
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

    private func handleKeyboardReadinessNotification(hasFullAccess: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onKeyboardReadinessReported?(
                VoiceInkIOSKeyboardReadinessObservation(
                    hasFullAccess: hasFullAccess,
                    observedAt: Date()
                )
            )
        }
    }
    
}
