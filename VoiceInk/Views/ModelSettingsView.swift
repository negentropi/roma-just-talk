import SwiftUI
import VoiceInkCore

struct ModelSettingsView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var preferredLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    @AppStorage(VoiceInkVADPreference.userDefaultsKey)
    private var isVADEnabled = VoiceInkVADPreference.defaultIsEnabled
    @AppStorage(VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
    private var appendTrailingSpace = VoiceInkAppendTrailingSpacePreference.defaultIsEnabled
    @AppStorage(VoiceInkModelRuntimePreference.userDefaultsKey)
    private var prewarmModelOnWake = VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake
    @AppStorage(VoiceInkRecorderPreviewPreference.userDefaultsKey)
    private var showLiveTextPreview = VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled
    @State private var promptDraftState = VoiceInkLocalWhisperPromptDraftState()
    @State private var cleanupSettingsRevision = 0
    private let advancedSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS
    private let appendTrailingSpacePresentation = VoiceInkAppendTrailingSpacePreference.macOSSettingsPresentation
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS
    private let localWhisperPromptPresentation = VoiceInkLocalWhisperPromptCatalog.macOSSettingsPresentation

    private var selectedLanguage: String {
        transcriptionModelManager.currentTranscriptionModel?.transcriptionLanguageSelectionFacts
            .compatibleLanguage(preferredLanguage) ?? preferredLanguage
    }

    private func languagePrompt(for language: String) -> String {
        VoiceInkLocalWhisperPromptCatalog.prompt(
            for: language,
            customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts()
        )
    }

    private func saveCustomPrompt(_ prompt: String, for language: String) {
        VoiceInkTranscriptionPromptPreference.saveLocalWhisperCustomPrompt(prompt, for: language)
        UserDefaults.standard.synchronize()
    }

    private var currentCleanupSettings: VoiceInkTranscriptionCleanupSettings {
        _ = cleanupSettingsRevision
        return VoiceInkTranscriptionCleanupSettings.current()
    }

    private var dictationProfile: VoiceInkDictationProfile {
        _ = cleanupSettingsRevision
        return VoiceInkDictationProfile.current()
    }

    private var dictationProfileBinding: Binding<VoiceInkDictationProfile> {
        Binding(
            get: { dictationProfile },
            set: { newValue in
                guard VoiceInkDictationProfile.current() != newValue else { return }
                newValue.save()
                cleanupSettingsRevision &+= 1
            }
        )
    }

    private var clarityStyle: VoiceInkClarityStyle {
        _ = cleanupSettingsRevision
        return VoiceInkClarityStyle.current()
    }

    // Global preference only: no AppSettingsDidChange post, so Power Mode state is untouched.
    private var clarityStyleBinding: Binding<VoiceInkClarityStyle> {
        Binding(
            get: { clarityStyle },
            set: { newValue in
                guard VoiceInkClarityStyle.current() != newValue else { return }
                newValue.save()
                cleanupSettingsRevision &+= 1
            }
        )
    }

    private func cleanupBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<VoiceInkTranscriptionCleanupSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentCleanupSettings[keyPath: keyPath] },
            set: { newValue in
                let previousSettings = VoiceInkTranscriptionCleanupSettings.current()
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
                Picker("Dictation Cleanup", selection: dictationProfileBinding) {
                    ForEach(VoiceInkDictationProfile.displayOrder, id: \.self) { profile in
                        Text(profile.title)
                            .accessibilityIdentifier(profile.accessibilityIdentifier)
                            .tag(profile)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
                .accessibilityIdentifier("dictationProfile.picker")

                VStack(alignment: .leading, spacing: 6) {
                    Text(dictationProfile.summary)
                        .accessibilityIdentifier("dictationProfile.summary")
                    Text("Applies to all apps and Power Modes, imported audio and retranscription. Changes take effect from the next transcription. Translate, Edit and Draft Writing Actions still use AI. Your formatting, dictionary and snippets stay saved.")
                        .accessibilityIdentifier("dictationProfile.scope")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Dictation Cleanup")
            }

            claritySection

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
                .accessibilityIdentifier("transcriptionSettings.paragraphBreaks")

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
                .accessibilityIdentifier("transcriptionSettings.punctuation")

                Toggle(isOn: cleanupBinding(\.lowercaseTranscription)) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.lowercaseToggleTitle)
                        if let helpText = cleanupPresentation.lowercaseHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("transcriptionSettings.lowercase")

                FillerWordsSettingsView(removeFillerWords: cleanupBinding(\.removeFillerWords))
            } header: {
                Text(cleanupPresentation.sectionTitle)
            } footer: {
                if !dictationProfile.usesCustomSettings {
                    Text("Saved for Custom. Not applied while Dictation Cleanup is \(dictationProfile.title).")
                        .accessibilityIdentifier("dictationProfile.formattingBypassedNote")
                }
            }
            .disabled(!dictationProfile.usesCustomSettings)

            Section {
                Toggle(isOn: $appendTrailingSpace) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(appendTrailingSpacePresentation.toggleTitle)
                            InfoTip(appendTrailingSpacePresentation.helpText)
                        }
                        if !dictationProfile.usesCustomSettings {
                            Text("Not added while Dictation Cleanup is \(dictationProfile.title).")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .accessibilityIdentifier("dictationProfile.trailingSpaceBypassedNote")
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(!dictationProfile.usesCustomSettings)
                .accessibilityIdentifier("transcriptionSettings.appendTrailingSpace")

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

    // Always present so the sheet layout stays stable; enabled only while Clarity is selected.
    private var claritySection: some View {
        let isClarity = dictationProfile == .clarity

        return Section {
            Picker("Style", selection: clarityStyleBinding) {
                ForEach(VoiceInkClarityStyle.allCases, id: \.self) { style in
                    Text(style.title)
                        .accessibilityIdentifier(style.accessibilityIdentifier)
                        .tag(style)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .accessibilityIdentifier("dictationProfile.clarityStyle.picker")

            VStack(alignment: .leading, spacing: 6) {
                Text(clarityStyle.summary)
                    .accessibilityIdentifier("dictationProfile.clarityStyle.summary")
                Text("Uses the AI provider and model you chose for AI Enhancement, as they are when each dictation starts. Power Mode AI settings apply only to Custom. If AI isn’t set up or doesn’t reply properly, your recognized text is used unchanged and you’ll see a warning.")
                    .accessibilityIdentifier("dictationProfile.clarityProvider")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Clarity")
        } footer: {
            if !isClarity {
                Text("Used only when Dictation Cleanup is Clarity. Your style choice stays saved.")
                    .accessibilityIdentifier("dictationProfile.clarityBypassedNote")
            }
        }
        .disabled(!isClarity)
    }
}

private extension VoiceInkDictationProfile {
    /// Custom and None keep their original positions; the new profiles follow.
    static let displayOrder: [Self] = [.custom, .none, .light, .clarity]

    var title: String {
        switch self {
        case .custom: return "Custom"
        case .none: return "None"
        case .light: return "Light"
        case .clarity: return "Clarity"
        }
    }

    var summary: String {
        switch self {
        case .custom:
            return "Uses your formatting, filler words, dictionary replacements, snippets and AI enhancement settings."
        case .none:
            return "Inserts exactly the text the transcription model returns. Formatting, filler-word removal, dictionary replacements, snippets, AI enhancement, cursor-based capitalization and the added trailing space are skipped."
        case .light:
            return "Quick cleanup without AI. Removes one leading “um,” or “uh,” when the transcription language is set to English, then applies your dictionary replacements. A snippet matching the whole dictation is inserted as written."
        case .clarity:
            return "One AI pass tidies punctuation, filler words and small grammar slips. It’s designed to keep your language, meaning, names and numbers, rather than translate, summarize or add new content. Dictionary replacements apply first; a snippet matching the whole dictation is inserted as written."
        }
    }

    var usesCustomSettings: Bool {
        self == .custom
    }

    var accessibilityIdentifier: String {
        "dictationProfile.\(rawValue)"
    }
}

private extension VoiceInkClarityStyle {
    var title: String {
        switch self {
        case .natural: return "Natural"
        case .casual: return "Casual"
        case .formal: return "Formal"
        }
    }

    var summary: String {
        switch self {
        case .natural: return "Natural keeps your own wording."
        case .casual: return "Casual allows small, conversational phrasing changes."
        case .formal: return "Formal allows small grammar and tone changes for a more polished register."
        }
    }

    var accessibilityIdentifier: String {
        "dictationProfile.clarityStyle.\(rawValue)"
    }
}
