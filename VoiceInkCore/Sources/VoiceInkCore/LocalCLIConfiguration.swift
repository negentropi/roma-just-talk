import Foundation

public struct VoiceInkMacOSLocalCLISettingsPresentation: Equatable, Sendable {
    public let commandTitle: String
    public let loadTemplateButtonTitle: String
    public let timeoutPickerTitle: String
    public let environmentHelpText: String
    public let configurationRequiredHelpText: String

    public static let macOS = VoiceInkMacOSLocalCLISettingsPresentation(
        commandTitle: "Command",
        loadTemplateButtonTitle: "Load Template",
        timeoutPickerTitle: "Timeout",
        environmentHelpText: "Environment variables available: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT. VoiceInk also writes VOICEINK_FULL_PROMPT to stdin for every command.",
        configurationRequiredHelpText: "Load a template or enter a command to enable Local CLI enhancement."
    )
}

public enum VoiceInkLocalCLITemplate: String, CaseIterable, Identifiable, Sendable {
    case pi
    case claude
    case codex
    case copilot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pi:
            return "Pi"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .copilot:
            return "Copilot"
        }
    }

    public var commandTemplate: String {
        switch self {
        case .pi:
            return "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        case .claude:
            return "claude -p \"$VOICEINK_FULL_PROMPT\""
        case .codex:
            return "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --output-last-message \"$TMPFILE\" \"$VOICEINK_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        case .copilot:
            return "copilot -p \"$VOICEINK_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        }
    }
}

public enum VoiceInkLocalCLIPreference {
    public static let commandTemplateKey = "localCLICommandTemplate"
    public static let selectedTemplateKey = "localCLISelectedTemplate"
    public static let timeoutSecondsKey = "localCLITimeoutSeconds"
    public static let macOSSettingsPresentation = VoiceInkMacOSLocalCLISettingsPresentation.macOS
    public static let defaultTimeoutSeconds: Double = 45
    public static let minimumTimeoutSeconds: Double = 5
    public static let timeoutOptions: [Double] = [15, 30, 45, 60, 90, 120, 180, 300]

    public static func commandTemplate(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: commandTemplateKey) ?? ""
    }

    public static func saveCommandTemplate(
        _ commandTemplate: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(commandTemplate, forKey: commandTemplateKey)
    }

    public static func selectedTemplate(from defaults: UserDefaults = .standard) -> VoiceInkLocalCLITemplate {
        guard let rawValue = defaults.string(forKey: selectedTemplateKey),
              let template = VoiceInkLocalCLITemplate(rawValue: rawValue)
        else {
            return .pi
        }

        return template
    }

    public static func saveSelectedTemplate(
        _ template: VoiceInkLocalCLITemplate,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(template.rawValue, forKey: selectedTemplateKey)
    }

    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Double {
        let storedTimeout = defaults.double(forKey: timeoutSecondsKey)
        guard storedTimeout > 0 else {
            return defaultTimeoutSeconds
        }

        return storedTimeout
    }

    public static func saveTimeoutSeconds(
        _ timeoutSeconds: Double,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(boundedTimeoutSeconds(timeoutSeconds), forKey: timeoutSecondsKey)
    }

    public static func boundedTimeoutSeconds(_ timeoutSeconds: Double) -> Double {
        max(minimumTimeoutSeconds, timeoutSeconds)
    }

    public static func timeoutLabel(for timeoutSeconds: Double) -> String {
        "\(Int(timeoutSeconds))s"
    }

    public static func isCommandConfigured(_ commandTemplate: String) -> Bool {
        !commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func fullPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        <SYSTEM_PROMPT>
        \(systemPrompt)
        </SYSTEM_PROMPT>

        <USER_PROMPT>
        \(userPrompt)
        </USER_PROMPT>
        """
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: commandTemplateKey)
        defaults.removeObject(forKey: selectedTemplateKey)
        defaults.removeObject(forKey: timeoutSecondsKey)
    }
}
