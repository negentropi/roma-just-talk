import SwiftUI
import LLMkit
import VoiceInkCore

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL: String = VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedOllamaModel: String = VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(
        fallback: VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
    )
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false
    @State private var localCLICommandTemplate: String = ""
    @State private var localCLITimeoutSeconds: Double = VoiceInkLocalCLIPreference.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false

    private var apiKeyDraft: VoiceInkAIEnhancementAPIKeyDraft {
        VoiceInkAIEnhancementAPIKeyDraft(
            provider: aiService.selectedProvider,
            enteredKey: apiKey
        )
    }

    private var hasDraftAPIKey: Bool {
        apiKeyDraft.hasEnteredKey
    }

    private var obfuscatedSelectedAPIKey: String {
        VoiceInkSecretPresentation.obfuscatedAPIKeyOrPlaceholder(aiService.apiKey)
    }

    private var selectedProviderSettingsSurface: VoiceInkAIEnhancementSettingsSurface {
        aiService.selectedProvider.textEnhancementSettingsSurface
    }

    private var connectionStatusPresentation: VoiceInkAIEnhancementConnectionStatusPresentation? {
        providerSettingsPresentation.connectionStatus(
            surface: selectedProviderSettingsSurface,
            isAPIKeyValid: aiService.isAPIKeyValid,
            isCheckingOllama: isCheckingOllama,
            hasOllamaModels: !ollamaModels.isEmpty
        )
    }

    private let providerSettingsPresentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS
    private let localCLIPresentation = VoiceInkLocalCLIPreference.macOSSettingsPresentation
    
    var body: some View {
        Section(providerSettingsPresentation.sectionTitle) {
            HStack {
                Picker(providerSettingsPresentation.providerPickerTitle, selection: $aiService.selectedProvider) {
                    ForEach(VoiceInkAIEnhancementProviderKind.selectableTextEnhancementProviders, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.automatic)
                .tint(.blue)

                if let connectionStatusPresentation {
                    Spacer()

                    switch connectionStatusPresentation {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)

                    case .status(let text, let tone):
                        Circle()
                            .fill(tone.macOSStatusColor)
                            .frame(width: 8, height: 8)
                        Text(text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: aiService.selectedProvider) { _, _ in
                syncSelectedProviderSettingsSurface()
            }

            VStack(alignment: .leading, spacing: 12) {
                // Model Selection
                if aiService.selectedProvider.supportsUserInitiatedTextEnhancementModelRefresh {
                    if aiService.availableModels.isEmpty {
                        HStack {
                            Text(providerSettingsPresentation.noModelsLoadedText)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label(providerSettingsPresentation.refreshButtonTitle, systemImage: "arrow.clockwise")
                            }
                        }
                    } else {
                        HStack {
                            Picker(providerSettingsPresentation.modelPickerTitle, selection: Binding(
                                get: { aiService.currentModel },
                                set: { aiService.selectModel($0) }
                            )) {
                                ForEach(aiService.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label(providerSettingsPresentation.refreshButtonTitle, systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    
                } else if aiService.selectedProvider.textEnhancementModelCatalogSource == .staticModels &&
                            !aiService.availableModels.isEmpty {
                    Picker(providerSettingsPresentation.modelPickerTitle, selection: Binding(
                        get: { aiService.currentModel },
                        set: { aiService.selectModel($0) }
                    )) {
                        ForEach(aiService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if selectedProviderSettingsSurface == .ollama {
                    if isEditingURL {
                        HStack {
                            TextField(providerSettingsPresentation.ollamaBaseURLFieldTitle, text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(providerSettingsPresentation.ollamaSaveButtonTitle) {
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                                isEditingURL = false
                            }
                        }
                    } else {
                        HStack {
                            Text(providerSettingsPresentation.ollamaServerText(baseURL: ollamaBaseURL))
                            Spacer()
                            Button(providerSettingsPresentation.ollamaEditButtonTitle) { isEditingURL = true }
                            Button(action: {
                                ollamaBaseURL = VoiceInkPreferenceDefault.ollamaBaseURL
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help(providerSettingsPresentation.ollamaResetButtonHelp)
                        }
                    }

                    if !ollamaModels.isEmpty {
                        Divider()

                        Picker(providerSettingsPresentation.modelPickerTitle, selection: $selectedOllamaModel) {
                            ForEach(ollamaModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .onChange(of: selectedOllamaModel) { oldValue, newValue in
                            aiService.updateSelectedOllamaModel(newValue)
                        }
                    }

                } else if selectedProviderSettingsSurface == .localCLI {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localCLIPresentation.commandTitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Menu(localCLIPresentation.loadTemplateButtonTitle) {
                                ForEach(VoiceInkLocalCLITemplate.allCases) { template in
                                    Button(template.displayName) {
                                        aiService.loadLocalCLITemplate(template)
                                        syncLocalCLIStateFromService()
                                    }
                                }
                            }
                        }

                        TextEditor(text: $localCLICommandTemplate)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .onChange(of: localCLICommandTemplate) { _, newValue in
                                guard !isSyncingLocalCLIState else { return }
                                if newValue != aiService.localCLICommandTemplate {
                                    aiService.updateLocalCLICommandTemplate(newValue)
                                }
                        }
                    }

                    Picker(localCLIPresentation.timeoutPickerTitle, selection: $localCLITimeoutSeconds) {
                        ForEach(VoiceInkLocalCLIPreference.timeoutOptions, id: \.self) { timeout in
                            Text(VoiceInkLocalCLIPreference.timeoutLabel(for: timeout)).tag(timeout)
                        }
                    }
                    .onChange(of: localCLITimeoutSeconds) { _, newValue in
                        aiService.updateLocalCLITimeoutSeconds(newValue)
                    }

                    Text(localCLIPresentation.environmentHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !aiService.isAPIKeyValid {
                        Text(localCLIPresentation.configurationRequiredHelpText)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                } else if selectedProviderSettingsSurface == .custom {
                    TextField(
                        providerSettingsPresentation.customProviderBaseURLFieldTitle,
                        text: $aiService.customBaseURL,
                        prompt: Text(providerSettingsPresentation.customProviderBaseURLPlaceholder)
                    )
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    TextField(
                        providerSettingsPresentation.customProviderModelFieldTitle,
                        text: $aiService.customModel,
                        prompt: Text(providerSettingsPresentation.customProviderModelPlaceholder)
                    )
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    if aiService.isAPIKeyValid {
                        HStack {
                            Text(providerSettingsPresentation.customProviderAPIKeySetText)
                            Spacer()
                            Text(obfuscatedSelectedAPIKey)
                                .foregroundColor(.secondary)
                            Button(providerSettingsPresentation.customProviderRemoveKeyButtonTitle, role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField(providerSettingsPresentation.apiKeyFieldTitle, text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button(providerSettingsPresentation.verifyAndSaveButtonTitle) {
                            verifyAndSaveAPIKey()
                        }
                        .disabled(!providerSettingsPresentation.canSubmitCustomProvider(
                            baseURL: aiService.customBaseURL,
                            modelName: aiService.customModel,
                            hasDraftAPIKey: hasDraftAPIKey
                        ))
                    }
                    
                } else {
                    if aiService.isAPIKeyValid {
                        HStack {
                            Text(providerSettingsPresentation.apiKeyFieldTitle)
                            Spacer()
                            Text(obfuscatedSelectedAPIKey)
                                .foregroundColor(.secondary)
                            Button(providerSettingsPresentation.defaultAPIKeyRemoveButtonTitle, role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField(providerSettingsPresentation.apiKeyFieldTitle, text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if let url = aiService.selectedProvider.apiKeyConsoleURL {
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                        Text(providerSettingsPresentation.getAPIKeyButtonTitle)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Button(action: {
                                verifyAndSaveAPIKey()
                            }) {
                                HStack {
                                    if isVerifying {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(providerSettingsPresentation.verifyAndSaveButtonTitle)
                                }
                            }
                            .disabled(!hasDraftAPIKey)
                        }
                    }
                }
            }
        }
        .alert(providerSettingsPresentation.errorAlertTitle, isPresented: $showAlert) {
            Button(providerSettingsPresentation.errorAlertDismissButtonTitle, role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            syncSelectedProviderSettingsSurface()
        }
    }

    private func syncSelectedProviderSettingsSurface() {
        switch selectedProviderSettingsSurface {
        case .ollama:
            checkOllamaConnection()
        case .localCLI:
            syncLocalCLIStateFromService()
        case .apiKey, .custom:
            break
        }
    }

    private func verifyAndSaveAPIKey() {
        isVerifying = true
        aiService.saveAPIKey(apiKey) { result in
            isVerifying = false
            if !result.isValid {
                showAPIKeyVerificationFailure(result)
            }
            apiKey = ""
        }
    }

    private func showAPIKeyVerificationFailure(_ result: VoiceInkAPIKeyVerificationResult) {
        let progress = VoiceInkProviderAPIKeyVerificationProgress.failure(message: result.errorMessage)
        guard let feedback = progress.macOSInlineFeedback else {
            return
        }
        alertMessage = feedback.text
        showAlert = true
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }
    
    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    ollamaModels = await aiService.fetchOllamaModels()
                    isCheckingOllama = false
                }
            } else {
                ollamaModels = []
                isCheckingOllama = false
                alertMessage = providerSettingsPresentation.ollamaConnectionFailureMessage
                showAlert = true
            }
        }
    }
    
}
