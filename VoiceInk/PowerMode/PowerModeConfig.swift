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
            activeConfiguration = configurations.powerModeConfiguration(with: activeConfigId)
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
        let previousEnabledConfigIds = enabledConfigurationIds
        if configurations.appendPowerModeConfigurationIfMissing(config) {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func removeConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        ShortcutStore.removeShortcutStorage(for: .powerMode(id))
        configurations.removePowerModeConfiguration(with: id)
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func getConfiguration(with id: UUID) -> PowerModeConfig? {
        return configurations.powerModeConfiguration(with: id)
    }

    func updateConfiguration(_ config: PowerModeConfig) {
        let previousEnabledConfigIds = enabledConfigurationIds
        if configurations.updatePowerModeConfiguration(config) {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        configurations.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveConfigurations()
    }

    func getConfigurationForURL(_ url: String) -> PowerModeConfig? {
        configurations.powerModeConfiguration(forWebsiteURL: url)
    }
    
    func getConfigurationForApp(_ bundleId: String) -> PowerModeConfig? {
        configurations.powerModeConfiguration(forAppBundleIdentifier: bundleId)
    }
    
    func getDefaultConfiguration() -> PowerModeConfig? {
        configurations.defaultPowerModeConfiguration
    }
    
    func hasDefaultConfiguration() -> Bool {
        return configurations.hasPowerModeDefaultConfiguration
    }
    
    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        configurations.setPowerModeDefaultConfiguration(id: configId)

        if !skipSave {
            saveConfigurations()
        }
    }
    
    func enableConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        if configurations.setPowerModeConfiguration(id: id, isEnabled: true) {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }
    
    func disableConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        if configurations.setPowerModeConfiguration(id: id, isEnabled: false) {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }
    
    var enabledConfigurations: [PowerModeConfig] {
        configurations.enabledPowerModeConfigurations
    }

    private var enabledConfigurationIds: Set<UUID> {
        configurations.enabledPowerModeConfigurationIds
    }

    private func postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: Set<UUID>) {
        guard previousEnabledConfigIds != enabledConfigurationIds else {
            return
        }

        NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
    }

    func addAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, to config: PowerModeConfig) {
        if configurations.addPowerModeAppConfig(appConfig, toConfigurationID: config.id) {
            saveConfigurations()
        }
    }

    func removeAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, from config: PowerModeConfig) {
        if configurations.removePowerModeAppConfig(id: appConfig.id, fromConfigurationID: config.id) {
            saveConfigurations()
        }
    }

    func addURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, to config: PowerModeConfig) {
        if configurations.addPowerModeURLConfig(urlConfig, toConfigurationID: config.id) {
            saveConfigurations()
        }
    }

    func removeURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, from config: PowerModeConfig) {
        if configurations.removePowerModeURLConfig(id: urlConfig.id, fromConfigurationID: config.id) {
            saveConfigurations()
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
        return configurations.containsPowerModeEmoji(emoji)
    }
} 
