import SwiftUI
import SwiftData
import VoiceInkCore

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var fillerWordDraftState = VoiceInkFillerWordDraftState()
    @State private var newCustomVocabularyTerm = ""
    @State private var newReplacementOriginal = ""
    @State private var newReplacementText = ""
    @State private var dictionaryAlert: VoiceInkDictionaryAlertPresentation?
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.iOS
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.iOS
    private let audioTimeoutPresentation = VoiceInkAudioSessionTimeoutPreference.settingsPresentation
    private let settingsPresentation = VoiceInkSettingsPresentation.iOS
    
    var body: some View {
        List {
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
                .onDelete(perform: deleteMode)
                
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
            }
            
            Section(header: Text(VoiceInkModelManagementFilter.cloud.settingsSectionTitle)) {
                NavigationLink(destination: APIKeysView()) {
                    Text(VoiceInkModelManagementFilter.cloud.manageSettingsTitle)
                }
            }

            Section(header: Text(VoiceInkTranscriptionLanguagePresentation.sectionTitle)) {
                Picker(VoiceInkTranscriptionLanguagePresentation.pickerTitle, selection: selectedLanguageBinding) {
                    ForEach(sortedTranscriptionLanguages) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }

            Section(header: Text(cleanupPresentation.sectionTitle)) {
                Picker(cleanupPresentation.punctuationPickerTitle, selection: $settings.punctuationCleanupMode) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle(cleanupPresentation.paragraphBreaksToggleTitle, isOn: $settings.isTextFormattingEnabled)

                Toggle(cleanupPresentation.lowercaseToggleTitle, isOn: $settings.lowercaseTranscription)

                Toggle(cleanupPresentation.removeFillerWordsToggleTitle, isOn: $settings.removeFillerWords)

                if settings.removeFillerWords {
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

                    ForEach(settings.fillerWords, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: settings.removeFillerWords)
                }
            }

            Section(header: Text(dictionaryPresentation.sectionTitle)) {
                HStack {
                    TextField(dictionaryPresentation.vocabularyPlaceholder, text: $newCustomVocabularyTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addCustomVocabularyTerm)

                    Button(action: addCustomVocabularyTerm) {
                        Image(systemName: settingsPresentation.addActionSystemImageName)
                    }
                    .disabled(!canAddCustomVocabularyTerm)
                }

                ForEach(settings.customVocabularyTerms, id: \.self) { term in
                    Text(term)
                }
                .onDelete(perform: settings.removeCustomVocabularyTerms)

                TextField(dictionaryPresentation.originalTextPlaceholder, text: $newReplacementOriginal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(submitWordReplacement)

                TextField(dictionaryPresentation.replacementTextPlaceholder, text: $newReplacementText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(submitWordReplacement)

                Button(action: submitWordReplacement) {
                    Label(
                        dictionaryPresentation.addReplacementButtonTitle,
                        systemImage: settingsPresentation.addActionSystemImageName
                    )
                }
                .disabled(!canAddWordReplacement)

                ForEach(Array(settings.wordReplacements.enumerated()), id: \.offset) { _, rule in
                    HStack(spacing: 8) {
                        Text(rule.originalText)
                        Image(systemName: dictionaryPresentation.wordReplacementArrowSystemImageName)
                            .foregroundStyle(.secondary)
                        Text(rule.replacementText)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: settings.removeWordReplacements)
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

            #if DEBUG
            Section(header: Text(settingsPresentation.debugSectionTitle)) {
                Button(role: .destructive) {
                    resetAppData()
                } label: {
                    Label(
                        settingsPresentation.resetAllAppDataButtonTitle,
                        systemImage: settingsPresentation.resetAllAppDataSystemImageName
                    )
                }
            }
            #endif
        }
        .navigationTitle(settingsPresentation.navigationTitle)
        .onAppear {
            settings.repairSelectedTranscriptionLanguage()
        }
        .alert(item: $dictionaryAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }

    private var sortedTranscriptionLanguages: [VoiceInkLanguageOption] {
        VoiceInkLanguageCatalog.sortedOptions(settings.availableTranscriptionLanguages)
    }

    private var selectedLanguageBinding: Binding<String> {
        Binding(
            get: { settings.selectedTranscriptionLanguage },
            set: { settings.setSelectedTranscriptionLanguage($0) }
        )
    }

    private var canAddCustomVocabularyTerm: Bool {
        VoiceInkDictionaryPolicy.hasVocabularyDraft(newCustomVocabularyTerm)
    }

    private var canAddWordReplacement: Bool {
        VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
            original: newReplacementOriginal,
            replacement: newReplacementText
        )
    }

    private func addFillerWord() {
        let submission = fillerWordDraftState.submitting(existingWords: settings.fillerWords)
        settings.applyFillerWordSubmissionPlan(submission.plan)
        fillerWordDraftState = submission.draftStateAfterSubmit
        dictionaryAlert = submission.alertPresentation
    }

    private func addCustomVocabularyTerm() {
        let plan = settings.submitCustomVocabularyDraft(newCustomVocabularyTerm)
        newCustomVocabularyTerm = plan.draftAfterSubmit
        dictionaryAlert = plan.alertPresentation
    }

    private func submitWordReplacement() {
        guard canAddWordReplacement else { return }

        let plan = settings.submitWordReplacementDraft(
            original: newReplacementOriginal,
            replacement: newReplacementText
        )
        newReplacementOriginal = plan.originalDraftAfterSubmit
        newReplacementText = plan.replacementDraftAfterSubmit
        dictionaryAlert = plan.alertPresentation
    }
    
    private func deleteMode(at offsets: IndexSet) {
        settings.removeModes(at: offsets)
    }

    #if DEBUG
    private func resetAppData() {
        // 1) Delete all SwiftData Transcription records
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
            print("Failed to reset SwiftData: \(error)")
        }

        VoiceInkAppDataResetFilePlan.iOS(
            recordingsDirectory: VoiceInkIOSStorageDirectories.recordingsDirectory,
            modelsDirectory: VoiceInkIOSStorageDirectories.modelsDirectory,
            cachesDirectory: VoiceInkIOSStorageDirectories.cachesDirectory,
            temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
        .performBestEffort()

        settings.resetAll()
    }
    #endif
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
