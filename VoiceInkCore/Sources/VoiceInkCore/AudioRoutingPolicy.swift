import Foundation

public enum VoiceInkAudioRoutingPlatform: Sendable {
    case iOS
    case macOS
}

public enum VoiceInkPlatformAudioInputPolicy {
    public static func defaultMode(for platform: VoiceInkAudioRoutingPlatform) -> VoiceInkAudioInputMode {
        switch platform {
        case .iOS:
            return .systemDefault
        case .macOS:
            return .custom
        }
    }

    public static func normalizedIOSMode(_ mode: VoiceInkAudioInputMode) -> VoiceInkAudioInputMode {
        mode == .custom ? .custom : .systemDefault
    }

    public static func registeredDefaults(for platform: VoiceInkAudioRoutingPlatform) -> [String: Any] {
        [
            VoiceInkAudioInputPreference.inputModeKey: defaultMode(for: platform).rawValue
        ]
    }

    public static func inputMode(
        for platform: VoiceInkAudioRoutingPlatform,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkAudioInputMode {
        guard let rawValue = defaults.string(forKey: VoiceInkAudioInputPreference.inputModeKey),
              let storedMode = VoiceInkAudioInputMode(rawValue: rawValue) else {
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

public struct VoiceInkIOSAudioRouteSelection: Equatable, Sendable {
    public let inputMode: VoiceInkAudioInputMode
    public let preferredInputUID: String?
    public let usedSystemFallback: Bool

    public init(
        inputMode: VoiceInkAudioInputMode,
        preferredInputUID: String?,
        usedSystemFallback: Bool
    ) {
        self.inputMode = inputMode
        self.preferredInputUID = preferredInputUID
        self.usedSystemFallback = usedSystemFallback
    }
}

public enum VoiceInkIOSAudioRouteSelectionPolicy {
    public static func selection(
        inputMode: VoiceInkAudioInputMode,
        selectedInputUID: String?,
        availableInputUIDs: [String]
    ) -> VoiceInkIOSAudioRouteSelection {
        let normalizedMode = VoiceInkPlatformAudioInputPolicy.normalizedIOSMode(inputMode)
        guard normalizedMode == .custom,
              let selectedInputUID,
              availableInputUIDs.contains(selectedInputUID) else {
            return VoiceInkIOSAudioRouteSelection(
                inputMode: normalizedMode,
                preferredInputUID: nil,
                usedSystemFallback: normalizedMode == .custom
            )
        }

        return VoiceInkIOSAudioRouteSelection(
            inputMode: .custom,
            preferredInputUID: selectedInputUID,
            usedSystemFallback: false
        )
    }
}
