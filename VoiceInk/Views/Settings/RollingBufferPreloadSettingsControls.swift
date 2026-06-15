import SwiftUI

struct RollingBufferPreloadSettingsControls: View {
    @AppStorage(RollingBufferPreloadSettings.modeKey) private var modeRaw = RollingBufferPreloadSettings.defaultMode.rawValue
    @AppStorage(RollingBufferPreloadSettings.autoDisableCloudModelsKey) private var autoDisableCloudModels = RollingBufferPreloadSettings.defaultAutoDisablesCloudModels
    @AppStorage(RollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey) private var autoDisableLowBatteryLocalModels = RollingBufferPreloadSettings.defaultAutoDisablesLowBatteryLocalModels
    @AppStorage(RollingBufferPreloadSettings.lowBatteryThresholdPercentKey) private var lowBatteryThresholdPercent = RollingBufferPreloadSettings.defaultLowBatteryThresholdPercent
    @AppStorage(RollingBufferPreloadSettings.bufferDurationSecondsKey) private var bufferDurationSeconds = RollingBufferPreloadSettings.defaultBufferDurationSeconds
    @AppStorage(RollingBufferPreloadSettings.preRunFinalizationKey) private var preRunFinalization = RollingBufferPreloadSettings.defaultPreRunFinalization

    private var mode: Binding<RollingBufferPreloadMode> {
        Binding(
            get: {
                RollingBufferPreloadMode(rawValue: modeRaw) ?? RollingBufferPreloadSettings.defaultMode
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
            ForEach(RollingBufferPreloadMode.allCases) { mode in
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
