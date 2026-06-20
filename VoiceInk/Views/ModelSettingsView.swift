import SwiftUI
import VoiceInkCore

struct ModelSettingsView: View {
    @ObservedObject var whisperPrompt: WhisperPrompt
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var selectedLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    @AppStorage(VoiceInkUserDefaultsKey.isTextFormattingEnabled)
    private var isTextFormattingEnabled = VoiceInkPreferenceDefault.isTextFormattingEnabled
    @AppStorage(PunctuationCleanupMode.userDefaultsKey) private var punctuationCleanupModeRaw = PunctuationCleanupMode.current().rawValue
    @AppStorage(VoiceInkUserDefaultsKey.lowercaseTranscription) private var lowercaseTranscription = false
    @AppStorage(VoiceInkVADPreference.userDefaultsKey)
    private var isVADEnabled = VoiceInkVADPreference.defaultIsEnabled
    @AppStorage(VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
    private var appendTrailingSpace = VoiceInkAppendTrailingSpacePreference.defaultIsEnabled
    @AppStorage(VoiceInkModelRuntimePreference.userDefaultsKey)
    private var prewarmModelOnWake = VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake
    @AppStorage(VoiceInkRecorderPreviewPreference.userDefaultsKey)
    private var showLiveTextPreview = VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled
    @State private var customPrompt: String = ""
    @State private var isEditing: Bool = false
    private let advancedSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS
    private let appendTrailingSpacePresentation = VoiceInkAppendTrailingSpacePreference.macOSSettingsPresentation
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS
    private let localWhisperPromptPresentation = VoiceInkLocalWhisperPromptCatalog.macOSSettingsPresentation

    private var punctuationCleanupMode: Binding<PunctuationCleanupMode> {
        Binding(
            get: {
                PunctuationCleanupMode(rawValue: punctuationCleanupModeRaw) ?? PunctuationCleanupMode.current()
            },
            set: { newMode in
                punctuationCleanupModeRaw = newMode.rawValue
                PunctuationCleanupMode.setCurrent(newMode)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        TextEditor(text: $customPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 40, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)

                        Button(localWhisperPromptPresentation.saveButtonTitle) {
                            whisperPrompt.setCustomPrompt(customPrompt, for: selectedLanguage)
                            isEditing = false
                        }
                    } else {
                        Text(whisperPrompt.getLanguagePrompt(for: selectedLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(localWhisperPromptPresentation.editButtonTitle) {
                            customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
                            isEditing = true
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
                Toggle(isOn: $isTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.paragraphBreaksToggleTitle)
                        if let helpText = cleanupPresentation.paragraphBreaksHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                Picker(selection: punctuationCleanupMode) {
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

                Toggle(isOn: $lowercaseTranscription) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.lowercaseToggleTitle)
                        if let helpText = cleanupPresentation.lowercaseHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                FillerWordsSettingsView()
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
        .onChange(of: selectedLanguage) { oldValue, newValue in
            if isEditing {
                customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
            }
        }
    }
}
