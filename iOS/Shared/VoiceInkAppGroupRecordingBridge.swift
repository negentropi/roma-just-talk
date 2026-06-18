import Foundation

struct VoiceInkAppGroupRecordingState: Equatable {
    let isRecording: Bool
    let shouldClearStaleState: Bool
}

enum VoiceInkAppGroupRecordingBridge {
    static let appGroupIdentifier = "group.com.prakashjoshipax.VoiceInk"
    static let staleRecordingInterval: TimeInterval = 30

    enum UserDefaultsKey {
        static let isRecording = "isRecording"
        static let lastRecordingTimestamp = "lastRecordingTimestamp"
    }

    enum NotificationName {
        static let stopRecording = "com.prakashjoshipax.VoiceInk.stopRecording"
        static let recordingStateChanged = "com.prakashjoshipax.VoiceInk.recordingStateChanged"
    }

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func markStopRequested(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) {
        defaults?.set(now.timeIntervalSince1970, forKey: UserDefaultsKey.lastRecordingTimestamp)
    }

    static func writeRecordingState(
        _ isRecording: Bool,
        to defaults: UserDefaults?,
        now: Date = Date()
    ) {
        defaults?.set(isRecording, forKey: UserDefaultsKey.isRecording)
        defaults?.set(now.timeIntervalSince1970, forKey: UserDefaultsKey.lastRecordingTimestamp)
    }

    static func recordingState(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        let storedState = defaults?.bool(forKey: UserDefaultsKey.isRecording) ?? false
        let timestamp = defaults?.double(forKey: UserDefaultsKey.lastRecordingTimestamp) ?? 0

        guard storedState else {
            return VoiceInkAppGroupRecordingState(isRecording: false, shouldClearStaleState: false)
        }

        let isStale = now.timeIntervalSince1970 - timestamp > staleRecordingInterval
        return VoiceInkAppGroupRecordingState(isRecording: !isStale, shouldClearStaleState: isStale)
    }
}
