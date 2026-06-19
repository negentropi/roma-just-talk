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
