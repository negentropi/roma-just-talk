import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        Group {
            LabeledContent(VoiceInkCustomSoundSettingsPresentation.label(for: .start)) {
                soundControls(for: .start)
            }

            LabeledContent(VoiceInkCustomSoundSettingsPresentation.label(for: .stop)) {
                soundControls(for: .stop)
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button(VoiceInkCustomSoundSettingsPresentation.alertDismissButtonTitle, role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func soundControls(for type: VoiceInkCustomSoundType) -> some View {
        let isCustom = type == .start ? customSoundManager.isUsingCustomStartSound : customSoundManager.isUsingCustomStopSound
        let fileName = customSoundManager.getSoundDisplayName(for: type)

        HStack(spacing: 8) {
            Picker(VoiceInkCustomSoundSettingsPresentation.pickerTitle, selection: soundSelectionBinding(for: type)) {
                ForEach(VoiceInkBuiltInRecordingSound.allCases) { sound in
                    Text(sound.displayName).tag(VoiceInkCustomSoundMenuSelection.builtIn(sound))
                }

                if isCustom || fileName != nil {
                    Text(VoiceInkCustomSoundSettingsPresentation.customMenuTitle(filename: fileName))
                        .tag(VoiceInkCustomSoundMenuSelection.custom)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116, alignment: .trailing)
            .fixedSize()
            .help(VoiceInkCustomSoundSettingsPresentation.selectSoundHelpText)

            Button {
                if type == .start {
                    SoundManager.shared.playStartSound()
                } else {
                    SoundManager.shared.playStopSound()
                }
            } label: {
                Image(systemName: VoiceInkCustomSoundSettingsPresentation.testButtonSystemImageName)
            }
            .buttonStyle(.borderless)
            .help(VoiceInkCustomSoundSettingsPresentation.testButtonHelpText)

            Button {
                selectSound(for: type)
            } label: {
                Image(systemName: VoiceInkCustomSoundSettingsPresentation.chooseButtonSystemImageName)
            }
            .buttonStyle(.borderless)
            .help(VoiceInkCustomSoundSettingsPresentation.chooseButtonHelpText)

            if !customSoundManager.isDefaultSelection(for: type) {
                Button {
                    if isCustom {
                        customSoundManager.resetSoundToDefault(for: type)
                    } else {
                        customSoundManager.selectBuiltInSound(type.defaultBuiltInSound, for: type)
                    }
                } label: {
                    Image(systemName: VoiceInkCustomSoundSettingsPresentation.resetButtonSystemImageName)
                }
                .buttonStyle(.borderless)
                .help(VoiceInkCustomSoundSettingsPresentation.resetButtonHelpText)
            }
        }
    }

    private func soundSelectionBinding(for type: VoiceInkCustomSoundType) -> Binding<VoiceInkCustomSoundMenuSelection> {
        Binding(
            get: {
                let isCustom = type == .start ? customSoundManager.isUsingCustomStartSound : customSoundManager.isUsingCustomStopSound
                if isCustom {
                    return .custom
                }

                return .builtIn(customSoundManager.selectedBuiltInSound(for: type))
            },
            set: { selection in
                switch selection {
                case .builtIn(let sound):
                    customSoundManager.selectBuiltInSound(sound, for: type)
                case .custom:
                    customSoundManager.useCustomSound(for: type)
                }
            }
        )
    }

    private func selectSound(for type: VoiceInkCustomSoundType) {
        let panel = NSOpenPanel()
        panel.title = VoiceInkCustomSoundSettingsPresentation.openPanelTitle(for: type)
        panel.message = VoiceInkCustomSoundSettingsPresentation.openPanelMessage
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let result = customSoundManager.setCustomSound(url: url, for: type)
            if case .failure(let error) = result {
                alertTitle = VoiceInkCustomSoundSettingsPresentation.invalidAudioAlertTitle
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

#Preview {
    CustomSoundSettingsView()
        .frame(width: 400)
        .padding()
}
