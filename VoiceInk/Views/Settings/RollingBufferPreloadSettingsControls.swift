import SwiftUI
import VoiceInkCore

struct RollingBufferPreloadSettingsControls: View {
    @AppStorage(VoiceInkRollingBufferPreloadSettings.modeKey) private var modeRaw = VoiceInkRollingBufferPreloadSettings.defaultMode.rawValue
    @AppStorage(VoiceInkRollingBufferPreloadSettings.autoDisableCloudModelsKey) private var autoDisableCloudModels = VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesCloudModels
    @AppStorage(VoiceInkRollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey) private var autoDisableLowBatteryLocalModels = VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesLowBatteryLocalModels
    @AppStorage(VoiceInkRollingBufferPreloadSettings.lowBatteryThresholdPercentKey) private var lowBatteryThresholdPercent = VoiceInkRollingBufferPreloadSettings.defaultLowBatteryThresholdPercent
    @AppStorage(VoiceInkRollingBufferPreloadSettings.bufferDurationSecondsKey) private var bufferDurationSeconds = VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds
    @AppStorage(VoiceInkRollingBufferPreloadSettings.preRunFinalizationKey) private var preRunFinalization = VoiceInkRollingBufferPreloadSettings.defaultPreRunFinalization
    @AppStorage(VoiceInkRollingBufferVADSettings.modelKey)
    private var rollingBufferVADModel = VoiceInkRollingBufferVADSettings.defaultModel.rawValue
    private static let presentation = VoiceInkRollingBufferPreloadSettings.macOSSettingsPresentation

    private var mode: Binding<VoiceInkRollingBufferPreloadMode> {
        Binding(
            get: {
                VoiceInkRollingBufferPreloadSettings.preloadModeSelection(fromStoredRawValue: modeRaw)
            },
            set: { newMode in
                modeRaw = newMode.rawValue
                notifySettingsChanged()
            }
        )
    }

    private var durationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: VoiceInkRollingBufferPreloadSettings.minimumBufferDurationSeconds)
        formatter.maximum = NSNumber(value: VoiceInkRollingBufferPreloadSettings.maximumBufferDurationSeconds)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }

    var body: some View {
        Picker(selection: mode) {
            ForEach(VoiceInkRollingBufferPreloadMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        } label: {
            HStack(spacing: 4) {
                Text(Self.presentation.modePickerTitle)
                InfoTip(Self.presentation.modePickerHelp)
            }
        }
        .pickerStyle(.segmented)

        LabeledContent(Self.presentation.durationLabel) {
            HStack(spacing: 6) {
                TextField("", value: $bufferDurationSeconds, formatter: durationFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .onSubmit(normalizeDuration)
                    .onChange(of: bufferDurationSeconds) { _, _ in
                        normalizeDuration()
                    }
                Text(Self.presentation.durationUnitLabel)
                    .foregroundColor(.secondary)
            }
        }

        Toggle(isOn: $preRunFinalization) {
            HStack(spacing: 4) {
                Text(Self.presentation.preRunFinalizationTitle)
                InfoTip(Self.presentation.preRunFinalizationHelp)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: preRunFinalization) { _, _ in notifySettingsChanged() }

        Picker(selection: $rollingBufferVADModel) {
            ForEach(VoiceInkRollingBufferVADModel.allCases) { model in
                Text(model.displayName).tag(model.rawValue)
            }
        } label: {
            HStack(spacing: 4) {
                Text(Self.presentation.vadModelPickerTitle)
                InfoTip(Self.presentation.vadModelPickerHelp)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: rollingBufferVADModel) { _, _ in notifySettingsChanged() }

        if mode.wrappedValue == .auto {
            Toggle(isOn: $autoDisableCloudModels) {
                HStack(spacing: 4) {
                    Text(Self.presentation.autoDisableCloudModelsTitle)
                    InfoTip(Self.presentation.autoDisableCloudModelsHelp)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoDisableCloudModels) { _, _ in notifySettingsChanged() }

            Toggle(isOn: $autoDisableLowBatteryLocalModels) {
                HStack(spacing: 4) {
                    Text(Self.presentation.autoDisableLowBatteryLocalModelsTitle)
                    InfoTip(Self.presentation.autoDisableLowBatteryLocalModelsHelp)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoDisableLowBatteryLocalModels) { _, _ in notifySettingsChanged() }

            if autoDisableLowBatteryLocalModels {
                Stepper(
                    Self.presentation.batteryCutoffLabel(percent: lowBatteryThresholdPercent),
                    value: $lowBatteryThresholdPercent,
                    in: 1...100,
                    step: 1
                )
                .onChange(of: lowBatteryThresholdPercent) { _, _ in notifySettingsChanged() }
            }
        }
    }

    private func normalizeDuration() {
        let normalized = VoiceInkRollingBufferPreloadSettings.normalizedBufferDurationSeconds(bufferDurationSeconds)
        if normalized != bufferDurationSeconds {
            bufferDurationSeconds = normalized
        }
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
