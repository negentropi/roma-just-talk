import SwiftUI
import UniformTypeIdentifiers
import RomaCore

struct IOSRecordingFeedbackView: View {
    @AppStorage(RomaIOSRecordingFeedbackPreference.hapticFeedbackEnabledKey)
    private var hapticFeedbackEnabled = RomaIOSRecordingFeedbackPreference.defaultHapticFeedbackEnabled
    @AppStorage(RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
    private var soundFeedbackEnabled = RomaRecordingFeedbackPreference.defaultIsSoundFeedbackEnabled
    @State private var importingType: RomaCustomSoundType?
    @State private var importError: RomaCustomSoundError?
    @State private var refreshToken = 0

    var body: some View {
        Form {
            Section {
                Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                Toggle("Sound Feedback", isOn: $soundFeedbackEnabled)
            } footer: {
                Text("Turn both off for silent recording feedback.")
            }

            if soundFeedbackEnabled {
                soundSection(for: .start)
                soundSection(for: .stop)
            }
        }
        .navigationTitle("Recording Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: Binding(
                get: { importingType != nil },
                set: { if !$0 { importingType = nil } }
            ),
            allowedContentTypes: [.audio]
        ) { result in
            guard let type = importingType else { return }
            importingType = nil
            guard case .success(let url) = result else { return }
            if case .failure(let error) = IOSRecordingFeedbackManager.shared.importCustomSound(
                from: url,
                for: type
            ) {
                importError = error
            } else {
                refreshToken += 1
            }
        }
        .alert("Invalid Audio File", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError?.localizedDescription ?? "Unable to import this sound.")
        }
    }

    private func soundSection(for type: RomaCustomSoundType) -> some View {
        _ = refreshToken
        let state = RomaCustomSoundPreference.selectionState(for: type)
        return Section("\(type.displayName) Sound") {
            Picker("Built-in Sound", selection: Binding(
                get: { state.selectedBuiltInSound },
                set: {
                    RomaCustomSoundPreference.saveSelectedBuiltInSound($0, for: type)
                    RomaCustomSoundPreference.saveIsUsingCustomSound(false, for: type)
                    refreshToken += 1
                }
            )) {
                ForEach(RomaBuiltInRecordingSound.allCases) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }

            if let filename = state.customFilename {
                Toggle("Use Custom: \(filename)", isOn: Binding(
                    get: { state.isUsingCustomSound },
                    set: {
                        RomaCustomSoundPreference.saveIsUsingCustomSound($0, for: type)
                        refreshToken += 1
                    }
                ))
            }

            Button("Import Custom Sound") {
                importingType = type
            }

            Button("Preview") {
                IOSRecordingFeedbackManager.shared.preview(type)
            }
        }
    }
}

#Preview {
    NavigationStack {
        IOSRecordingFeedbackView()
    }
}
