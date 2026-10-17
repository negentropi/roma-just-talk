import SwiftUI
import UniformTypeIdentifiers
import RomaCore

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        Group {
            LabeledContent(RomaCustomSoundSettingsPresentation.label(for: .start)) {
                soundControls(for: .start)
            }

            LabeledContent(RomaCustomSoundSettingsPresentation.label(for: .stop)) {
                soundControls(for: .stop)
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button(RomaCustomSoundSettingsPresentation.alertDismissButtonTitle, role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func soundControls(for type: RomaCustomSoundType) -> some View {
        let isCustom = customSoundManager.isUsingCustomSound(for: type)
        let fileName = customSoundManager.getSoundDisplayName(for: type)

        HStack(spacing: 8) {
            Picker(RomaCustomSoundSettingsPresentation.pickerTitle, selection: soundSelectionBinding(for: type)) {
                ForEach(RomaBuiltInRecordingSound.allCases) { sound in
                    Text(sound.displayName).tag(RomaCustomSoundMenuSelection.builtIn(sound))
                }

                if isCustom || fileName != nil {
                    Text(RomaCustomSoundSettingsPresentation.customMenuTitle(filename: fileName))
                        .tag(RomaCustomSoundMenuSelection.custom)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116, alignment: .trailing)
            .fixedSize()
            .help(RomaCustomSoundSettingsPresentation.selectSoundHelpText)

            Button {
                SoundManager.shared.play(type.recordingSoundCue)
            } label: {
                Image(systemName: RomaCustomSoundSettingsPresentation.testButtonSystemImageName)
            }
            .buttonStyle(.borderless)
            .help(RomaCustomSoundSettingsPresentation.testButtonHelpText)

            Button {
                selectSound(for: type)
            } label: {
                Image(systemName: RomaCustomSoundSettingsPresentation.chooseButtonSystemImageName)
            }
            .buttonStyle(.borderless)
            .help(RomaCustomSoundSettingsPresentation.chooseButtonHelpText)

            if !customSoundManager.isDefaultSelection(for: type) {
                Button {
                    if isCustom {
                        customSoundManager.resetSoundToDefault(for: type)
                    } else {
                        customSoundManager.selectBuiltInSound(type.defaultBuiltInSound, for: type)
                    }
                } label: {
                    Image(systemName: RomaCustomSoundSettingsPresentation.resetButtonSystemImageName)
                }
                .buttonStyle(.borderless)
                .help(RomaCustomSoundSettingsPresentation.resetButtonHelpText)
            }
        }
    }

    private func soundSelectionBinding(for type: RomaCustomSoundType) -> Binding<RomaCustomSoundMenuSelection> {
        Binding(
            get: {
                customSoundManager.menuSelection(for: type)
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

    private func selectSound(for type: RomaCustomSoundType) {
        let panel = NSOpenPanel()
        panel.title = RomaCustomSoundSettingsPresentation.openPanelTitle(for: type)
        panel.message = RomaCustomSoundSettingsPresentation.openPanelMessage
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
                alertTitle = RomaCustomSoundSettingsPresentation.invalidAudioAlertTitle
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
