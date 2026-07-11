import SwiftUI
import VoiceInkCore

struct IOSEnhancementBehaviorView: View {
    @AppStorage(VoiceInkIOSKeyboardEnhancementContextPreference.userDefaultsKey)
    private var useKeyboardContext = VoiceInkIOSKeyboardEnhancementContextPreference.defaultIsEnabled
    @AppStorage(VoiceInkUserDefaultsKey.skipShortEnhancement)
    private var skipShortEnhancement = VoiceInkPreferenceDefault.skipShortEnhancement
    @AppStorage(VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)
    private var shortEnhancementWordThreshold = VoiceInkPreferenceDefault.shortEnhancementWordThreshold
    @AppStorage(VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
    private var enhancementTimeoutSeconds = VoiceInkPreferenceDefault.enhancementTimeoutSeconds
    @AppStorage(VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    private var retryOnTimeout = VoiceInkPreferenceDefault.enhancementRetryOnTimeout

    private let presentation = VoiceInkEnhancementSettingsPresentation.macOS

    var body: some View {
        Form {
            Section("Context") {
                Toggle("Use keyboard text context", isOn: $useKeyboardContext)

                Text("Include text before the cursor when enhancing keyboard dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(presentation.skipShortEnhancementTitle, isOn: $skipShortEnhancement)

                if skipShortEnhancement {
                    Picker(presentation.minimumWordsPickerTitle, selection: $shortEnhancementWordThreshold) {
                        ForEach(presentation.shortEnhancementWordOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }
            } footer: {
                Text(presentation.skipShortEnhancementHelp)
            }

            Section {
                Picker(presentation.timeoutPickerTitle, selection: $enhancementTimeoutSeconds) {
                    ForEach(presentation.timeoutOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }

                Picker(presentation.timeoutRetryPickerTitle, selection: $retryOnTimeout) {
                    ForEach(presentation.timeoutRetryOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
            } header: {
                Text(presentation.requestTimeoutSectionTitle)
            } footer: {
                Text("If enhancement still fails, VoiceInk keeps the original transcription.")
            }
        }
        .navigationTitle("AI Enhancement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        IOSEnhancementBehaviorView()
    }
}
