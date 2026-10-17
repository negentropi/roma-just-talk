import Foundation
import OSLog
import RomaCore

enum RomaAppGroupRecordingBridge {
    static let appGroupIdentifier = RomaAppIdentity.iOSAppGroupIdentifier

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func recordingStateReadPlan(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateReadPlan {
        RomaAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: defaults?.bool(
                forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            ) ?? false,
            lastRecordingTimestamp: defaults?.double(
                forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
            ) ?? 0,
            now: now
        )
    }

    static func apply(
        _ plan: RomaAppGroupRecordingStateWritePlan,
        to defaults: UserDefaults?
    ) {
        plan.applyRuntimeState(
            setIsRecording: {
                defaults?.set(
                    $0,
                    forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
                )
            },
            setLastRecordingTimestamp: {
                defaults?.set(
                    $0,
                    forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
                )
            }
        )
    }
}

/// Handles communication between the main RomaJustTalk app and the keyboard extension
/// Uses App Groups + Darwin Notifications for reliable iOS-native communication
final class AppGroupCoordinator {
    static let shared = AppGroupCoordinator()
    
    // MARK: - Properties
    private let sharedDefaults: UserDefaults?
    private let keyboardDictationStore: RomaKeyboardDictationExchangeStore
    private let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    
    var onStopRecordingRequested: (() -> Void)?
    var onKeyboardReadinessReported: ((RomaIOSKeyboardReadinessObservation) -> Void)?
    
    // MARK: - Initialization
    private init() {
        let sharedDefaults = RomaAppGroupRecordingBridge.sharedDefaults()
        self.sharedDefaults = sharedDefaults
        self.keyboardDictationStore = RomaKeyboardDictationExchangeStore(defaults: sharedDefaults)
        setupNotificationObservers()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Interface for Keyboard Extension
    
    /// Call this from the keyboard extension to request recording stop
    func requestStopRecording() {
        let mutationPlan = RomaAppGroupRecordingStatePolicy.stopRequestedMutationPlan()
        
        // Send immediate notification
        apply(mutationPlan)
    }
    
    /// Get current recording state (for keyboard UI updates)
    var isRecording: Bool {
        let readPlan = RomaAppGroupRecordingBridge.recordingStateReadPlan(in: sharedDefaults)
        let state = readPlan.applyRuntimeState { mutationPlan in
            RomaIOSLogger.appGroup.warning("\(RomaAppGroupRecordingDiagnostics.staleRecordingStateClearedMessage, privacy: .public)")
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
                ? RomaAppIdentity.iOSKeyboardActivatedWithFullAccessDarwinNotificationName
                : RomaAppIdentity.iOSKeyboardActivatedDarwinNotificationName
        )
    }

    func takePendingKeyboardDictationRequest() -> RomaKeyboardDictationRequest? {
        keyboardDictationStore.takePendingRequest()
    }

    func keyboardDictationStatus(
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String?,
        surroundingTextAfterCursor: String?
    ) -> RomaKeyboardDictationExchangeStatus {
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
    ) -> RomaKeyboardDictationDelivery? {
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
        let mutationPlan = RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: isRecording
        )
        
        // Notify keyboard of state change
        apply(mutationPlan)
        
        RomaIOSLogger.appGroup.notice("\(RomaAppGroupRecordingDiagnostics.updatedRecordingStateMessage(isRecording: isRecording), privacy: .public)")
    }

    private func apply(_ mutationPlan: RomaAppGroupRecordingStateMutationPlan) {
        mutationPlan.applyRuntimeState(
            applyWritePlan: {
                RomaAppGroupRecordingBridge.apply($0, to: sharedDefaults)
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
            RomaAppIdentity.iOSStopRecordingDarwinNotificationName as CFString,
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
            RomaAppIdentity.iOSKeyboardActivatedDarwinNotificationName as CFString,
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
            RomaAppIdentity.iOSKeyboardActivatedWithFullAccessDarwinNotificationName as CFString,
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
                RomaIOSKeyboardReadinessObservation(
                    hasFullAccess: hasFullAccess,
                    observedAt: Date()
                )
            )
        }
    }
    
}
