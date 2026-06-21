import Foundation
import VoiceInkCore

enum VoiceInkAppGroupRecordingBridge {
    static let appGroupIdentifier = VoiceInkAppIdentity.iOSAppGroupIdentifier

    enum NotificationName {
        static let stopRecording = VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName
        static let recordingStateChanged = VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
    }

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func markStopRequested(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) {
        apply(
            VoiceInkAppGroupRecordingStatePolicy.stopRequestedWritePlan(now: now),
            to: defaults
        )
    }

    static func writeRecordingState(
        _ isRecording: Bool,
        to defaults: UserDefaults?,
        now: Date = Date()
    ) {
        apply(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateWritePlan(
                isRecording: isRecording,
                now: now
            ),
            to: defaults
        )
    }

    static func recordingState(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        VoiceInkAppGroupRecordingStatePolicy.state(
            storedIsRecording: defaults?.bool(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            ) ?? false,
            lastRecordingTimestamp: defaults?.double(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
            ) ?? 0,
            now: now
        )
    }

    private static func apply(
        _ plan: VoiceInkAppGroupRecordingStateWritePlan,
        to defaults: UserDefaults?
    ) {
        if let isRecording = plan.isRecording {
            defaults?.set(
                isRecording,
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            )
        }

        defaults?.set(
            plan.lastRecordingTimestamp,
            forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
        )
    }
}
