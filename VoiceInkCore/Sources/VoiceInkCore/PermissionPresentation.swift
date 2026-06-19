import Foundation

public enum VoiceInkMacOSPermissionSettingsCardKind: String, Equatable, Sendable {
    case inputMonitoring
    case microphone
    case accessibility
    case screenContext
}

public struct VoiceInkMacOSPermissionSettingsCardPresentation: Identifiable, Equatable, Sendable {
    public let kind: VoiceInkMacOSPermissionSettingsCardKind
    public let iconSystemName: String
    public let title: String
    public let description: String
    public let grantButtonTitle: String
    public let relaunchButtonTitle: String?
    public let infoTipMessage: String?
    public let infoTipURLString: String?

    public var id: VoiceInkMacOSPermissionSettingsCardKind { kind }

    public init(
        kind: VoiceInkMacOSPermissionSettingsCardKind,
        iconSystemName: String,
        title: String,
        description: String,
        grantButtonTitle: String,
        relaunchButtonTitle: String? = nil,
        infoTipMessage: String? = nil,
        infoTipURLString: String? = nil
    ) {
        self.kind = kind
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
        self.grantButtonTitle = grantButtonTitle
        self.relaunchButtonTitle = relaunchButtonTitle
        self.infoTipMessage = infoTipMessage
        self.infoTipURLString = infoTipURLString
    }

    public var grantedIconSystemName: String {
        "\(iconSystemName).fill"
    }

    public func buttonTitle(requiresRelaunch: Bool) -> String {
        if requiresRelaunch, let relaunchButtonTitle {
            return relaunchButtonTitle
        }
        return grantButtonTitle
    }
}

public enum VoiceInkMacOSPermissionSettingsPresentation {
    public static let headerIconSystemName = "shield.lefthalf.filled"
    public static let headerTitle = "App Permissions"
    public static let headerDescription =
        "Microphone and shortcut access are needed for recording. Screen context is optional."
    public static let relaunchRequiredMessage =
        "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
    public static let refreshButtonSystemImageName = "arrow.clockwise"
    public static let grantedStatusSystemImageName = "checkmark.seal.fill"
    public static let deniedStatusSystemImageName = "xmark.seal.fill"
    public static let actionSystemImageName = "arrow.right"

    public static let inputMonitoringCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .inputMonitoring,
        iconSystemName: "keyboard.badge.eye",
        title: "Input Monitoring Access",
        description: "Allow roma-just-talk to listen for your recording hotkey globally",
        grantButtonTitle: "Grant",
        relaunchButtonTitle: "Relaunch to Apply",
        infoTipMessage: "roma-just-talk uses Input Monitoring only to detect your configured recording shortcut while other apps are active."
    )

    public static let microphoneCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .microphone,
        iconSystemName: "mic",
        title: "Microphone Access",
        description: "Allow roma-just-talk to record your voice for transcription",
        grantButtonTitle: "Grant"
    )

    public static let accessibilityCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .accessibility,
        iconSystemName: "hand.raised",
        title: "Accessibility Access",
        description: "Add roma-just-talk to Accessibility, then turn its switch on",
        grantButtonTitle: "Grant",
        infoTipMessage: "macOS requires you to enable the roma-just-talk switch yourself. Dragging the app into the list only adds it when it is missing."
    )

    public static let screenContextCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .screenContext,
        iconSystemName: "rectangle.on.rectangle",
        title: "Screen Context (Optional)",
        description: "Use visible screen text to improve transcript enhancement when you choose.",
        grantButtonTitle: "Enable",
        relaunchButtonTitle: "Relaunch to Apply",
        infoTipMessage: "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
        infoTipURLString: "https://tryvoiceink.com/docs/contextual-awareness"
    )
}
