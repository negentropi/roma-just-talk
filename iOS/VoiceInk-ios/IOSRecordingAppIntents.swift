import AppIntents
import Foundation
import VoiceInkCore

enum IOSRecordingAppIntentAction: String, Equatable {
    case start
    case stop
    case cancel
}

enum IOSRecordingAppIntentRuntimeAction: Equatable {
    case start
    case stop
    case cancel
    case ignore
}

enum IOSRecordingAppIntentPolicy {
    static func runtimeAction(
        for request: IOSRecordingAppIntentAction,
        recordingState: VoiceInkRecordingState
    ) -> IOSRecordingAppIntentRuntimeAction {
        switch request {
        case .start:
            return recordingState == .idle ? .start : .ignore
        case .stop:
            return recordingState == .recording ? .stop : .ignore
        case .cancel:
            return recordingState == .recording ? .cancel : .ignore
        }
    }
}

enum IOSRecordingAppIntentRequestStore {
    static let requestNotification = Notification.Name("iosRecordingAppIntentRequest")
    static let defaultsKey = "iosRecordingAppIntentAction"

    static func submit(
        _ action: IOSRecordingAppIntentAction,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(action.rawValue, forKey: defaultsKey)
        notificationCenter.post(name: requestNotification, object: nil)
    }

    static func consume(
        defaults: UserDefaults = .standard
    ) -> IOSRecordingAppIntentAction? {
        guard let rawValue = defaults.string(forKey: defaultsKey) else { return nil }
        defaults.removeObject(forKey: defaultsKey)
        return IOSRecordingAppIntentAction(rawValue: rawValue)
    }
}

struct IOSStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Open the app and start a voice recording.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            IOSRecordingAppIntentRequestStore.submit(.start)
        }
        return .result(dialog: "Ready to record")
    }
}

struct IOSStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stop the active recording and begin transcription.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            IOSRecordingAppIntentRequestStore.submit(.stop)
        }
        return .result(dialog: "Stopping recording")
    }
}

struct IOSCancelRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Recording"
    static var description = IntentDescription("Cancel and discard the active recording.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            IOSRecordingAppIntentRequestStore.submit(.cancel)
        }
        return .result(dialog: "Canceling recording")
    }
}

struct IOSRecordingAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IOSStartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Record with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.circle"
        )
        AppShortcut(
            intent: IOSStopRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "Finish recording with \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: IOSCancelRecordingIntent(),
            phrases: [
                "Cancel recording with \(.applicationName)",
                "Discard recording with \(.applicationName)"
            ],
            shortTitle: "Cancel Recording",
            systemImageName: "xmark.circle"
        )
    }
}
