import Foundation

public struct PowerModeConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]?
    public var urlConfigs: [VoiceInkPowerModeURLConfig]?
    public var isAIEnhancementEnabled: Bool
    public var selectedPrompt: String?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var useScreenCapture: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isEnabled: Bool
    public var isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, appConfigs, urlConfigs, isAIEnhancementEnabled, selectedPrompt, selectedLanguage, isTextFormattingEnabled, punctuationCleanupMode, removePunctuation, lowercaseTranscription, useScreenCapture, selectedAIProvider, selectedAIModel, isAutoSendEnabled, autoSendKey, isEnabled, isDefault
        case selectedWhisperModel
        case selectedTranscriptionModelName
    }

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig]? = nil,
        urlConfigs: [VoiceInkPowerModeURLConfig]? = nil,
        isAIEnhancementEnabled: Bool,
        selectedPrompt: String? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPrompt = selectedPrompt
        self.useScreenCapture = useScreenCapture
        self.autoSendKey = autoSendKey
        self.selectedAIProvider = selectedAIProvider ?? VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
        self.selectedAIModel = selectedAIModel
        self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? VoiceInkCurrentTranscriptionModelPreference.modelName()
        self.selectedLanguage = selectedLanguage ?? VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage()
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        appConfigs = try container.decodeIfPresent([VoiceInkPowerModeAppConfig].self, forKey: .appConfigs)
        urlConfigs = try container.decodeIfPresent([VoiceInkPowerModeURLConfig].self, forKey: .urlConfigs)
        isAIEnhancementEnabled = try container.decode(Bool.self, forKey: .isAIEnhancementEnabled)
        selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled) ?? false
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            let removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation) ?? false
            punctuationCleanupMode = removePunctuation ? .removeAll : .keep
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription) ?? false
        useScreenCapture = try container.decode(Bool.self, forKey: .useScreenCapture)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .autoSendKey),
           let newKey = VoiceInkAutoSendKey(rawValue: rawValue) {
            autoSendKey = newKey
        } else if let oldBool = try container.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled), oldBool {
            autoSendKey = .enter
        } else {
            autoSendKey = .none
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        if let newModelName = try container.decodeIfPresent(String.self, forKey: .selectedTranscriptionModelName) {
            selectedTranscriptionModelName = newModelName
        } else if let oldModelName = try container.decodeIfPresent(String.self, forKey: .selectedWhisperModel) {
            selectedTranscriptionModelName = oldModelName
        } else {
            selectedTranscriptionModelName = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encodeIfPresent(appConfigs, forKey: .appConfigs)
        try container.encodeIfPresent(urlConfigs, forKey: .urlConfigs)
        try container.encode(isAIEnhancementEnabled, forKey: .isAIEnhancementEnabled)
        try container.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encode(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encode(punctuationCleanupMode == .removeAll, forKey: .removePunctuation)
        try container.encode(lowercaseTranscription, forKey: .lowercaseTranscription)
        try container.encode(useScreenCapture, forKey: .useScreenCapture)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encode(autoSendKey, forKey: .autoSendKey)
        try container.encodeIfPresent(selectedTranscriptionModelName, forKey: .selectedTranscriptionModelName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isDefault, forKey: .isDefault)
    }

    public static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool {
        lhs.id == rhs.id
    }
}

public struct VoiceInkPowerModeApplicationState: Codable, Equatable, Sendable {
    public var isEnhancementEnabled: Bool
    public var useScreenCaptureContext: Bool
    public var selectedPromptId: String?
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var selectedLanguage: String?
    public var transcriptionModelName: String?
    public var isTextFormattingEnabled: Bool?
    public var punctuationCleanupMode: PunctuationCleanupMode?
    public var removePunctuation: Bool?
    public var lowercaseTranscription: Bool?

    private enum CodingKeys: String, CodingKey {
        case isEnhancementEnabled
        case useScreenCaptureContext
        case selectedPromptId
        case selectedAIProvider
        case selectedAIModel
        case selectedLanguage
        case transcriptionModelName
        case isTextFormattingEnabled
        case punctuationCleanupMode
        case removePunctuation
        case lowercaseTranscription
    }

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        selectedPromptId: String? = nil,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        selectedLanguage: String? = nil,
        transcriptionModelName: String? = nil,
        isTextFormattingEnabled: Bool? = nil,
        punctuationCleanupMode: PunctuationCleanupMode? = nil,
        removePunctuation: Bool? = nil,
        lowercaseTranscription: Bool? = nil
    ) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.useScreenCaptureContext = useScreenCaptureContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.removePunctuation = removePunctuation
        self.lowercaseTranscription = lowercaseTranscription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnhancementEnabled = try container.decode(Bool.self, forKey: .isEnhancementEnabled)
        useScreenCaptureContext = try container.decode(Bool.self, forKey: .useScreenCaptureContext)
        selectedPromptId = try container.decodeIfPresent(String.self, forKey: .selectedPromptId)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled)
        removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation)
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            punctuationCleanupMode = removePunctuation.map { $0 ? .removeAll : .keep }
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnhancementEnabled, forKey: .isEnhancementEnabled)
        try container.encode(useScreenCaptureContext, forKey: .useScreenCaptureContext)
        try container.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encodeIfPresent(transcriptionModelName, forKey: .transcriptionModelName)
        try container.encodeIfPresent(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encodeIfPresent(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encodeIfPresent(removePunctuation, forKey: .removePunctuation)
        try container.encodeIfPresent(lowercaseTranscription, forKey: .lowercaseTranscription)
    }
}

