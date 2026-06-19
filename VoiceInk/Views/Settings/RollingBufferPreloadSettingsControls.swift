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

    private var mode: Binding<VoiceInkRollingBufferPreloadMode> {
        Binding(
            get: {
                VoiceInkRollingBufferPreloadMode(rawValue: modeRaw) ?? VoiceInkRollingBufferPreloadSettings.defaultMode
            },
            set: { newMode in
                modeRaw = newMode.rawValue
                notifySettingsChanged()
            }
        )
    }

    private var durationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0.25
        formatter.maximum = 30
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
                Text("Buffer Preload")
                InfoTip("Runs local VAD on the rolling buffer and pre-runs supported STT models before capture is finalized.")
            }
        }
        .pickerStyle(.segmented)

        LabeledContent("Rolling Duration") {
            HStack(spacing: 6) {
                TextField("", value: $bufferDurationSeconds, formatter: durationFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .onSubmit(normalizeDuration)
                    .onChange(of: bufferDurationSeconds) { _, _ in
                        normalizeDuration()
                    }
                Text("s")
                    .foregroundColor(.secondary)
            }
        }

        Toggle(isOn: $preRunFinalization) {
            HStack(spacing: 4) {
                Text("Pre-run Finalization")
                InfoTip("When available, use the already-running preload session to finalize text instead of starting transcription from the saved WAV.")
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
                Text("Buffer VAD Model")
                InfoTip("Silero runs locally on CPU and watches rolling-buffer audio for speech before STT preload starts.")
            }
        }
        .pickerStyle(.menu)
        .onChange(of: rollingBufferVADModel) { _, _ in notifySettingsChanged() }

        if mode.wrappedValue == .auto {
            Toggle(isOn: $autoDisableCloudModels) {
                HStack(spacing: 4) {
                    Text("Auto: Disable Cloud Models")
                    InfoTip("When enabled, Auto keeps rolling-buffer preload local and avoids cloud streaming before capture.")
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoDisableCloudModels) { _, _ in notifySettingsChanged() }

            Toggle(isOn: $autoDisableLowBatteryLocalModels) {
                HStack(spacing: 4) {
                    Text("Auto: Disable Local Models on Low Battery")
                    InfoTip("When enabled, Auto stops local pre-run STT while running on battery below the cutoff.")
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoDisableLowBatteryLocalModels) { _, _ in notifySettingsChanged() }

            if autoDisableLowBatteryLocalModels {
                Stepper(
                    "Battery cutoff: \(lowBatteryThresholdPercent)%",
                    value: $lowBatteryThresholdPercent,
                    in: 1...100,
                    step: 1
                )
                .onChange(of: lowBatteryThresholdPercent) { _, _ in notifySettingsChanged() }
            }
        }
    }

    private func normalizeDuration() {
        let normalized = min(max(bufferDurationSeconds, 0.25), 30.0)
        if normalized != bufferDurationSeconds {
            bufferDurationSeconds = normalized
        }
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
