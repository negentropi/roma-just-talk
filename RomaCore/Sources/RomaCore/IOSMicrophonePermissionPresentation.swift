public enum RomaIOSMicrophonePermissionRecoveryAction: Equatable, Sendable {
    case requestAccess
    case openSettings
    case none
}

public struct RomaIOSMicrophonePermissionStatusPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let iconSystemName: String
    public let recoveryAction: RomaIOSMicrophonePermissionRecoveryAction
    public let recoveryButtonTitle: String?

    public init(
        title: String,
        detail: String,
        iconSystemName: String,
        recoveryAction: RomaIOSMicrophonePermissionRecoveryAction,
        recoveryButtonTitle: String?
    ) {
        self.title = title
        self.detail = detail
        self.iconSystemName = iconSystemName
        self.recoveryAction = recoveryAction
        self.recoveryButtonTitle = recoveryButtonTitle
    }
}

public enum RomaIOSMicrophonePermissionPresentation {
    public static let navigationTitle = "Microphone Access"
    public static let title = "Allow Microphone Access"
    public static let subtitle = "\(RomaAppIdentity.displayName) needs microphone access to record and transcribe your voice."
    public static let settingsRowTitle = "Microphone Access"
    public static let settingsRowSystemImageName = "mic.fill"
    public static let continueButtonTitle = "Continue"
    public static let skipButtonTitle = "Set Up Later"
    public static let refreshButtonTitle = "Refresh Status"

    public static func status(
        _ status: RomaRecordingPermissionStatus
    ) -> RomaIOSMicrophonePermissionStatusPresentation {
        switch status {
        case .granted:
            return RomaIOSMicrophonePermissionStatusPresentation(
                title: "Microphone Ready",
                detail: "Microphone access is enabled. You can start recording.",
                iconSystemName: "checkmark.circle.fill",
                recoveryAction: .none,
                recoveryButtonTitle: nil
            )
        case .denied:
            return RomaIOSMicrophonePermissionStatusPresentation(
                title: "Microphone Access Denied",
                detail: "Enable Microphone access in Settings, then return here to refresh the status.",
                iconSystemName: "mic.slash.fill",
                recoveryAction: .openSettings,
                recoveryButtonTitle: "Open Settings"
            )
        case .undetermined:
            return RomaIOSMicrophonePermissionStatusPresentation(
                title: "Microphone Access Required",
                detail: "Allow access when prompted so recordings can begin from the app, keyboard, or Shortcuts.",
                iconSystemName: "mic.fill",
                recoveryAction: .requestAccess,
                recoveryButtonTitle: "Allow Microphone Access"
            )
        }
    }
}
