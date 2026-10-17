import SwiftUI
import RomaCore

struct ModelSettingsView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(RomaUserDefaultsKey.selectedTranscriptionLanguage)
    private var preferredLanguage = RomaDefaultSettings.macOS.selectedTranscriptionLanguage
    @AppStorage(RomaVADPreference.userDefaultsKey)
    private var isVADEnabled = RomaVADPreference.defaultIsEnabled
    @AppStorage(RomaAppendTrailingSpacePreference.userDefaultsKey)
    private var appendTrailingSpace = RomaAppendTrailingSpacePreference.defaultIsEnabled
    @AppStorage(RomaModelRuntimePreference.userDefaultsKey)
    private var prewarmModelOnWake = RomaModelRuntimePreference.defaultShouldPrewarmModelOnWake
    @AppStorage(RomaRecorderPreviewPreference.userDefaultsKey)
    private var showLiveTextPreview = RomaRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled
    @State private var promptDraftState = RomaLocalWhisperPromptDraftState()
    @State private var cleanupSettingsRevision = 0
    private let advancedSettingsPresentation = RomaMacOSAdvancedTranscriptionSettingsPresentation.macOS
    private let appendTrailingSpacePresentation = RomaAppendTrailingSpacePreference.macOSSettingsPresentation
    private let cleanupPresentation = RomaTranscriptionCleanupPresentation.macOS
    private let localWhisperPromptPresentation = RomaLocalWhisperPromptCatalog.macOSSettingsPresentation

    private var selectedLanguage: String {
        transcriptionModelManager.currentTranscriptionModel?.transcriptionLanguageSelectionFacts
            .compatibleLanguage(preferredLanguage) ?? preferredLanguage
    }

    private func languagePrompt(for language: String) -> String {
        RomaLocalWhisperPromptCatalog.prompt(
            for: language,
            customPrompts: RomaLocalWhisperPromptCatalog.storedCustomPrompts()
        )
    }

    private func saveCustomPrompt(_ prompt: String, for language: String) {
        RomaTranscriptionPromptPreference.saveLocalWhisperCustomPrompt(prompt, for: language)
        UserDefaults.standard.synchronize()
    }

    private var currentCleanupSettings: RomaTranscriptionCleanupSettings {
        _ = cleanupSettingsRevision
        return RomaTranscriptionCleanupSettings.current()
    }

    private func cleanupBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<RomaTranscriptionCleanupSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentCleanupSettings[keyPath: keyPath] },
            set: { newValue in
                let previousSettings = RomaTranscriptionCleanupSettings.current()
                guard previousSettings[keyPath: keyPath] != newValue else { return }

                let updatedSettings = previousSettings.updating(keyPath, to: newValue)
                updatedSettings.saveChangedValues(from: previousSettings)
                cleanupSettingsRevision &+= 1
            }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if promptDraftState.isEditing {
                        TextEditor(text: $promptDraftState.text)
                            .font(.system(size: 12))
                            .frame(minHeight: 40, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)

                        Button(localWhisperPromptPresentation.saveButtonTitle) {
                            saveCustomPrompt(promptDraftState.text, for: selectedLanguage)
                            promptDraftState = promptDraftState.saved()
                        }
                    } else {
                        Text(languagePrompt(for: selectedLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(localWhisperPromptPresentation.editButtonTitle) {
                            promptDraftState = promptDraftState.editing(
                                prompt: languagePrompt(for: selectedLanguage)
                            )
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text(localWhisperPromptPresentation.sectionTitle)
                    InfoTip(
                        localWhisperPromptPresentation.helpText,
                        learnMoreURL: localWhisperPromptPresentation.learnMoreURLString
                    )
                }
            }

            Section {
                Toggle(isOn: cleanupBinding(\.isTextFormattingEnabled)) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.paragraphBreaksToggleTitle)
                        if let helpText = cleanupPresentation.paragraphBreaksHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                Picker(selection: cleanupBinding(\.punctuationMode)) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.punctuationPickerTitle)
                        if let helpText = cleanupPresentation.punctuationHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: cleanupBinding(\.lowercaseTranscription)) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.lowercaseToggleTitle)
                        if let helpText = cleanupPresentation.lowercaseHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                FillerWordsSettingsView(removeFillerWords: cleanupBinding(\.removeFillerWords))
            } header: {
                Text(cleanupPresentation.sectionTitle)
            }

            Section {
                Toggle(isOn: $appendTrailingSpace) {
                    HStack(spacing: 4) {
                        Text(appendTrailingSpacePresentation.toggleTitle)
                        InfoTip(appendTrailingSpacePresentation.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isVADEnabled) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.vad.title)
                        InfoTip(advancedSettingsPresentation.vad.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $prewarmModelOnWake) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.modelPrewarm.title)
                        InfoTip(advancedSettingsPresentation.modelPrewarm.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $showLiveTextPreview) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.liveTextPreview.title)
                        InfoTip(advancedSettingsPresentation.liveTextPreview.helpText)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text(advancedSettingsPresentation.sectionTitle)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedLanguage) { _, _ in
            promptDraftState = promptDraftState.refreshingForSelectedLanguage(
                prompt: languagePrompt(for: selectedLanguage)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            cleanupSettingsRevision &+= 1
        }
    }
}