public struct VoiceInkPowerModeSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var originalState: VoiceInkPowerModeApplicationState

    public init(id: UUID, startTime: Date, originalState: VoiceInkPowerModeApplicationState) {
        self.id = id
        self.startTime = startTime
        self.originalState = originalState
    }
}

public extension Array where Element == PowerModeConfig {
    var powerModePolicyRules: [VoiceInkPowerModeRule] {
        map(\.powerModePolicyRule)
    }

    var enabledPowerModeConfigurations: [PowerModeConfig] {
        filter(\.isEnabled)
    }

    var enabledPowerModeConfigurationIds: Set<UUID> {
        Set(enabledPowerModeConfigurations.map(\.id))
    }

    var hasPowerModeDefaultConfiguration: Bool {
        contains { $0.isDefault }
    }

    var hasEnabledAutomaticRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: powerModePolicyRules)
    }

    var hasEnabledURLRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: powerModePolicyRules)
    }

    func powerModeConfiguration(with id: UUID) -> PowerModeConfig? {
        first { $0.id == id }
    }

    func powerModeConfiguration(forWebsiteURL url: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: url,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    func powerModeConfiguration(forAppBundleIdentifier bundleIdentifier: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forAppBundleIdentifier: bundleIdentifier,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    var defaultPowerModeConfiguration: PowerModeConfig? {
        guard let defaultRule = VoiceInkPowerModePolicy.defaultRule(
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: defaultRule.id)
    }

    func resolvedPowerModeConfiguration(
        explicitID: UUID? = nil,
        websiteURL: String? = nil,
        appBundleIdentifier: String? = nil
    ) -> PowerModeConfig? {
        if let explicitID,
           let config = powerModeConfiguration(with: explicitID) {
            return config
        }

        guard websiteURL != nil || appBundleIdentifier != nil else {
            return nil
        }

        guard hasEnabledAutomaticRules else {
            return nil
        }

        if let websiteURL,
           let config = powerModeConfiguration(forWebsiteURL: websiteURL) {
            return config
        }

        if let appBundleIdentifier,
           let config = powerModeConfiguration(forAppBundleIdentifier: appBundleIdentifier) {
            return config
        }

        return defaultPowerModeConfiguration
    }

    func containsPowerModeEmoji(_ emoji: String) -> Bool {
        contains { $0.emoji == emoji }
    }

    @discardableResult
    mutating func appendPowerModeConfigurationIfMissing(_ config: PowerModeConfig) -> Bool {
        guard powerModeConfiguration(with: config.id) == nil else {
            return false
        }

        append(config)
        return true
    }

    @discardableResult
    mutating func updatePowerModeConfiguration(_ config: PowerModeConfig) -> Bool {
        guard let index = firstIndex(where: { $0.id == config.id }) else {
            return false
        }

        self[index] = config
        return true
    }

    @discardableResult
    mutating func removePowerModeConfiguration(with id: UUID) -> Bool {
        let originalCount = count
        removeAll { $0.id == id }
        return count != originalCount
    }

    mutating func movePowerModeConfigurations(fromOffsets offsets: IndexSet, toOffset: Int) {
        let validOffsets = offsets
            .filter { indices.contains($0) }
            .sorted()
        guard !validOffsets.isEmpty else { return }

        let configurationsToMove = validOffsets.map { self[$0] }
        for index in validOffsets.reversed() {
            remove(at: index)
        }

        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let insertionIndex = Swift.max(0, Swift.min(toOffset - removedBeforeDestination, count))
        insert(contentsOf: configurationsToMove, at: insertionIndex)
    }

    mutating func setPowerModeDefaultConfiguration(id configID: UUID) {
        for index in indices {
            self[index].isDefault = false
        }

        if let index = firstIndex(where: { $0.id == configID }) {
            self[index].isDefault = true
        }
    }

    @discardableResult
    mutating func setPowerModeConfiguration(id configID: UUID, isEnabled: Bool) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].isEnabled = isEnabled
        return true
    }

    @discardableResult
    mutating func addPowerModeAppConfig(
        _ appConfig: VoiceInkPowerModeAppConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].appConfigs ?? []
        configs.append(appConfig)
        self[index].appConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeAppConfig(
        id appConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].appConfigs?.removeAll { $0.id == appConfigID }
        return true
    }

    @discardableResult
    mutating func addPowerModeURLConfig(
        _ urlConfig: VoiceInkPowerModeURLConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].urlConfigs ?? []
        configs.append(urlConfig)
        self[index].urlConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeURLConfig(
        id urlConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].urlConfigs?.removeAll { $0.id == urlConfigID }
        return true
    }
}

public extension PowerModeConfig {
    var powerModePolicyRule: VoiceInkPowerModeRule {
        VoiceInkPowerModeRule(
            id: id,
            name: name,
            appRules: (appConfigs ?? []).map(\.rule),
            websiteRules: (urlConfigs ?? []).map(\.rule),
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }
}

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
