import Foundation

public struct WindowsPermissionSurface: Equatable, Hashable, Sendable {
    public var minimumPermissions: [String]
    public var osPermissionGrants: [String]
    public var nativeCapabilities: [String]
    public var microphoneSettingsPath: String
    public var microphoneSettingsURI: String
    public var requiresDesktopAppMicrophoneAccess: Bool
    public var hotKeyPermissionPrompt: Bool
    public var pastePermissionPrompt: Bool
    public var accessibilityPermissionPrompt: Bool
    public var automationPermissionPrompt: Bool
    public var pasteIntegrityLimit: String
    public var adminRequired: Bool
    public var startupMechanism: String
    public var startupLauncher: String
    public var startupLaunchMode: String
    public var startupPermissionPrompt: Bool
    public var screenCaptureRequired: Bool
    public var screenRecordingPermissionPrompt: Bool

    public init(
        minimumPermissions: [String],
        osPermissionGrants: [String],
        nativeCapabilities: [String],
        microphoneSettingsPath: String,
        microphoneSettingsURI: String,
        requiresDesktopAppMicrophoneAccess: Bool,
        hotKeyPermissionPrompt: Bool,
        pastePermissionPrompt: Bool,
        accessibilityPermissionPrompt: Bool,
        automationPermissionPrompt: Bool,
        pasteIntegrityLimit: String,
        adminRequired: Bool,
        startupMechanism: String,
        startupLauncher: String,
        startupLaunchMode: String,
        startupPermissionPrompt: Bool,
        screenCaptureRequired: Bool,
        screenRecordingPermissionPrompt: Bool
    ) {
        self.minimumPermissions = minimumPermissions
        self.osPermissionGrants = osPermissionGrants
        self.nativeCapabilities = nativeCapabilities
        self.microphoneSettingsPath = microphoneSettingsPath
        self.microphoneSettingsURI = microphoneSettingsURI
        self.requiresDesktopAppMicrophoneAccess = requiresDesktopAppMicrophoneAccess
        self.hotKeyPermissionPrompt = hotKeyPermissionPrompt
        self.pastePermissionPrompt = pastePermissionPrompt
        self.accessibilityPermissionPrompt = accessibilityPermissionPrompt
        self.automationPermissionPrompt = automationPermissionPrompt
        self.pasteIntegrityLimit = pasteIntegrityLimit
        self.adminRequired = adminRequired
        self.startupMechanism = startupMechanism
        self.startupLauncher = startupLauncher
        self.startupLaunchMode = startupLaunchMode
        self.startupPermissionPrompt = startupPermissionPrompt
        self.screenCaptureRequired = screenCaptureRequired
        self.screenRecordingPermissionPrompt = screenRecordingPermissionPrompt
    }

    public static let minimumMVP = WindowsPermissionSurface(
        minimumPermissions: ["microphone", "hotkey", "clipboard"],
        osPermissionGrants: ["microphone"],
        nativeCapabilities: [
            "RegisterHotKey",
            "WH_KEYBOARD_LL",
            "Win32 clipboard",
            "SendInput",
            "DPAPI",
            "user Startup folder shortcut"
        ],
        microphoneSettingsPath: "Settings > Privacy & security > Microphone",
        microphoneSettingsURI: "ms-settings:privacy-microphone",
        requiresDesktopAppMicrophoneAccess: true,
        hotKeyPermissionPrompt: false,
        pastePermissionPrompt: false,
        accessibilityPermissionPrompt: false,
        automationPermissionPrompt: false,
        pasteIntegrityLimit: "equal_or_lower",
        adminRequired: false,
        startupMechanism: "user_startup_folder_shortcut",
        startupLauncher: "run-windows-agent.ps1",
        startupLaunchMode: "listen",
        startupPermissionPrompt: false,
        screenCaptureRequired: false,
        screenRecordingPermissionPrompt: false
    )

    public var proofOutputLines: [String] {
        [
            "minimum_permission_surface=\(minimumPermissions.joined(separator: ","))",
            "os_permission_grants=\(osPermissionGrants.joined(separator: ","))",
            "native_capabilities=\(nativeCapabilities.joined(separator: ","))",
            "microphone_settings=\(microphoneSettingsPath)",
            "microphone_settings_uri=\(microphoneSettingsURI)",
            "desktop_app_microphone_access_required=\(requiresDesktopAppMicrophoneAccess)",
            "hotkey_permission_prompt=\(hotKeyPermissionPrompt)",
            "paste_permission_prompt=\(pastePermissionPrompt)",
            "accessibility_permission_prompt=\(accessibilityPermissionPrompt)",
            "automation_permission_prompt=\(automationPermissionPrompt)",
            "paste_integrity_limit=\(pasteIntegrityLimit)",
            "admin_required=\(adminRequired)",
            "startup_mechanism=\(startupMechanism)",
            "startup_launcher=\(startupLauncher)",
            "startup_launch_mode=\(startupLaunchMode)",
            "startup_permission_prompt=\(startupPermissionPrompt)",
            "screen_capture_required=\(screenCaptureRequired)",
            "screen_recording_permission_prompt=\(screenRecordingPermissionPrompt)"
        ]
    }
}
