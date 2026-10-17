import SwiftUI
import RomaCore

struct IOSEnhancementBehaviorView: View {
    @AppStorage(RomaIOSKeyboardEnhancementContextPreference.userDefaultsKey)
    private var useKeyboardContext = RomaIOSKeyboardEnhancementContextPreference.defaultIsEnabled
    @AppStorage(RomaUserDefaultsKey.skipShortEnhancement)
    private var skipShortEnhancement = RomaPreferenceDefault.skipShortEnhancement
    @AppStorage(RomaUserDefaultsKey.shortEnhancementWordThreshold)
    private var shortEnhancementWordThreshold = RomaPreferenceDefault.shortEnhancementWordThreshold
    @AppStorage(RomaUserDefaultsKey.enhancementTimeoutSeconds)
    private var enhancementTimeoutSeconds = RomaPreferenceDefault.enhancementTimeoutSeconds
    @AppStorage(RomaUserDefaultsKey.enhancementRetryOnTimeout)
    private var retryOnTimeout = RomaPreferenceDefault.enhancementRetryOnTimeout

    private let presentation = RomaEnhancementSettingsPresentation.macOS

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
                Text("If enhancement still fails, Roma Just Talk keeps the original transcription.")
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
