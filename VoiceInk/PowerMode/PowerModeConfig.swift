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
        applyConfigurationMutationPlan(
            .saving(config, mode: mode, in: configurations)
        )
    }

    func removeConfiguration(with id: UUID) {
        applyConfigurationMutationPlan(
            .removing(id: id, from: configurations)
        )
    }

    func updateConfiguration(_ config: PowerModeConfig) {
        applyConfigurationMutationPlan(
            .updating(config, in: configurations)
        )
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        applyConfigurationMutationPlan(
            .moving(fromOffsets: fromOffsets, toOffset: toOffset, in: configurations)
        )
    }

    func enableConfiguration(with id: UUID) {
        applyConfigurationMutationPlan(
            .settingEnabled(id: id, isEnabled: true, in: configurations)
        )
    }
    
    func disableConfiguration(with id: UUID) {
        applyConfigurationMutationPlan(
            .settingEnabled(id: id, isEnabled: false, in: configurations)
        )
    }

    private func postShortcutAvailabilityDidChange() {
        NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
    }

    @discardableResult
    private func applyConfigurationMutationPlan(_ plan: VoiceInkPowerModeConfigurationMutationPlan) -> Bool {
        plan.applyRuntimeState(
            setConfigurations: { configurations = $0 },
            removeShortcutStorageForConfiguration: { id in
                ShortcutStore.removeShortcutStorage(for: .powerMode(id))
            },
            saveConfigurations: saveConfigurations,
            postShortcutAvailabilityDidChange: postShortcutAvailabilityDidChange
        )
        return plan.didMutate
    }

    func addAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, to config: PowerModeConfig) {
        applyConfigurationMutationPlan(
            .addingAppConfig(appConfig, toConfigurationID: config.id, in: configurations)
        )
    }

    func removeAppConfig(_ appConfig: VoiceInkPowerModeAppConfig, from config: PowerModeConfig) {
        applyConfigurationMutationPlan(
            .removingAppConfig(id: appConfig.id, fromConfigurationID: config.id, in: configurations)
        )
    }

    func addURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, to config: PowerModeConfig) {
        applyConfigurationMutationPlan(
            .addingURLConfig(urlConfig, toConfigurationID: config.id, in: configurations)
        )
    }

    func removeURLConfig(_ urlConfig: VoiceInkPowerModeURLConfig, from config: PowerModeConfig) {
        applyConfigurationMutationPlan(
            .removingURLConfig(id: urlConfig.id, fromConfigurationID: config.id, in: configurations)
        )
    }

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(config?.id)
        self.objectWillChange.send()
    }
}
