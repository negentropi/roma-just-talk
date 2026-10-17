import SwiftUI
import RomaCore

struct ConfigurationView: View {
    let mode: RomaPowerModeConfigurationMode
    let powerModeManager: PowerModeManager
    var onDismiss: () -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @FocusState private var isNameFieldFocused: Bool

    @State private var configName: String = RomaPowerModeConfigurationFormState.addDefaultName
    @State private var selectedEmoji: String = RomaPowerModeConfigurationFormState.addDefaultEmoji
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
    @State private var validationErrors: [RomaPowerModeValidationError] = []
    @State private var showValidationAlert = false
    @State private var selectedAIProvider: String?
    @State private var selectedAIModel: String?
    @State private var selectedAppConfigs: [RomaPowerModeAppConfig] = []
    @State private var websiteConfigs: [RomaPowerModeURLConfig] = []
    @State private var newWebsiteURL: String = ""
    @State private var useScreenCapture = false
    @State private var autoSendKey: RomaAutoSendKey = .none
    @State private var isDefault = false
    @State private var isShowingDeleteConfirmation = false
    @State private var powerModeConfigId: UUID = UUID()
    @State private var isTranscriptFormattingExpanded = false
    @State private var didSaveConfiguration = false
    private let cleanupPresentation = RomaTranscriptionCleanupPresentation.macOS

    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        RomaPowerModeAppPickerPolicy.filteredItems(
            installedApps,
            searchText: searchText,
            appName: { $0.name },
            bundleIdentifier: { $0.bundleId }
        )
    }

    private var transcriptionSelection: RomaPowerModeTranscriptionSelection {
        RomaPowerModeTranscriptionSelection(
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

    private func applyTranscriptionSelection(_ selection: RomaPowerModeTranscriptionSelection) {
        selectedTranscriptionModelName = selection.selectedModelName
        selectedLanguage = selection.selectedLanguage
    }

    private func modelFacts(for model: any TranscriptionModel) -> RomaPowerModeTranscriptionModelFacts {
        model.powerModeTranscriptionModelFacts
    }

    private var enhancementSelection: RomaPowerModeEnhancementSelection {
        RomaPowerModeEnhancementSelection(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel
        )
    }

    private func applyEnhancementSelection(_ selection: RomaPowerModeEnhancementSelection) {
        selectedPromptId = selection.selectedPromptId
        selectedAIProvider = selection.selectedAIProvider
        selectedAIModel = selection.selectedAIModel
    }

    init(
        mode: RomaPowerModeConfigurationMode,
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
                    Image(systemName: RomaPowerModePresentation.formCloseSystemImageName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(RomaPowerModePresentation.formCloseHelpText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            Form {
                Section(RomaPowerModePresentation.generalSectionTitle) {
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

                        TextField(RomaPowerModePresentation.nameFieldPlaceholder, text: $configName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFieldFocused)
                    }
                }

                Section(RomaPowerModePresentation.triggerScenariosSectionTitle) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(RomaPowerModePresentation.applicationsSectionTitle)
                            Spacer()
                            AddIconButton(helpText: RomaPowerModePresentation.addApplicationHelpText) {
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
                            Text(RomaPowerModePresentation.noApplicationsText)
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
                                            Image(systemName: RomaPowerModePresentation.appTriggerSystemImageName)
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
                                            selectedAppConfigs = RomaPowerModePolicy.removingAppConfig(
                                                id: appConfig.id,
                                                from: selectedAppConfigs
                                            )
                                        } label: {
                                            Image(systemName: RomaPowerModePresentation.removeTriggerSystemImageName)
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
                        Text(RomaPowerModePresentation.websitesSectionTitle)

                        HStack {
                            TextField(RomaPowerModePresentation.websiteURLFieldPlaceholder, text: $newWebsiteURL)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addWebsite() }

                            AddIconButton(helpText: RomaPowerModePresentation.addWebsiteHelpText, isDisabled: newWebsiteURL.isEmpty) {
                                addWebsite()
                            }
                        }

                        if websiteConfigs.isEmpty {
                            Text(RomaPowerModePresentation.noWebsitesText)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                                ForEach(websiteConfigs) { urlConfig in
                                    HStack(spacing: 6) {
                                        Image(systemName: RomaPowerModePresentation.websiteTriggerSystemImageName)
                                            .foregroundColor(.secondary)
                                        Text(urlConfig.url)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Button {
                                            websiteConfigs = RomaPowerModePolicy.removingWebsiteConfig(
                                                id: urlConfig.id,
                                                from: websiteConfigs
                                            )
                                        } label: {
                                            Image(systemName: RomaPowerModePresentation.removeTriggerSystemImageName)
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

                Section(RomaPowerModePresentation.transcriptionSectionTitle) {
                    if transcriptionModelManager.usableModels.isEmpty {
                        Text(RomaPowerModePresentation.noTranscriptionModelsAvailableText)
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

                        Picker(RomaPowerModePresentation.transcriptionModelPickerTitle, selection: modelBinding) {
                            ForEach(transcriptionModelManager.usableModels, id: \.name) { model in
                                Text(model.displayName).tag(model.name as String?)
                            }
                        }
                        .onChange(of: selectedTranscriptionModelName) { _, _ in
                            transcriptionSelection.modelChangePlan(
                                selectedModelFacts: selectedTranscriptionModel.map { modelFacts(for: $0) },
                                storedLanguage: RomaTranscriptionLanguagePreference.storedLanguage()
                            )
                            .applyRuntimeState(
                                applyTranscriptionSelection: applyTranscriptionSelection
                            )
                        }
                    }

                    if let model = selectedTranscriptionModel {
                        let facts = modelFacts(for: model)

                        if facts.shouldShowAutodetectOnlyLanguage {
                            LabeledContent(RomaPowerModePresentation.transcriptionLanguageTitle) {
                                Text(RomaPowerModePresentation.autodetectedLanguageText)
                                    .foregroundColor(.secondary)
                            }
                            .onAppear {
                                transcriptionSelection.languageControlAppearPlan(
                                    for: facts,
                                    defaultLanguage: RomaDefaultSettings.macOS.selectedTranscriptionLanguage
                                )
                                .applyRuntimeState(
                                    applyTranscriptionSelection: applyTranscriptionSelection
                                )
                            }
                        } else if facts.shouldShowLanguagePicker {
                            let languageBinding = Binding<String?>(
                                get: {
                                    transcriptionSelection.selectedLanguageForPicker(
                                        storedLanguage: RomaTranscriptionLanguagePreference.selectedLanguage()
                                    )
                                },
                                set: {
                                    applyTranscriptionSelection(transcriptionSelection.selectingLanguage($0))
                                }
                            )

                            Picker(RomaPowerModePresentation.transcriptionLanguageTitle, selection: languageBinding) {
                                ForEach(RomaLanguageCatalog.sortedOptions(facts.languageOptions)) { option in
                                    Text(option.name).tag(option.code as String?)
                                }
                            }
                        } else if facts.shouldApplyDefaultLanguageIfMissing {
                            EmptyView()
                                .onAppear {
                                    transcriptionSelection.languageControlAppearPlan(
                                        for: facts,
                                        defaultLanguage: RomaDefaultSettings.macOS.selectedTranscriptionLanguage
                                    )
                                    .applyRuntimeState(
                                        applyTranscriptionSelection: applyTranscriptionSelection
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
                            Image(systemName: RomaPowerModePresentation.transcriptFormattingDisclosureSystemImageName)
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

                Section(RomaPowerModePresentation.aiEnhancementSectionTitle) {
                    Toggle(RomaPowerModePresentation.aiEnhancementToggleTitle, isOn: $isAIEnhancementEnabled)
                        .onChange(of: isAIEnhancementEnabled) { _, newValue in
                            enhancementSelection.togglePlan(
                                isEnabled: newValue,
                                currentProvider: aiService.selectedProvider,
                                currentModel: aiService.currentModel,
                                prompts: enhancementService.allPrompts
                            )
                            .applyRuntimeState(applyEnhancementSelection: applyEnhancementSelection)
                        }

                    let providerBinding = Binding<RomaAIEnhancementProviderKind>(
                        get: {
                            enhancementSelection.resolvedProviderForPicker(currentProvider: aiService.selectedProvider)
                        },
                        set: { newValue in
                            applyEnhancementSelection(enhancementSelection.selectingProvider(newValue))
                        }
                    )

                    if isAIEnhancementEnabled {
                        if aiService.connectedProviders.isEmpty {
                            LabeledContent(RomaPowerModePresentation.aiProviderFormTitle) {
                                Text(RomaPowerModePresentation.noAIProvidersConnectedText)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            Picker(RomaPowerModePresentation.aiProviderFormTitle, selection: providerBinding) {
                                ForEach(aiService.connectedProviders, id: \.self) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .onChange(of: selectedAIProvider) { _, _ in
                                enhancementSelection.providerChangePlan { provider in
                                    provider.defaultTextEnhancementModel()
                                }
                                .applyRuntimeState(
                                    applyEnhancementSelection: applyEnhancementSelection
                                )
                            }
                        }

                        if let provider = enhancementSelection.selectedProviderForModelOptions(currentProvider: aiService.selectedProvider),
                           RomaPowerModePresentation.shouldShowAIModelOptions(for: provider) {
                            let models = aiService.availableModels(for: provider)
                            if models.isEmpty {
                                LabeledContent(RomaPowerModePresentation.aiModelFormTitle) {
                                    Text(RomaPowerModePresentation.noAIModelsAvailableText(for: provider))
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

                                Picker(RomaPowerModePresentation.aiModelFormTitle, selection: modelBinding) {
                                    ForEach(models, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }

                                if RomaPowerModePresentation.shouldShowRefreshModelsButton(for: provider) {
                                    Button(RomaPowerModePresentation.refreshModelsButtonTitle) {
                                        Task { await aiService.fetchOpenRouterModels() }
                                    }
                                    .help(RomaPowerModePresentation.refreshModelsButtonHelp)
                                }
                            }
                        }

                        if enhancementService.allPrompts.isEmpty {
                            LabeledContent(RomaPowerModePresentation.enhancementPromptFormTitle) {
                                Text(RomaPowerModePresentation.noEnhancementPromptsAvailableText)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Picker(RomaPowerModePresentation.enhancementPromptFormTitle, selection: $selectedPromptId) {
                                ForEach(enhancementService.allPrompts) { prompt in
                                    Text(prompt.title).tag(prompt.id as UUID?)
                                }
                            }
                        }

                        Toggle(RomaPowerModePresentation.contextAwarenessDisplayText, isOn: $useScreenCapture)
                    }
                }

                Section(RomaPowerModePresentation.advancedSectionTitle) {
                    Toggle(isOn: $isDefault) {
                        HStack(spacing: 6) {
                            Text(RomaPowerModePresentation.setAsDefaultToggleTitle)
                            InfoTip(RomaPowerModePresentation.setAsDefaultHelpText)
                        }
                    }

                    Picker(selection: $autoSendKey) {
                        ForEach(RomaAutoSendKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(RomaPowerModePresentation.autoSendFormTitle)
                            InfoTip(RomaPowerModePresentation.autoSendHelpText)
                        }
                    }

                    HStack {
                        Text(RomaPowerModePresentation.keyboardShortcutFormTitle)
                        InfoTip(RomaPowerModePresentation.keyboardShortcutHelpText)

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
                RomaPowerModePresentation.deleteConfirmationTitle,
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if case .edit(let config) = mode {
                    let deleteConfirmation = RomaPowerModePresentation.deleteConfirmation(configName: config.name)
                    Button(deleteConfirmation.primaryButtonTitle, role: .destructive) {
                        powerModeManager.removeConfiguration(with: config.id)
                        onDismiss()
                    }
                }
                Button(RomaPowerModePresentation.deleteConfirmationCancelButtonTitle, role: .cancel) { }
            } message: {
                if case .edit(let config) = mode {
                    Text(RomaPowerModePresentation.deleteConfirmation(configName: config.name).message)
                }
            }
            .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
            .onAppear {
                let selectedModelFacts = selectedTranscriptionModel.map { modelFacts(for: $0) }
                mode.appearPlan(
                    enhancementSelection: enhancementSelection,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    prompts: enhancementService.allPrompts,
                    currentAIProvider: aiService.selectedProvider,
                    currentAIModel: aiService.currentModel,
                    transcriptionSelection: transcriptionSelection,
                    selectedTranscriptionModelFacts: selectedModelFacts,
                    storedLanguage: RomaTranscriptionLanguagePreference.storedLanguage()
                )
                .applyRuntimeState(
                    applyEnhancementSelection: applyEnhancementSelection,
                    applyTranscriptionSelection: applyTranscriptionSelection
                )

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
                        Button(RomaPowerModePresentation.formDeleteButtonTitle, role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(RomaPowerModePresentation.formCancelButtonTitle) { onDismiss() }
                            .keyboardShortcut(.escape, modifiers: [])
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        saveConfiguration()
                    } label: {
                        Text(RomaPowerModePresentation.formSaveButtonTitle)
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!RomaPowerModePolicy.canSaveConfigurationName(configName))
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
        guard let updatedConfigs = RomaPowerModePolicy.addingWebsiteConfig(
            forFormInput: newWebsiteURL,
            to: websiteConfigs
        ) else { return }

        websiteConfigs = updatedConfigs
        newWebsiteURL = ""
    }

    private func draftForForm() -> RomaPowerModeConfigurationDraft {
        RomaPowerModeConfigurationDraft(
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
        RomaPowerModePolicy.formSavePlan(
            draft: draftForForm(),
            mode: mode,
            existing: powerModeManager.configurations.powerModePolicyRules
        )
        .applyRuntimeState(
            setValidationErrors: { validationErrors = $0 },
            showValidationAlert: { showValidationAlert = true },
            saveConfiguration: { config, saveMode in
                powerModeManager.saveConfiguration(config, mode: saveMode)
            },
            markSaved: { didSaveConfiguration = true },
            dismiss: onDismiss
        )
    }

    private func cleanupUnsavedShortcutIfNeeded() {
        mode.dismissalPlan(didSaveConfiguration: didSaveConfiguration)
            .applyRuntimeState {
                ShortcutStore.removeShortcutStorage(for: .powerMode(powerModeConfigId))
            }
    }
}

extension View {
    func powerModeValidationAlert(
        errors: [RomaPowerModeValidationError],
        isPresented: Binding<Bool>
    ) -> some View {
        let presentation = RomaPowerModePresentation.validationAlert(errors: errors)

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
