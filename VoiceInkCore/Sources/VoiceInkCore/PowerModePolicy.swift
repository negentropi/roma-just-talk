import Foundation

public struct VoiceInkPowerModeAppConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var appName: String

    public init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    public static func == (lhs: VoiceInkPowerModeAppConfig, rhs: VoiceInkPowerModeAppConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeAppRule {
        VoiceInkPowerModeAppRule(bundleIdentifier: bundleIdentifier, appName: appName)
    }
}

public struct VoiceInkPowerModeAppRule: Equatable, Sendable {
    public let bundleIdentifier: String
    public let appName: String

    public init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}

public struct VoiceInkPowerModeURLConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: String

    public init(id: UUID = UUID(), url: String) {
        self.id = id
        self.url = url
    }

    public static func == (lhs: VoiceInkPowerModeURLConfig, rhs: VoiceInkPowerModeURLConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeWebsiteRule {
        VoiceInkPowerModeWebsiteRule(url: url)
    }
}

public struct VoiceInkPowerModeWebsiteRule: Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct VoiceInkPowerModeRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let appRules: [VoiceInkPowerModeAppRule]
    public let websiteRules: [VoiceInkPowerModeWebsiteRule]
    public let isEnabled: Bool
    public let isDefault: Bool

    public init(
        id: UUID,
        name: String,
        appRules: [VoiceInkPowerModeAppRule] = [],
        websiteRules: [VoiceInkPowerModeWebsiteRule] = [],
        isEnabled: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.appRules = appRules
        self.websiteRules = websiteRules
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}

public enum VoiceInkAutoSendKey: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case enter = "enter"
    case shiftEnter = "shiftEnter"
    case commandEnter = "commandEnter"

    public static let allCases: [VoiceInkAutoSendKey] = [
        .none,
        .enter,
        .shiftEnter,
        .commandEnter
    ]

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .enter:
            return "Return (⏎)"
        case .shiftEnter:
            return "Shift + Return (⇧⏎)"
        case .commandEnter:
            return "Command + Return (⌘⏎)"
        }
    }

    public var isEnabled: Bool {
        self != .none
    }
}

public enum VoiceInkPowerModeSaveMode: Equatable, Sendable {
    case add
    case edit(UUID)
}

public enum VoiceInkPowerModeValidationError: Error, Equatable, Identifiable, Sendable {
    case emptyName
    case duplicateName(String)
    case duplicateAppTrigger(String, String)
    case duplicateWebsiteTrigger(String, String)

    public var id: String {
        switch self {
        case .emptyName:
            return "emptyName"
        case .duplicateName:
            return "duplicateName"
        case .duplicateAppTrigger:
            return "duplicateAppTrigger"
        case .duplicateWebsiteTrigger:
            return "duplicateWebsiteTrigger"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .emptyName:
            return "Power mode name cannot be empty."
        case .duplicateName(let name):
            return "A power mode with the name '\(name)' already exists."
        case .duplicateAppTrigger(let appName, let powerModeName):
            return "The app '\(appName)' is already configured in the '\(powerModeName)' power mode."
        case .duplicateWebsiteTrigger(let website, let powerModeName):
            return "The website '\(website)' is already configured in the '\(powerModeName)' power mode."
        }
    }
}

public enum VoiceInkPowerModePolicy {
    public static func normalizedWebsiteURL(_ url: String) -> String {
        url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hasEnabledAutomaticRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && (
                rule.isDefault ||
                !rule.appRules.isEmpty ||
                !rule.websiteRules.isEmpty
            )
        }
    }

    public static func hasEnabledWebsiteRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && !rule.websiteRules.isEmpty
        }
    }

    public static func matchingRule(
        forWebsiteURL url: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        let normalizedURL = normalizedWebsiteURL(url)

        for rule in rules where rule.isEnabled {
            for websiteRule in rule.websiteRules {
                let normalizedRuleURL = normalizedWebsiteURL(websiteRule.url)
                if normalizedURL.contains(normalizedRuleURL) {
                    return rule
                }
            }
        }

        return nil
    }

    public static func matchingRule(
        forAppBundleIdentifier bundleIdentifier: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.appRules.contains { appRule in
                appRule.bundleIdentifier == bundleIdentifier
            }
        }
    }

    public static func defaultRule(in rules: [VoiceInkPowerModeRule]) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.isDefault
        }
    }

    public static func validateForSave(
        candidate: VoiceInkPowerModeRule,
        mode: VoiceInkPowerModeSaveMode,
        existing rules: [VoiceInkPowerModeRule]
    ) -> [VoiceInkPowerModeValidationError] {
        var errors: [VoiceInkPowerModeValidationError] = []

        if candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        let comparableRules = rules.filter { rule in
            switch mode {
            case .add:
                return true
            case .edit(let editedID):
                return rule.id != editedID
            }
        }

        if comparableRules.contains(where: { $0.name == candidate.name }) {
            errors.append(.duplicateName(candidate.name))
        }

        for appRule in candidate.appRules {
            for existingRule in comparableRules {
                if existingRule.appRules.contains(where: { $0.bundleIdentifier == appRule.bundleIdentifier }) {
                    errors.append(.duplicateAppTrigger(appRule.appName, existingRule.name))
                }
            }
        }

        for websiteRule in candidate.websiteRules {
            for existingRule in comparableRules {
                if existingRule.websiteRules.contains(where: { $0.url == websiteRule.url }) {
                    errors.append(.duplicateWebsiteTrigger(websiteRule.url, existingRule.name))
                }
            }
        }

        return errors
    }
}
