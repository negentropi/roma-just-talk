import SwiftUI
import SwiftData
import VoiceInkCore

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var newFillerWord = ""
    @State private var newCustomVocabularyTerm = ""
    @State private var newReplacementOriginal = ""
    @State private var newReplacementText = ""
    @State private var dictionaryAlert: VoiceInkDictionaryAlertPresentation?
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.iOS
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.iOS
    private let audioTimeoutPresentation = VoiceInkAudioSessionTimeoutPreference.settingsPresentation
    
    var body: some View {
        List {
            Section(header: Text("Modes")) {
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
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Add New Mode")
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
                        TextField(cleanupPresentation.addFillerWordPlaceholder, text: $newFillerWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addFillerWord)

                        Button(action: addFillerWord) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(!canAddFillerWord)
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
                        Image(systemName: "plus.circle.fill")
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
                    .onSubmit(addWordReplacement)

                TextField(dictionaryPresentation.replacementTextPlaceholder, text: $newReplacementText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addWordReplacement)

                Button(action: addWordReplacement) {
                    Label(dictionaryPresentation.addReplacementButtonTitle, systemImage: "plus.circle.fill")
                }
                .disabled(!canAddWordReplacement)

                ForEach(Array(settings.wordReplacements.enumerated()), id: \.offset) { _, rule in
                    HStack(spacing: 8) {
                        Text(rule.originalText)
                        Image(systemName: "arrow.right")
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
            Section(header: Text("Debug")) {
                Button(role: .destructive) {
                    resetAppData()
                } label: {
                    Label("Reset All App Data", systemImage: "trash")
                }
            }
            #endif
        }
        .navigationTitle("Settings")
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

    private var canAddFillerWord: Bool {
        VoiceInkFillerWords.hasDraft(newFillerWord)
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
        guard canAddFillerWord else { return }

        if let errorMessage = settings.addFillerWord(newFillerWord) {
            dictionaryAlert = .duplicateFillerWord(message: errorMessage)
            return
        }

        newFillerWord = ""
    }

    private func addCustomVocabularyTerm() {
        guard canAddCustomVocabularyTerm else { return }

        if let error = settings.addCustomVocabularyTerms(newCustomVocabularyTerm) {
            dictionaryAlert = .vocabulary(message: error)
            return
        }

        newCustomVocabularyTerm = ""
    }

    private func addWordReplacement() {
        guard canAddWordReplacement else { return }

        if let error = settings.addWordReplacement(
            original: newReplacementOriginal,
            replacement: newReplacementText
        ) {
            dictionaryAlert = .wordReplacement(message: error)
            return
        }

        newReplacementOriginal = ""
        newReplacementText = ""
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

        // 2) Delete audio files directory
        let recordingsDir = VoiceInkIOSStorageDirectories.recordingsDirectory
        if FileManager.default.fileExists(atPath: recordingsDir.path) {
            try? FileManager.default.removeItem(at: recordingsDir)
        }

        // 3) Delete local model directory
        let modelsDir = VoiceInkIOSStorageDirectories.modelsDirectory
        if FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.removeItem(at: modelsDir)
        }

        // 4) Clear caches and tmp contents (best-effort)
        let cachesURL = VoiceInkIOSStorageDirectories.cachesDirectory
        if let cacheItems = try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for url in cacheItems { try? FileManager.default.removeItem(at: url) }
        }
        let tmpPath = NSTemporaryDirectory()
        if let tmpItems = try? FileManager.default.contentsOfDirectory(atPath: tmpPath) {
            for item in tmpItems { try? FileManager.default.removeItem(atPath: (tmpPath as NSString).appendingPathComponent(item)) }
        }

        // 5) Reset settings, modes, and keys
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
