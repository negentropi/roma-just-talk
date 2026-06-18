import SwiftUI
import SwiftData
import VoiceInkCore

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var newFillerWord = ""
    @State private var fillerWordAlertMessage = ""
    @State private var showFillerWordAlert = false
    @State private var newCustomVocabularyTerm = ""
    @State private var customVocabularyAlertMessage = ""
    @State private var showCustomVocabularyAlert = false
    @State private var newReplacementOriginal = ""
    @State private var newReplacementText = ""
    @State private var wordReplacementAlertMessage = ""
    @State private var showWordReplacementAlert = false
    
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
            
            Section(header: Text("Local Models")) {
                NavigationLink(destination: LocalModelManagementView()) {
                    Text("Manage Local Models")
                }
            }
            
            Section(header: Text("Cloud Models")) {
                NavigationLink(destination: APIKeysView()) {
                    Text("Manage Cloud Models")
                }
            }

            Section(header: Text("Transcription Language")) {
                Picker("Language", selection: selectedLanguageBinding) {
                    ForEach(sortedTranscriptionLanguages) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }

            Section(header: Text("Transcription Cleanup")) {
                Picker("Punctuation", selection: $settings.punctuationCleanupMode) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Paragraph Breaks", isOn: $settings.isTextFormattingEnabled)

                Toggle("Lowercase Transcription", isOn: $settings.lowercaseTranscription)

                Toggle("Remove Filler Words", isOn: $settings.removeFillerWords)

                if settings.removeFillerWords {
                    HStack {
                        TextField("Add filler word", text: $newFillerWord)
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

            Section(header: Text("Dictionary")) {
                HStack {
                    TextField("Vocabulary term", text: $newCustomVocabularyTerm)
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

                TextField("Original text", text: $newReplacementOriginal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addWordReplacement)

                TextField("Replacement text", text: $newReplacementText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addWordReplacement)

                Button(action: addWordReplacement) {
                    Label("Add Replacement", systemImage: "plus.circle.fill")
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
            
            Section(header: Text("Audio Settings")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Session Timeout")
                        Spacer()
                        Text("\(settings.audioSessionTimeoutSeconds)s")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.audioSessionTimeoutSeconds) },
                            set: { settings.audioSessionTimeoutSeconds = Int($0) }
                        ),
                        in: 0...300,
                        step: 15
                    )
                    
                    Text("How long to keep the microphone session active after recording stops. Longer timeouts prevent 'session activation failed' errors when recording frequently, but may use more battery.")
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
        .alert("Duplicate Word", isPresented: $showFillerWordAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fillerWordAlertMessage)
        }
        .alert("Vocabulary", isPresented: $showCustomVocabularyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(customVocabularyAlertMessage)
        }
        .alert("Word Replacement", isPresented: $showWordReplacementAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wordReplacementAlertMessage)
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
            fillerWordAlertMessage = errorMessage
            showFillerWordAlert = true
            return
        }

        newFillerWord = ""
    }

    private func addCustomVocabularyTerm() {
        guard canAddCustomVocabularyTerm else { return }

        if let error = settings.addCustomVocabularyTerms(newCustomVocabularyTerm) {
            customVocabularyAlertMessage = error
            showCustomVocabularyAlert = true
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
            wordReplacementAlertMessage = error
            showWordReplacementAlert = true
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription: \(mode.effectiveTranscriptionModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if mode.isPostProcessingEnabled {
                        Text("Post-processing: \(mode.effectivePostProcessingModel)")
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
