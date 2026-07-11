import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct IOSRecordingFeedbackView: View {
    @AppStorage(VoiceInkIOSRecordingFeedbackPreference.hapticFeedbackEnabledKey)
    private var hapticFeedbackEnabled = VoiceInkIOSRecordingFeedbackPreference.defaultHapticFeedbackEnabled
    @AppStorage(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
    private var soundFeedbackEnabled = VoiceInkRecordingFeedbackPreference.defaultIsSoundFeedbackEnabled
    @State private var importingType: VoiceInkCustomSoundType?
    @State private var importError: VoiceInkCustomSoundError?
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

    private func soundSection(for type: VoiceInkCustomSoundType) -> some View {
        _ = refreshToken
        let state = VoiceInkCustomSoundPreference.selectionState(for: type)
        return Section("\(type.displayName) Sound") {
            Picker("Built-in Sound", selection: Binding(
                get: { state.selectedBuiltInSound },
                set: {
                    VoiceInkCustomSoundPreference.saveSelectedBuiltInSound($0, for: type)
                    VoiceInkCustomSoundPreference.saveIsUsingCustomSound(false, for: type)
                    refreshToken += 1
                }
            )) {
                ForEach(VoiceInkBuiltInRecordingSound.allCases) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }

            if let filename = state.customFilename {
                Toggle("Use Custom: \(filename)", isOn: Binding(
                    get: { state.isUsingCustomSound },
                    set: {
                        VoiceInkCustomSoundPreference.saveIsUsingCustomSound($0, for: type)
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
