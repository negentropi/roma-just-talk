import Foundation
import VoiceInkCore

enum MacOnboardingStage: String {
    case welcome
    case permissions
    case modelDownload
    case tutorial

    var resumesPermissionsView: Bool {
        self != .welcome
    }

    var resumesModelDownload: Bool {
        self == .modelDownload || self == .tutorial
    }

    var resumesTutorial: Bool {
        self == .tutorial
    }
}

enum MacOnboardingProgressStore {
    private static let stageKey = "macOSOnboardingStage"
    private static let permissionKindKey = "macOSOnboardingPermissionKind"

    static func stage(in defaults: UserDefaults = .standard) -> MacOnboardingStage {
        defaults.string(forKey: stageKey)
            .flatMap(MacOnboardingStage.init(rawValue:)) ?? .welcome
    }

    static func saveStage(_ stage: MacOnboardingStage, in defaults: UserDefaults = .standard) {
        defaults.set(stage.rawValue, forKey: stageKey)
    }

    static func permissionKind(in defaults: UserDefaults = .standard) -> VoiceInkMacOSOnboardingPermissionKind? {
        defaults.string(forKey: permissionKindKey)
            .flatMap(VoiceInkMacOSOnboardingPermissionKind.init(rawValue:))
    }

    static func savePermissionKind(
        _ kind: VoiceInkMacOSOnboardingPermissionKind,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(kind.rawValue, forKey: permissionKindKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: stageKey)
        defaults.removeObject(forKey: permissionKindKey)
    }
}
