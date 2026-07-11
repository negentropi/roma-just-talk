import SwiftUI
import SwiftData
import OSLog
import VoiceInkCore

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @AppStorage(VoiceInkVADPreference.userDefaultsKey)
    private var isVADEnabled = VoiceInkVADPreference.defaultIsEnabled
    @AppStorage(VoiceInkModelRuntimePreference.userDefaultsKey)
    private var shouldPrewarmModel = VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake
    @AppStorage(VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
    private var appendTrailingSpace = VoiceInkAppendTrailingSpacePreference.defaultIsEnabled
    @State private var promptDraftState = VoiceInkLocalWhisperPromptDraftState()
    @State private var fillerWordDraftState = VoiceInkFillerWordDraftState()
    @State private var customVocabularyDraftState = VoiceInkVocabularyDraftState()
    @State private var wordReplacementDraftState = VoiceInkWordReplacementDraftState()
    @State private var editingWordReplacement: IOSWordReplacementEditSelection?
    @State private var dictionaryAlert: VoiceInkDictionaryAlertPresentation?
    @State private var isResetConfirmationPresented = false
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.iOS
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.iOS
    private let wordReplacementListPresentation = VoiceInkWordReplacementListPresentation.iOS
    private let audioTimeoutPresentation = VoiceInkAudioSessionTimeoutPreference.settingsPresentation
    private let settingsPresentation = VoiceInkSettingsPresentation.iOS
    private let vadPresentation = VoiceInkVADPreference.settingsPresentation
    private let prewarmPresentation = VoiceInkModelRuntimePreference.settingsPresentation
    private let promptPresentation = VoiceInkLocalWhisperPromptCatalog.settingsPresentation
    private let trailingSpacePresentation = VoiceInkAppendTrailingSpacePreference.settingsPresentation
    
    var body: some View {
        let dictionarySnapshot = self.dictionarySnapshot
        let fillerWordEditorPresentation = VoiceInkFillerWords.editorPresentation(
            isEnabled: settings.transcriptionCleanupSettings.removeFillerWords,
            words: settings.fillerWords
        )

        List {
            Section {
                NavigationLink(destination: IOSMicrophonePermissionView()) {
                    Label(
                        VoiceInkIOSMicrophonePermissionPresentation.settingsRowTitle,
                        systemImage: VoiceInkIOSMicrophonePermissionPresentation.settingsRowSystemImageName
                    )
                }

                NavigationLink(destination: KeyboardSetupView()) {
                    Label(
                        VoiceInkIOSKeyboardSetupPresentation.settingsRowTitle,
                        systemImage: VoiceInkIOSKeyboardSetupPresentation.settingsRowSystemImageName
                    )
                }

                NavigationLink(destination: IOSHelpSupportView(
                    announcementsStore: .shared
                )) {
                    Label(
                        VoiceInkIOSHelpSupportPresentation.settingsRowTitle,
                        systemImage: VoiceInkIOSHelpSupportPresentation.settingsRowSystemImageName
                    )
                }
            }

            Section(header: Text(settingsPresentation.modesSectionTitle)) {
                ForEach(settings.modes) { mode in
                    NavigationLink(destination: ModeConfigurationView(
                        mode: mode,
                        settings: settings
                    ) { updatedMode in
                        settings.updateMode(updatedMode, replacing: mode.id)
                    }) {
                        ModeRowView(mode: mode)
                    }
                }
                .onDelete(perform: settings.removeModes)
                
                NavigationLink(destination: ModeConfigurationView(
                    settings: settings
                ) { newMode in
                    settings.addMode(newMode)
                }) {
                    HStack {
                        Image(systemName: settingsPresentation.addActionSystemImageName)
                            .foregroundStyle(.blue)
                        Text(settingsPresentation.addModeButtonTitle)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Section(header: Text(VoiceInkModelManagementFilter.local.settingsSectionTitle)) {
                NavigationLink(destination: LocalModelManagementView()) {
                    Text(VoiceInkModelManagementFilter.local.manageSettingsTitle)
                }

                Toggle(vadPresentation.title, isOn: $isVADEnabled)

                Text(vadPresentation.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(prewarmPresentation.title, isOn: $shouldPrewarmModel)

                Text(prewarmPresentation.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section(header: Text(VoiceInkModelManagementFilter.cloud.settingsSectionTitle)) {
                NavigationLink(destination: APIKeysView()) {
                    Text(VoiceInkModelManagementFilter.cloud.manageSettingsTitle)
                }

                NavigationLink(destination: IOSCustomCloudModelsView()) {
                    Text(VoiceInkModelManagementFilter.custom.manageSettingsTitle)
                }

                NavigationLink(destination: IOSOllamaSettingsView(settings: settings)) {
                    Text("Ollama")
                }
            }

            Section(header: Text(VoiceInkTranscriptionLanguagePresentation.sectionTitle)) {
                Picker(
                    VoiceInkTranscriptionLanguagePresentation.pickerTitle,
                    selection: Binding(
                        get: { settings.selectedTranscriptionLanguage },
                        set: { settings.setSelectedTranscriptionLanguage($0) }
                    )
                ) {
                    ForEach(VoiceInkLanguageCatalog.sortedOptions(settings.transcriptionLanguages)) { language in
                        Text(language.name).tag(language.code)
                    }
                }

                if selectedTranscriptionProvider == .nativeApple {
                    IOSNativeAppleLanguageAssetView(
                        localeIdentifier: settings.selectedTranscriptionLanguage
                    )
                }
            }

            Section(header: Text(promptPresentation.sectionTitle)) {
                if promptDraftState.isEditing {
                    TextEditor(text: $promptDraftState.text)
                        .frame(minHeight: 88)

                    Button {
                        saveLanguagePrompt()
                    } label: {
                        Label(promptPresentation.saveButtonTitle, systemImage: "checkmark")
                    }
                } else {
                    Text(languagePrompt)
                        .foregroundStyle(.secondary)

                    Button {
                        promptDraftState = promptDraftState.editing(prompt: languagePrompt)
                    } label: {
                        Label(promptPresentation.editButtonTitle, systemImage: "pencil")
                    }
                }

                Toggle(trailingSpacePresentation.toggleTitle, isOn: $appendTrailingSpace)

                Text(trailingSpacePresentation.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(cleanupPresentation.sectionTitle)) {
                Picker(cleanupPresentation.punctuationPickerTitle, selection: cleanupBinding(\.punctuationMode)) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle(cleanupPresentation.paragraphBreaksToggleTitle, isOn: cleanupBinding(\.isTextFormattingEnabled))

                Toggle(cleanupPresentation.lowercaseToggleTitle, isOn: cleanupBinding(\.lowercaseTranscription))

                Toggle(cleanupPresentation.removeFillerWordsToggleTitle, isOn: cleanupBinding(\.removeFillerWords))

                if fillerWordEditorPresentation.shouldShowEditor {
                    HStack {
                        TextField(cleanupPresentation.addFillerWordPlaceholder, text: $fillerWordDraftState.draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addFillerWord)

                        Button(action: addFillerWord) {
                            Image(systemName: settingsPresentation.addActionSystemImageName)
                        }
                        .disabled(!fillerWordDraftState.canSubmit)
                    }

                    if fillerWordEditorPresentation.shouldShowWordList {
                        ForEach(settings.fillerWords, id: \.self) { word in
                            Text(word)
                        }
                        .onDelete { offsets in
                            settings.fillerWords = dictionarySnapshot.removingFillerWords(at: offsets)
                        }
                    }
                }
            }

            Section(header: Text(dictionaryPresentation.sectionTitle)) {
                HStack {
                    TextField(dictionaryPresentation.vocabularyPlaceholder, text: $customVocabularyDraftState.draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addCustomVocabularyTerm)

                    Button(action: addCustomVocabularyTerm) {
                        Image(systemName: settingsPresentation.addActionSystemImageName)
                    }
                    .disabled(!customVocabularyDraftState.canSubmit)
                }

                ForEach(dictionarySnapshot.sortedCustomVocabularyTerms, id: \.self) { term in
                    Text(term)
                }
                .onDelete { offsets in
                    settings.customVocabularyTerms = dictionarySnapshot.removingCustomVocabularyTerms(
                        atSortedOffsets: offsets
                    )
                }

                TextField(dictionaryPresentation.originalTextPlaceholder, text: $wordReplacementDraftState.original)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(submitWordReplacement)

                TextField(dictionaryPresentation.replacementTextPlaceholder, text: $wordReplacementDraftState.replacement)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(submitWordReplacement)

                Button(action: submitWordReplacement) {
                    Label(
                        dictionaryPresentation.addReplacementButtonTitle,
                        systemImage: settingsPresentation.addActionSystemImageName
                    )
                }
                .disabled(!wordReplacementDraftState.canSubmit)

                ForEach(Array(dictionarySnapshot.sortedWordReplacements.enumerated()), id: \.offset) { _, rule in
                    Button {
                        editingWordReplacement = IOSWordReplacementEditSelection(rule: rule)
                    } label: {
                        HStack(spacing: 8) {
                            Text(rule.originalText)
                            Image(systemName: dictionaryPresentation.wordReplacementArrowSystemImageName)
                                .foregroundStyle(.secondary)
                            Text(rule.replacementText)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(wordReplacementListPresentation.editButtonHelp)
                }
                .onDelete { offsets in
                    settings.wordReplacements = dictionarySnapshot.removingWordReplacements(
                        atSortedOffsets: offsets
                    )
                }
            }
            
            Section(header: Text(audioTimeoutPresentation.sectionTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(audioTimeoutPresentation.timeoutTitle)
                        Spacer()
                        Text(VoiceInkAudioSessionTimeoutPreference.displayText(
                            for: settings.audioSessionTimeoutSeconds
                        ))
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.audioSessionTimeoutSeconds) },
                            set: { settings.audioSessionTimeoutSeconds = Int($0) }
                        ),
                        in: Double(VoiceInkAudioSessionTimeoutPreference.minimumSeconds)...Double(
                            VoiceInkAudioSessionTimeoutPreference.maximumSeconds
                        ),
                        step: Double(VoiceInkAudioSessionTimeoutPreference.stepSeconds)
                    )
                    
                    Text(audioTimeoutPresentation.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text(VoiceInkIOSAppDataResetPresentation.sectionTitle)) {
                Button(role: .destructive) {
                    isResetConfirmationPresented = true
                } label: {
                    Label(
                        VoiceInkIOSAppDataResetPresentation.buttonTitle,
                        systemImage: VoiceInkIOSAppDataResetPresentation.buttonSystemImageName
                    )
                }
            }
        }
        .navigationTitle(settingsPresentation.navigationTitle)
        .sheet(item: $editingWordReplacement) { selection in
            IOSWordReplacementEditView(
                selection: selection,
                snapshot: dictionarySnapshot,
                setRules: { settings.wordReplacements = $0 }
            )
        }
        .onAppear {
            settings.repairSelectedTranscriptionLanguage()
        }
        .onChange(of: settings.selectedTranscriptionLanguage) { _, _ in
            promptDraftState = promptDraftState.refreshingForSelectedLanguage(
                prompt: languagePrompt
            )
        }
        .alert(item: $dictionaryAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
        .confirmationDialog(
            VoiceInkIOSAppDataResetPresentation.confirmationTitle,
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(VoiceInkIOSAppDataResetPresentation.confirmButtonTitle, role: .destructive) {
                resetAppData()
            }
            Button(VoiceInkIOSAppDataResetPresentation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(VoiceInkIOSAppDataResetPresentation.confirmationMessage)
        }
    }

    private func cleanupBinding<Value>(
        _ keyPath: WritableKeyPath<VoiceInkTranscriptionCleanupSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings.transcriptionCleanupSettings[keyPath: keyPath] },
            set: { settings.transcriptionCleanupSettings[keyPath: keyPath] = $0 }
        )
    }

    private var dictionarySnapshot: VoiceInkDictionarySettingsSnapshot {
        VoiceInkDictionarySettingsSnapshot(
            fillerWords: settings.fillerWords,
            customVocabularyTerms: settings.customVocabularyTerms,
            wordReplacements: settings.wordReplacements
        )
    }

    private var selectedTranscriptionProvider: VoiceInkProviderKind? {
        settings.modes.activeMode(selectedModeId: settings.selectedModeId)?.transcriptionProvider
    }

    private var languagePrompt: String {
        VoiceInkLocalWhisperPromptCatalog.prompt(
            for: settings.selectedTranscriptionLanguage,
            customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts()
        )
    }

    private func saveLanguagePrompt() {
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(
            promptDraftState.text,
            for: settings.selectedTranscriptionLanguage
        )
        promptDraftState = promptDraftState.saved()
    }

    private func addFillerWord() {
        let snapshot = dictionarySnapshot
        snapshot
            .fillerWordSubmission(fillerWordDraftState)
            .applyRuntimeState(
                applyPlan: {
                    snapshot.applyFillerWordSubmission($0) { settings.fillerWords = $0 }
                },
                setDraftState: { fillerWordDraftState = $0 },
                setAlertPresentation: { dictionaryAlert = $0 }
            )
    }

    private func addCustomVocabularyTerm() {
        let snapshot = dictionarySnapshot
        snapshot
            .customVocabularySubmission(customVocabularyDraftState)
            .applyRuntimeState(
                applyPlan: {
                    snapshot.applyCustomVocabularySubmission($0) { settings.customVocabularyTerms = $0 }
                },
                setDraftState: { customVocabularyDraftState = $0 },
                setAlertPresentation: { dictionaryAlert = $0 }
            )
    }

    private func submitWordReplacement() {
        let snapshot = dictionarySnapshot
        snapshot
            .wordReplacementSubmission(wordReplacementDraftState)
            .applyRuntimeState(
                applyPlan: {
                    snapshot.applyWordReplacementSubmission($0) { settings.wordReplacements = $0 }
                },
                setDraftState: { wordReplacementDraftState = $0 },
                setAlertPresentation: { dictionaryAlert = $0 }
            )
    }

    private func resetAppData() {
        let resetPlan = VoiceInkAppDataResetPlan.iOS()

        resetPlan.applyRuntimeState(
            deleteTranscriptionRecords: deleteTranscriptionRecords,
            resetAppSettings: { settings.resetAll() }
        )
    }

    private func deleteTranscriptionRecords() {
        do {
            let descriptor = FetchDescriptor<Transcription>()
            let modelContainer = try ModelContainer(for: Transcription.self)
            let context = ModelContext(modelContainer)
            let notes = try context.fetch(descriptor)
            for note in notes {
                context.delete(note)
            }
            try? context.save()
        } catch {
            VoiceInkIOSLogger.settings.error("\(VoiceInkAppDataResetDiagnostics.swiftDataResetFailedMessage(errorDescription: String(describing: error)), privacy: .public)")
        }
    }
}



#Preview {
    NavigationStack { SettingsView() }
}

private struct ModeRowView: View {
    let mode: Mode

    var body: some View {
        let presentation = mode.summaryPresentation

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.transcriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let postProcessingText = presentation.postProcessingText {
                        Text(postProcessingText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
