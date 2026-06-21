import SwiftUI
import AppKit
import LLMkit
import VoiceInkCore

// MARK: - Cloud Model Card View
struct CloudModelCardView: View {
    let model: CloudModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var selectedLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    @State private var isExpanded = false
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()
    @State private var streamingEnabled: Bool
    @State private var preloadEnabled: Bool

    init(model: CloudModel, isCurrent: Bool, setDefaultAction: @escaping () -> Void) {
        self.model = model
        self.isCurrent = isCurrent
        self.setDefaultAction = setDefaultAction
        _streamingEnabled = State(initialValue: VoiceInkTranscriptionStreamingPreference.isEnabled(forModelName: model.name))
        _preloadEnabled = State(initialValue: VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(forModelName: model.name))
    }
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()

    private var isConfigured: Bool {
        return APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
    }

    var body: some View {
        let apiKeyCardPresentation = VoiceInkProviderAPIKeyCardPresentation(providerDisplayName: model.provider.rawValue)

        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection(apiKeyCardPresentation: apiKeyCardPresentation)
            }
            .padding(16)
            
            // Expandable configuration section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                configurationSection(apiKeyCardPresentation: apiKeyCardPresentation)
                    .padding(16)
            }
        }
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .onAppear {
            loadSavedAPIKey()
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            if model.supportsStreaming && isConfigured {
                streamingModeBadge
            }

            Spacer()
        }
    }
    
    private var streamingModeBadge: some View {
        let streamingModePresentation = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: streamingEnabled,
            isStreamingOnly: model.streamingPreferenceSnapshot.isStreamingOnly,
            isPreloadEnabled: preloadEnabled
        )

        HStack(spacing: 8) {
            Toggle(
                streamingModePresentation.streamingToggleTitle,
                isOn: streamingModePresentation.isStreamingToggleForcedOn ? .constant(true) : $streamingEnabled
            )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))
                .disabled(streamingModePresentation.isStreamingToggleDisabled)
                .onChange(of: streamingEnabled) { _, newValue in
                    if !streamingModePresentation.isStreamingToggleForcedOn {
                        VoiceInkTranscriptionStreamingPreference.saveIsEnabled(newValue, forModelName: model.name)
                        ensureCurrentModelLanguageIsStillValid()
                        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                    }
                }
                .help(streamingModePresentation.streamingToggleHelp)

            Toggle(streamingModePresentation.preloadToggleTitle, isOn: $preloadEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))
                .onChange(of: preloadEnabled) { _, newValue in
                    VoiceInkRollingBufferPreloadSettings.savePerModelPreloadEnabled(newValue, forModelName: model.name)
                    NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                }
                .help(streamingModePresentation.preloadToggleHelp)
        }
    }

    private func ensureCurrentModelLanguageIsStillValid() {
        guard transcriptionModelManager.currentTranscriptionModel?.name == model.name else {
            return
        }

        let compatibleLanguage = model.validTranscriptionLanguageOrFallback(selectedLanguage)
        if selectedLanguage != compatibleLanguage {
            selectedLanguage = compatibleLanguage
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Provider
            Label(model.provider.rawValue, systemImage: "cloud")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            // Speed
            HStack(spacing: 3) {
                Text(VoiceInkModelManagementPresentation.speedLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            // Accuracy
            HStack(spacing: 3) {
                Text(VoiceInkModelManagementPresentation.accuracyLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private func actionSection(
        apiKeyCardPresentation: VoiceInkProviderAPIKeyCardPresentation
    ) -> some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text(VoiceInkModelManagementPresentation.defaultModelTitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isConfigured {
                Button(action: setDefaultAction) {
                    Text(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle)
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(apiKeyCardPresentation.configureButtonTitle)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: apiKeyCardPresentation.configureButtonSystemImageName)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                            .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            if isConfigured {
                Menu {
                    Button {
                        clearAPIKey()
                    } label: {
                        Label(
                            apiKeyCardPresentation.removeAPIKeyButtonTitle,
                            systemImage: apiKeyCardPresentation.removeAPIKeyButtonSystemImageName
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
    
    private func configurationSection(
        apiKeyCardPresentation: VoiceInkProviderAPIKeyCardPresentation
    ) -> some View {
        let verificationProgress = apiKeyFormState.verificationProgress
        let apiKeyDraft = apiKeyFormState.draft(
            storedRuntimeKey: APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName)
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text(apiKeyCardPresentation.configurationSectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            HStack(spacing: 8) {
                SecureField(apiKeyCardPresentation.apiKeyFieldPlaceholder, text: $apiKeyFormState.enteredKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(verificationProgress.isVerifying)
                
                Button(action: verifyAPIKey) {
                    HStack(spacing: 4) {
                        if verificationProgress.isVerifying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: verificationProgress.macOSVerifyButtonSystemImageName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(verificationProgress.macOSVerifyButtonTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(verificationProgress.isSuccess ? Color(.systemGreen) : Color(.controlAccentColor))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!apiKeyDraft.canVerify || verificationProgress.isVerifying)
            }
            
            if let feedback = verificationProgress.macOSInlineFeedback {
                Text(feedback.text)
                    .font(.caption)
                    .foregroundColor(feedback.tone.macOSStatusColor)
            }
        }
    }
    
    private func loadSavedAPIKey() {
        let hasSavedKey = APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
        apiKeyFormState = VoiceInkProviderAPIKeyFormState(
            enteredKey: APIKeyManager.shared.getStoredAPIKey(forProvider: model.provider.apiKeyProviderName) ?? "",
            verificationProgress: hasSavedKey ? .success : .idle,
            isEditing: !hasSavedKey
        )
    }
    
    private func verifyAPIKey() {
        let startPlan = apiKeyFormState.verificationStartPlan(
            storedRuntimeKey: APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName),
            missingCandidatePolicy: .keepCurrentState
        )
        apiKeyFormState = startPlan.formState
        guard let keyToVerify = startPlan.candidate else { return }

        guard let provider = model.provider.coreTranscriptionModelProvider else {
            apiKeyFormState = apiKeyFormState.applyingVerificationPlan(
                VoiceInkProviderAPIKeyVerificationApplicationPlan(
                    progress: .unsupportedProviderFailure,
                    keyToSave: nil,
                    shouldMarkKeyVerified: false
                )
            )
            return
        }

        Task {
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)

            await MainActor.run {
                let plan = startPlan.draft.verificationApplicationPlan(for: result)
                apiKeyFormState = apiKeyFormState.applyingVerificationPlan(plan)

                if plan.shouldMarkKeyVerified {
                    if let keyToSave = plan.keyToSave {
                        APIKeyManager.shared.saveAPIKey(keyToSave, forProvider: model.provider.apiKeyProviderName)
                    }
                    transcriptionModelManager.refreshAllAvailableModels()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = false
                    }
                }
            }
        }
    }
    
    private func clearAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: model.provider.apiKeyProviderName)
        apiKeyFormState = VoiceInkProviderAPIKeyFormState()

        if isCurrent {
            transcriptionModelManager.clearCurrentTranscriptionModel()
        }

        transcriptionModelManager.refreshAllAvailableModels()

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }

}
