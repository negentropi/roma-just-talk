import Foundation

public struct VoiceInkSettingsPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let modesSectionTitle: String
    public let addModeButtonTitle: String
    public let addActionSystemImageName: String
    public let debugSectionTitle: String
    public let resetAllAppDataButtonTitle: String
    public let resetAllAppDataSystemImageName: String

    public static let iOS = VoiceInkSettingsPresentation(
        navigationTitle: "Settings",
        modesSectionTitle: "Modes",
        addModeButtonTitle: "Add New Mode",
        addActionSystemImageName: "plus.circle.fill",
        debugSectionTitle: "Debug",
        resetAllAppDataButtonTitle: "Reset All App Data",
        resetAllAppDataSystemImageName: "trash"
    )
}

public struct VoiceInkMacOSSettingsPresentation: Equatable, Sendable {
    public let generalSectionTitle: String
    public let showMenuBarIconTitle: String
    public let hideDockIconTitle: String
    public let launchAtLoginTitle: String
    public let autoCheckUpdatesTitle: String
    public let showAnnouncementsTitle: String
    public let checkForUpdatesButtonTitle: String
    public let privacySectionTitle: String
    public let privacyFooterText: String
    public let backupSectionTitle: String
    public let backupFooterText: String
    public let exportSettingsLabel: String
    public let exportButtonTitle: String
    public let importSettingsLabel: String
    public let importButtonTitle: String
    public let diagnosticsSectionTitle: String

    public static let macOS = VoiceInkMacOSSettingsPresentation(
        generalSectionTitle: "General",
        showMenuBarIconTitle: "Show in Menu Bar",
        hideDockIconTitle: "Hide Dock Icon",
        launchAtLoginTitle: "Launch at Login",
        autoCheckUpdatesTitle: "Auto-check Updates",
        showAnnouncementsTitle: "Show Announcements",
        checkForUpdatesButtonTitle: "Check for Updates",
        privacySectionTitle: "Privacy",
        privacyFooterText: "Control how VoiceInk handles your transcription data and audio recordings.",
        backupSectionTitle: "Backup",
        backupFooterText: "Export all settings, or choose specific categories when importing a backup.",
        exportSettingsLabel: "Export Settings",
        exportButtonTitle: "Export",
        importSettingsLabel: "Import Settings",
        importButtonTitle: "Import",
        diagnosticsSectionTitle: "Diagnostics"
    )
}
