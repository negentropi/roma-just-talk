import SwiftUI

struct LiveTranscriptionSettingsControls: View {
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = false
    @AppStorage(LiveTranscriptionSettings.modeKey) private var liveTranscriptionModeRaw = LiveTranscriptionSettings.defaultMode.rawValue
    @AppStorage(LiveTranscriptionSettings.autoDisableCloudModelsKey) private var autoDisableCloudModels = LiveTranscriptionSettings.defaultAutoDisablesCloudModels
    @AppStorage(LiveTranscriptionSettings.autoDisableLowBatteryLocalModelsKey) private var autoDisableLowBatteryLocalModels = LiveTranscriptionSettings.defaultAutoDisablesLowBatteryLocalModels
    @AppStorage(LiveTranscriptionSettings.lowBatteryThresholdPercentKey) private var lowBatteryThresholdPercent = LiveTranscriptionSettings.defaultLowBatteryThresholdPercent

    private var liveTranscriptionMode: Binding<LiveTranscriptionMode> {
        Binding(
            get: {
                LiveTranscriptionMode(rawValue: liveTranscriptionModeRaw) ?? LiveTranscriptionSettings.defaultMode
            },
            set: { newMode in
                liveTranscriptionModeRaw = newMode.rawValue
            }
        )
    }

    var body: some View {
        Toggle(isOn: $isVADEnabled) {
            HStack(spacing: 4) {
                Text("Voice Activity Detection (VAD)")
                InfoTip("Detect speech segments and filter out silence before transcription work. Also gates real-time chunks with the local Silero model when available.")
            }
        }
        .toggleStyle(.switch)

        Picker(selection: liveTranscriptionMode) {
            ForEach(LiveTranscriptionMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Real-time Transcription")
                InfoTip("Start processing audio while recording. Per-model Real-time switches can still disable specific models.")
            }
        }
        .pickerStyle(.segmented)

        if liveTranscriptionMode.wrappedValue == .auto {
            Toggle(isOn: $autoDisableCloudModels) {
                HStack(spacing: 4) {
                    Text("Auto: Disable Cloud Models")
                    InfoTip("When enabled, Auto uses batch mode for cloud transcription models that have a batch endpoint.")
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $autoDisableLowBatteryLocalModels) {
                HStack(spacing: 4) {
                    Text("Auto: Disable Local Models on Low Battery")
                    InfoTip("When enabled, Auto uses batch mode for local models while running on battery below the cutoff.")
                }
            }
            .toggleStyle(.switch)

            if autoDisableLowBatteryLocalModels {
                Stepper(
                    "Battery cutoff: \(lowBatteryThresholdPercent)%",
                    value: $lowBatteryThresholdPercent,
                    in: 1...100,
                    step: 5
                )
            }
        }

        Toggle(isOn: $showLiveTextPreview) {
            HStack(spacing: 4) {
                Text("Show Live Text Preview")
                InfoTip("Displays the live transcript preview in the recorder while speaking. Only applies when real-time transcription is active.")
            }
        }
        .toggleStyle(.switch)
    }
}
