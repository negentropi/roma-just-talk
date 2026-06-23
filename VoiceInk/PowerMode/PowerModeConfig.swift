import Foundation
import VoiceInkCore

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var activeConfiguration: PowerModeConfig?

    private init() {
        configurations = VoiceInkPowerModeConfigurationPreference.loadConfigurations()

        if let activeConfigId = VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId() {
            activeConfiguration = configurations.powerModeConfiguration(with: activeConfigId)
        } else {
            activeConfiguration = nil
        }
    }

    func saveConfigurations() {
        VoiceInkPowerModeConfigurationPreference.saveConfigurations(configurations)
        NotificationCenter.default.post(name: .powerModeConfigurationsDidChange, object: nil)
    }

    @discardableResult
    func saveConfiguration(_ config: PowerModeConfig, mode: VoiceInkPowerModeSaveMode) -> Bool {
        let previousEnabledConfigIds = enabledConfigurationIds
        let didSave = configurations.savePowerModeConfiguration(config, mode: mode)

        if didSave {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }

        return didSave
    }

    func removeConfiguration(with id: UUID) {
        let previousEnabledConfigIds = enabledConfigurationIds
        ShortcutStore.removeShortcutStorage(for: .powerMode(id))
        configurations.removePowerModeConfiguration(with: id)
        saveConfigurations()
        postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
    }

    func updateConfiguration(_ config: PowerModeConfig) {
        let previousEnabledConfigIds = enabledConfigurationIds
        if configurations.updatePowerModeConfiguration(config) {
            saveConfigurations()
            postShortcutAvailabilityChangeIfNeeded(previousEnabledConfigIds: previousEnabledConfigIds)
        }
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        configurations.movePowerModeConfigurations(fromOffsets: fromOffsets, toOffset: toOffset)
        saveConfigurations()
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

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(config?.id)
        self.objectWillChange.send()
    }
}
