import Foundation
import VoiceInkCore

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var activeConfiguration: PowerModeConfig?

    private let configKey = VoiceInkUserDefaultsKey.powerModeConfigurations
    private let activeConfigIdKey = "activeConfigurationId"

    private init() {
        loadConfigurations()

        if let activeConfigIdString = UserDefaults.standard.string(forKey: activeConfigIdKey),
           let activeConfigId = UUID(uuidString: activeConfigIdString) {
            activeConfiguration = configurations.first { $0.id == activeConfigId }
        } else {
            activeConfiguration = nil
        }
    }

    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let configs = try? JSONDecoder().decode([PowerModeConfig].self, from: data) {
            configurations = configs
        }
    }

    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        NotificationCenter.default.post(name: .powerModeConfigurationsDidChange, object: nil)
    }

    func addConfiguration(_ config: PowerModeConfig) {
        if !configurations.contains(where: { $0.id == config.id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations.append(config)
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func removeConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        ShortcutStore.removeShortcutStorage(for: .powerMode(id))
        configurations.removeAll { $0.id == id }
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func getConfiguration(with id: UUID) -> PowerModeConfig? {
        return configurations.first { $0.id == id }
    }

    func updateConfiguration(_ config: PowerModeConfig) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index] = config
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        configurations.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveConfigurations()
    }

    func getConfigurationForURL(_ url: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: url,
            in: configurations.powerModePolicyRules
        ) else { return nil }

        return configurations.first { $0.id == matchingRule.id }
    }
    
    func getConfigurationForApp(_ bundleId: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forAppBundleIdentifier: bundleId,
            in: configurations.powerModePolicyRules
        ) else { return nil }

        return configurations.first { $0.id == matchingRule.id }
    }
    
    func getDefaultConfiguration() -> PowerModeConfig? {
        guard let defaultRule = VoiceInkPowerModePolicy.defaultRule(
            in: configurations.powerModePolicyRules
        ) else { return nil }

        return configurations.first { $0.id == defaultRule.id }
    }
    
    func hasDefaultConfiguration() -> Bool {
        return configurations.contains { $0.isDefault }
    }
    
    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        for index in configurations.indices {
            configurations[index].isDefault = false
        }

        if let index = configurations.firstIndex(where: { $0.id == configId }) {
            configurations[index].isDefault = true
        }

        if !skipSave {
            saveConfigurations()
        }
    }
    
    func enableConfiguration(with id: UUID) {
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index].isEnabled = true
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }
    
    func disableConfiguration(with id: UUID) {
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let previousEnabledConfigIds = enabledConfigurationIds
            configurations[index].isEnabled = false
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }
    
    var enabledConfigurations: [PowerModeConfig] {
        return configurations.filter { $0.isEnabled }
    }

    private var enabledConfigurationIds: Set<UUID> {
        Set(enabledConfigurations.map(\.id))
    }

    private func postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: Set<UUID>) {
        guard previousEnabledConfigIds != enabledConfigurationIds else {
            return
        }

        NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
    }

    func addAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, to config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.appConfigs ?? []
            configs.append(appConfig)
            updatedConfig.appConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, from config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.appConfigs?.removeAll(where: { $0.id == appConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func addURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, to config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            var configs = updatedConfig.urlConfigs ?? []
            configs.append(urlConfig)
            updatedConfig.urlConfigs = configs
            updateConfiguration(updatedConfig)
        }
    }

    func removeURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, from config: PowerModeConfig) {
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.urlConfigs?.removeAll(where: { $0.id == urlConfig.id })
            updateConfiguration(updatedConfig)
        }
    }

    func cleanURL(_ url: String) -> String {
        VoiceInkPowerModePolicy.normalizedWebsiteURL(url)
    }

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        UserDefaults.standard.set(config?.id.uuidString, forKey: activeConfigIdKey)
        self.objectWillChange.send()
    }

    var currentActiveConfiguration: PowerModeConfig? {
        return activeConfiguration
    }

    func getAllAvailableConfigurations() -> [PowerModeConfig] {
        return configurations
    }

    func isEmojiInUse(_ emoji: String) -> Bool {
        return configurations.contains { $0.emoji == emoji }
    }
} 
