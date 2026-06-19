import SwiftUI
import VoiceInkCore

struct ConfigurationView: View {
    let mode: VoiceInkPowerModeConfigurationMode
    let powerModeManager: PowerModeManager
    var onDismiss: () -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @FocusState private var isNameFieldFocused: Bool

    @State private var configName: String = "New Power Mode"
    @State private var selectedEmoji: String = "💼"
    @State private var isShowingEmojiPicker = false
    @State private var isShowingAppPicker = false
    @State private var isAIEnhancementEnabled: Bool
    @State private var selectedPromptId: UUID?
    @State private var selectedTranscriptionModelName: String?
    @State private var selectedLanguage: String?
    @State private var isTextFormattingEnabled = false
    @State private var punctuationCleanupMode: PunctuationCleanupMode = .keep
    @State private var lowercaseTranscription = false
    @State private var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State private var searchText = ""
    @State private var validationErrors: [VoiceInkPowerModeValidationError] = []
    @State private var showValidationAlert = false
    @State private var selectedAIProvider: String?
    @State private var selectedAIModel: String?
    @State private var selectedAppConfigs: [VoiceInkPowerModeAppConfig] = []
    @State private var websiteConfigs: [VoiceInkPowerModeURLConfig] = []
    @State private var newWebsiteURL: String = ""
    @State private var useScreenCapture = false
    @State private var autoSendKey: VoiceInkAutoSendKey = .none
    @State private var isDefault = false
    @State private var isShowingDeleteConfirmation = false
    @State private var powerModeConfigId: UUID = UUID()
    @State private var isTranscriptFormattingExpanded = false
    @State private var didSaveConfiguration = false
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS

    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var canSave: Bool {
        VoiceInkPowerModePolicy.canSaveConfigurationName(configName)
    }

    private var transcriptionSelection: VoiceInkPowerModeTranscriptionSelection {
        VoiceInkPowerModeTranscriptionSelection(
            selectedModelName: selectedTranscriptionModelName,
            selectedLanguage: selectedLanguage
        )
    }

    private var selectedTranscriptionModel: (any TranscriptionModel)? {
        guard let modelName = transcriptionSelection.selectedModelNameForPicker(
            currentModelName: transcriptionModelManager.currentTranscriptionModel?.name
        ) else {
            return nil
        }

        return transcriptionModelManager.allAvailableModels.first { $0.name == modelName }
    }

    private func applyTranscriptionSelection(_ selection: VoiceInkPowerModeTranscriptionSelection) {
        selectedTranscriptionModelName = selection.selectedModelName
        selectedLanguage = selection.selectedLanguage
    }

    private func modelFacts(for model: any TranscriptionModel) -> VoiceInkPowerModeTranscriptionModelFacts {
        VoiceInkPowerModeTranscriptionModelFacts(
            name: model.name,
            disablesLanguageSelection: model.provider == .gemini,
            isMultilingual: model.isMultilingualModel,
            languageOptions: model.transcriptionLanguageOptions,
            prefersNativeAppleEnglish: model.provider == .nativeApple
        )
    }

