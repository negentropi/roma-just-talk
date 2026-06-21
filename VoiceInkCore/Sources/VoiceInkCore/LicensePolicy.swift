import Foundation

public enum VoiceInkLicensePreference {
    public static let requiresActivationKey = "VoiceInkLicenseRequiresActivation"
    public static let hasLaunchedBeforeKey = "VoiceInkHasLaunchedBefore"
    public static let activationsLimitKey = "VoiceInkActivationsLimit"

    public static func requiresActivation(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: requiresActivationKey)
    }

    public static func saveRequiresActivation(_ requiresActivation: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(requiresActivation, forKey: requiresActivationKey)
    }

    public static func hasLaunchedBefore(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hasLaunchedBeforeKey)
    }

    public static func saveHasLaunchedBefore(_ hasLaunchedBefore: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(hasLaunchedBefore, forKey: hasLaunchedBeforeKey)
    }

    public static func activationsLimit(from defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: activationsLimitKey)
    }

    public static func saveActivationsLimit(_ limit: Int, to defaults: UserDefaults = .standard) {
        defaults.set(limit, forKey: activationsLimitKey)
    }

    public static func hasUsableStoredLicense(
        licenseKey: String?,
        activationId: String?,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        guard licenseKey != nil else { return false }
        return activationId != nil || !requiresActivation(from: defaults)
    }
}
