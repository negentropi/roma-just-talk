import Foundation
import VoiceInkCore

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var activeConfiguration: PowerModeConfig?

    private init() {
        let loadedConfigurations = VoiceInkPowerModeConfigurationPreference.loadConfigurations()
        configurations = loadedConfigurations
        VoiceInkPowerModeActiveConfigurationRestorePlan.restoring(
            configurations: loadedConfigurations,
            activeConfigurationID: VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId()
        ).applyRuntimeState { activeConfiguration = $0 }
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

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(config?.id)
        self.objectWillChange.send()
    }

    func activateConfiguration(_ config: PowerModeConfig?) async {
        await VoiceInkPowerModeActivationPlan.activating(config).applyRuntimeState(
            setActiveConfiguration: { config in
                await MainActor.run {
                    self.setActiveConfiguration(config)
                }
            },
            beginSession: { config in
                await PowerModeSessionManager.shared.beginSession(with: config)
            }
        )
    }
}