    private var enhancementSelection: VoiceInkPowerModeEnhancementSelection {
        VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel
        )
    }

    private func applyEnhancementSelection(_ selection: VoiceInkPowerModeEnhancementSelection) {
        selectedPromptId = selection.selectedPromptId
        selectedAIProvider = selection.selectedAIProvider
        selectedAIModel = selection.selectedAIModel
    }

    init(
        mode: VoiceInkPowerModeConfigurationMode,
        powerModeManager: PowerModeManager,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        self.onDismiss = onDismiss

        let formState = mode.formState(existingConfigurations: powerModeManager.configurations)
        _powerModeConfigId = State(initialValue: formState.id)
        _isAIEnhancementEnabled = State(initialValue: formState.isAIEnhancementEnabled)
        _selectedPromptId = State(initialValue: formState.selectedPromptId)
        _selectedTranscriptionModelName = State(initialValue: formState.selectedTranscriptionModelName)
        _selectedLanguage = State(initialValue: formState.selectedLanguage)
        _isTextFormattingEnabled = State(initialValue: formState.isTextFormattingEnabled)
        _punctuationCleanupMode = State(initialValue: formState.punctuationCleanupMode)
        _lowercaseTranscription = State(initialValue: formState.lowercaseTranscription)
        _configName = State(initialValue: formState.name)
        _selectedEmoji = State(initialValue: formState.emoji)
        _selectedAppConfigs = State(initialValue: formState.appConfigs)
        _websiteConfigs = State(initialValue: formState.urlConfigs)
        _useScreenCapture = State(initialValue: formState.useScreenCapture)
        _autoSendKey = State(initialValue: formState.autoSendKey)
        _isDefault = State(initialValue: formState.isDefault)
        _selectedAIProvider = State(initialValue: formState.selectedAIProvider)
        _selectedAIModel = State(initialValue: formState.selectedAIModel)
        _isTranscriptFormattingExpanded = State(initialValue: formState.isTranscriptFormattingExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(mode.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            Form {
                Section("General") {
                    HStack(spacing: 12) {
                        Button {
                            isShowingEmojiPicker.toggle()
                        } label: {
                            Text(selectedEmoji)
                                .font(.system(size: 22))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingEmojiPicker, arrowEdge: .bottom) {
                            EmojiPickerView(
                                selectedEmoji: $selectedEmoji,
                                isPresented: $isShowingEmojiPicker
                            )
                        }

                        TextField("Name", text: $configName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFieldFocused)
                    }
                }

                Section("Trigger Scenarios") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Applications")
                            Spacer()
                            AddIconButton(helpText: "Add application") {
                                loadInstalledApps()
                                isShowingAppPicker = true
                            }
                            .popover(isPresented: $isShowingAppPicker, arrowEdge: .bottom) {
                                AppPickerPopover(
                                    installedApps: filteredApps,
                                    selectedAppConfigs: $selectedAppConfigs,
                                    searchText: $searchText
                                )
                            }
                        }

                        if selectedAppConfigs.isEmpty {
                            Text("No applications added")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)], spacing: 10) {
                                ForEach(selectedAppConfigs) { appConfig in
                                    ZStack(alignment: .topTrailing) {
                                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        } else {
                                            Image(systemName: "app.fill")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 26, height: 26)
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(Color(NSColor.controlBackgroundColor))
                                                )
                                        }

                                        Button {
                                            selectedAppConfigs.removeAll(where: { $0.id == appConfig.id })
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Websites")

                        HStack {
                            TextField("Enter website URL", text: $newWebsiteURL)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addWebsite() }

                            AddIconButton(helpText: "Add website", isDisabled: newWebsiteURL.isEmpty) {
                                addWebsite()
                            }
                        }

                        if websiteConfigs.isEmpty {
                            Text("No websites added")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                                ForEach(websiteConfigs) { urlConfig in
                                    HStack(spacing: 6) {
                                        Image(systemName: "globe")
                                            .foregroundColor(.secondary)
                                        Text(urlConfig.url)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Button {
                                            websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Transcription") {
                    if transcriptionModelManager.usableModels.isEmpty {
                        Text(VoiceInkPowerModePresentation.noTranscriptionModelsAvailableText)
                            .foregroundColor(.secondary)
                    } else {
                        let modelBinding = Binding<String?>(
                            get: {
                                transcriptionSelection.selectedModelNameForPicker(
                                    currentModelName: transcriptionModelManager.currentTranscriptionModel?.name
                                )
                            },
                            set: {
                                applyTranscriptionSelection(transcriptionSelection.selectingModelName($0))
                            }
                        )

                        Picker("Model", selection: modelBinding) {
                            ForEach(transcriptionModelManager.usableModels, id: \.name) { model in
                                Text(model.displayName).tag(model.name as String?)
                            }
                        }
                        .onChange(of: selectedTranscriptionModelName) { _, _ in
                            if let model = selectedTranscriptionModel {
                                applyTranscriptionSelection(
                                    transcriptionSelection.selectingCompatibleLanguage(
                                        for: modelFacts(for: model),
                                        storedLanguage: VoiceInkTranscriptionLanguagePreference.storedLanguage()
                                    )
                                )
                            }
                        }
                    }

                    if let model = selectedTranscriptionModel {
                        let facts = modelFacts(for: model)

                        switch facts.languageControl {
                        case .disabledAutodetect:
                            LabeledContent("Language") {
                                Text("Autodetected")
                                    .foregroundColor(.secondary)
                            }
                            .onAppear {
                                applyTranscriptionSelection(transcriptionSelection.selectingAutodetectLanguage())
                            }
                        case .picker:
                            let languageBinding = Binding<String?>(
                                get: {
                                    transcriptionSelection.selectedLanguageForPicker(
                                        storedLanguage: VoiceInkTranscriptionLanguagePreference.selectedLanguage()
                                    )
                                },
                                set: {
                                    applyTranscriptionSelection(transcriptionSelection.selectingLanguage($0))
                                }
                            )

                            Picker("Language", selection: languageBinding) {
                                ForEach(VoiceInkLanguageCatalog.sortedOptions(facts.languageOptions)) { option in
                                    Text(option.name).tag(option.code as String?)
                                }
                            }
                        case .hiddenDefault:
                            EmptyView()
                                .onAppear {
                                    applyTranscriptionSelection(
                                        transcriptionSelection.selectingDefaultLanguageIfMissing(
                                            VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
                                        )
                                    )
                                }
                        }
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isTranscriptFormattingExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(cleanupPresentation.sectionTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isTranscriptFormattingExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isTranscriptFormattingExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $isTextFormattingEnabled) {
                                HStack(spacing: 4) {
                                    Text(cleanupPresentation.paragraphBreaksToggleTitle)
                                    if let helpText = cleanupPresentation.paragraphBreaksHelpText {
                                        InfoTip(helpText)
                                    }
                                }
                            }

                            Picker(selection: $punctuationCleanupMode) {
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
                        }
                        .padding(.top, 4)
                    }
                }

                Section("AI Enhancement") {
                    Toggle("AI Enhancement", isOn: $isAIEnhancementEnabled)
                        .onChange(of: isAIEnhancementEnabled) { _, newValue in
                            if newValue {
                                applyEnhancementSelection(
                                    enhancementSelection
                                        .fillingMissingProviderAndModel(
                                            currentProvider: aiService.selectedProvider,
                                            currentModel: aiService.currentModel,
                                            treatsEmptyModelAsMissing: false
                                        )
                                        .selectingPromptAfterEnabling(prompts: enhancementService.allPrompts)
                                )
                            }
                        }

                    let providerBinding = Binding<VoiceInkAIEnhancementProviderKind>(
                        get: {
                            enhancementSelection.resolvedProviderForPicker(currentProvider: aiService.selectedProvider)
                        },
                        set: { newValue in
                            applyEnhancementSelection(enhancementSelection.selectingProvider(newValue))
                        }
                    )

                    if isAIEnhancementEnabled {
                        if aiService.connectedProviders.isEmpty {
                            LabeledContent(VoiceInkPowerModePresentation.aiProviderFormTitle) {
                                Text(VoiceInkPowerModePresentation.noAIProvidersConnectedText)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            Picker(VoiceInkPowerModePresentation.aiProviderFormTitle, selection: providerBinding) {
                                ForEach(aiService.connectedProviders, id: \.self) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .onChange(of: selectedAIProvider) { _, _ in
                                applyEnhancementSelection(
                                    enhancementSelection.selectingDefaultModelForSelectedProvider { provider in
                                        provider.defaultTextEnhancementModel()
                                    }
                                )
                            }
                        }

                        if let provider = enhancementSelection.selectedProviderForModelOptions(currentProvider: aiService.selectedProvider),
                           provider != .custom {
                            let models = aiService.availableModels(for: provider)
                            if models.isEmpty {
                                LabeledContent(VoiceInkPowerModePresentation.aiModelFormTitle) {
                                    Text(VoiceInkPowerModePresentation.noAIModelsAvailableText(for: provider))
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            } else {
                                let modelBinding = Binding<String>(
                                    get: {
                                        enhancementSelection.selectedModelForPicker(currentModel: aiService.currentModel)
                                    },
                                    set: { newModelValue in
                                        applyEnhancementSelection(enhancementSelection.selectingModel(newModelValue))
                                    }
                                )

                                Picker(VoiceInkPowerModePresentation.aiModelFormTitle, selection: modelBinding) {
                                    ForEach(models, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }

                                if provider.supportsUserInitiatedTextEnhancementModelRefresh {
                                    Button(VoiceInkPowerModePresentation.refreshModelsButtonTitle) {
                                        Task { await aiService.fetchOpenRouterModels() }
                                    }
                                    .help(VoiceInkPowerModePresentation.refreshModelsButtonHelp)
                                }
                            }
                        }

                        if enhancementService.allPrompts.isEmpty {
                            LabeledContent(VoiceInkPowerModePresentation.enhancementPromptFormTitle) {
                                Text(VoiceInkPowerModePresentation.noEnhancementPromptsAvailableText)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Picker(VoiceInkPowerModePresentation.enhancementPromptFormTitle, selection: $selectedPromptId) {
                                ForEach(enhancementService.allPrompts) { prompt in
                                    Text(prompt.title).tag(prompt.id as UUID?)
                                }
                            }
                        }

                        Toggle(VoiceInkPowerModePresentation.contextAwarenessDisplayText, isOn: $useScreenCapture)
                    }
                }

                Section("Advanced") {
                    Toggle(isOn: $isDefault) {
                        HStack(spacing: 6) {
                            Text(VoiceInkPowerModePresentation.setAsDefaultToggleTitle)
                            InfoTip(VoiceInkPowerModePresentation.setAsDefaultHelpText)
                        }
                    }

                    Picker(selection: $autoSendKey) {
                        ForEach(VoiceInkAutoSendKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(VoiceInkPowerModePresentation.autoSendFormTitle)
                            InfoTip(VoiceInkPowerModePresentation.autoSendHelpText)
                        }
                    }

                    HStack {
                        Text(VoiceInkPowerModePresentation.keyboardShortcutFormTitle)
                        InfoTip(VoiceInkPowerModePresentation.keyboardShortcutHelpText)

                        Spacer()

                        ShortcutRecorder(action: .powerMode(powerModeConfigId))
                            .frame(minHeight: 28)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.controlBackgroundColor))
            .confirmationDialog(
                VoiceInkPowerModePresentation.deleteConfirmationTitle,
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if case .edit(let config) = mode {
                    let deleteConfirmation = VoiceInkPowerModePresentation.deleteConfirmation(configName: config.name)
                    Button(deleteConfirmation.primaryButtonTitle, role: .destructive) {
                        powerModeManager.removeConfiguration(with: config.id)
                        onDismiss()
                    }
                }
                Button(VoiceInkPowerModePresentation.deleteConfirmationCancelButtonTitle, role: .cancel) { }
            } message: {
                if case .edit(let config) = mode {
                    Text(VoiceInkPowerModePresentation.deleteConfirmation(configName: config.name).message)
                }
            }
            .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
            .onAppear {
                // Set AI provider/model after EnvironmentObjects are available
                if case .add = mode {
                    applyEnhancementSelection(
                        enhancementSelection.fillingMissingProviderAndModel(
                            currentProvider: aiService.selectedProvider,
                            currentModel: aiService.currentModel,
                            treatsEmptyModelAsMissing: true
                        )
                    )
                }

                if isAIEnhancementEnabled && selectedPromptId == nil {
                    applyEnhancementSelection(
                        enhancementSelection.selectingPromptAfterEnabling(prompts: enhancementService.allPrompts)
                    )
                }

                if let model = selectedTranscriptionModel {
                    let facts = modelFacts(for: model)
                    if facts.languageControl != .disabledAutodetect {
                        applyTranscriptionSelection(
                            transcriptionSelection.selectingCompatibleLanguage(
                                for: facts,
                                storedLanguage: VoiceInkTranscriptionLanguagePreference.storedLanguage()
                            )
                        )
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFieldFocused = true
                }
            }
            .onDisappear {
                cleanupUnsavedShortcutIfNeeded()
            }

            // Footer
            VStack(spacing: 0) {
                HStack {
                    if case .edit = mode {
                        Button("Delete", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Cancel") { onDismiss() }
                            .keyboardShortcut(.escape, modifiers: [])
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        saveConfiguration()
                    } label: {
                        Text("Save Changes")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    // MARK: - Actions

    private func addWebsite() {
        guard let websiteConfig = VoiceInkPowerModePolicy.websiteConfigForFormInput(newWebsiteURL) else { return }
        websiteConfigs.append(websiteConfig)
        newWebsiteURL = ""
    }

    private func getConfigForForm() -> PowerModeConfig {
        let draft = VoiceInkPowerModeConfigurationDraft(
            id: powerModeConfigId,
            name: configName,
            emoji: selectedEmoji,
            appConfigs: selectedAppConfigs,
            urlConfigs: websiteConfigs,
            isAIEnhancementEnabled: isAIEnhancementEnabled,
            selectedPromptId: selectedPromptId,
            selectedTranscriptionModelName: selectedTranscriptionModelName,
            selectedLanguage: selectedLanguage,
            useScreenCapture: useScreenCapture,
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationCleanupMode,
            lowercaseTranscription: lowercaseTranscription,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel,
            autoSendKey: autoSendKey,
            isDefault: isDefault
        )

        return VoiceInkPowerModePolicy.configuration(from: draft, mode: mode)
    }

    private func loadInstalledApps() {
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        let localAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + localAppURLs + systemAppURLs

        var allApps: [URL] = []

        func scanDirectory(_ baseURL: URL, depth: Int = 0) {
            // Prevent infinite recursion from circular symlinks
            guard depth < 5 else { return }
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for item in enumerator {
                guard let url = item as? URL else { continue }
                let resolvedURL = url.resolvingSymlinksInPath()

                if resolvedURL.pathExtension == "app" {
                    allApps.append(resolvedURL)
                    enumerator.skipDescendants()
                    continue
                }

                // Traverse symlinked directories manually
                var isDirectory: ObjCBool = false
                if url != resolvedURL &&
                   FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) &&
                   isDirectory.boolValue {
                    enumerator.skipDescendants()
                    scanDirectory(resolvedURL, depth: depth + 1)
                }
            }
        }

        for baseURL in allAppURLs {
            scanDirectory(baseURL)
        }

        installedApps = allApps.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func saveConfiguration() {
        let config = getConfigForForm()
        validationErrors = VoiceInkPowerModePolicy.validateForSave(
            candidate: config.powerModePolicyRule,
            mode: mode.saveMode,
            existing: powerModeManager.configurations.powerModePolicyRules
        )

        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }

        if isDefault {
            powerModeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            powerModeManager.addConfiguration(config)
        case .edit:
            powerModeManager.updateConfiguration(config)
        }

        didSaveConfiguration = true
        onDismiss()
    }

    private func cleanupUnsavedShortcutIfNeeded() {
        guard case .add = mode, !didSaveConfiguration else {
            return
        }

        ShortcutStore.removeShortcutStorage(for: .powerMode(powerModeConfigId))
    }
}

extension View {
    func powerModeValidationAlert(
        errors: [VoiceInkPowerModeValidationError],
        isPresented: Binding<Bool>
    ) -> some View {
        let presentation = VoiceInkPowerModePresentation.validationAlert(errors: errors)

        return self.alert(
            presentation.title,
            isPresented: isPresented,
            actions: {
                Button(presentation.buttonTitle, role: .cancel) {}
            },
            message: {
                Text(presentation.message)
            }
        )
    }
}
