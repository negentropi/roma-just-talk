import Foundation

public enum RomaAudioRoutingPlatform: Sendable {
    case iOS
    case macOS
}

public enum RomaPlatformAudioInputPolicy {
    public static func defaultMode(for platform: RomaAudioRoutingPlatform) -> RomaAudioInputMode {
        switch platform {
        case .iOS:
            return .systemDefault
        case .macOS:
            return .custom
        }
    }

    public static func normalizedIOSMode(_ mode: RomaAudioInputMode) -> RomaAudioInputMode {
        mode == .custom ? .custom : .systemDefault
    }

    public static func registeredDefaults(for platform: RomaAudioRoutingPlatform) -> [String: Any] {
        [
            RomaAudioInputPreference.inputModeKey: defaultMode(for: platform).rawValue
        ]
    }

    public static func inputMode(
        for platform: RomaAudioRoutingPlatform,
        from defaults: UserDefaults = .standard
    ) -> RomaAudioInputMode {
        guard let rawValue = defaults.string(forKey: RomaAudioInputPreference.inputModeKey),
              let storedMode = RomaAudioInputMode(rawValue: rawValue) else {
            return defaultMode(for: platform)
        }

        switch platform {
        case .iOS:
            return normalizedIOSMode(storedMode)
        case .macOS:
            return storedMode
        }
    }
}

public struct RomaIOSAudioRouteSelection: Equatable, Sendable {
    public let inputMode: RomaAudioInputMode
    public let preferredInputUID: String?
    public let usedSystemFallback: Bool

    public init(
        inputMode: RomaAudioInputMode,
        preferredInputUID: String?,
        usedSystemFallback: Bool
    ) {
        self.inputMode = inputMode
        self.preferredInputUID = preferredInputUID
        self.usedSystemFallback = usedSystemFallback
    }
}

public enum RomaIOSAudioRouteSelectionPolicy {
    public static func selection(
        inputMode: RomaAudioInputMode,
        selectedInputUID: String?,
        availableInputUIDs: [String]
    ) -> RomaIOSAudioRouteSelection {
        let normalizedMode = RomaPlatformAudioInputPolicy.normalizedIOSMode(inputMode)
        guard normalizedMode == .custom,
              let selectedInputUID,
              availableInputUIDs.contains(selectedInputUID) else {
            return RomaIOSAudioRouteSelection(
                inputMode: normalizedMode,
                preferredInputUID: nil,
                usedSystemFallback: normalizedMode == .custom
            )
        }

        return RomaIOSAudioRouteSelection(
            inputMode: .custom,
            preferredInputUID: selectedInputUID,
            usedSystemFallback: false
        )
    }
}
