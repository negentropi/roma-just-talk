import Foundation
import VoiceInkCore

enum VoiceInkAppGroupRecordingBridge {
    static let appGroupIdentifier = VoiceInkAppIdentity.iOSAppGroupIdentifier

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func recordingState(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        recordingStateReadPlan(in: defaults, now: now).state
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
