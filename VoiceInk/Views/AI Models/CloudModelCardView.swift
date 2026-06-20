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
    @State private var apiKey = ""
    @State private var streamingEnabled: Bool
    @State private var preloadEnabled: Bool

    init(model: CloudModel, isCurrent: Bool, setDefaultAction: @escaping () -> Void) {
        self.model = model
        self.isCurrent = isCurrent
        self.setDefaultAction = setDefaultAction
        _streamingEnabled = State(initialValue: VoiceInkTranscriptionStreamingPreference.isEnabled(forModelName: model.name))
        _preloadEnabled = State(initialValue: VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(forModelName: model.name))
    }
    @State private var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()

    private var isVerifying: Bool {
        verificationProgress.isVerifying
    }
    
    private var isConfigured: Bool {
        return APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
    }

    private var apiKeyDraft: VoiceInkProviderAPIKeyDraft {
        VoiceInkProviderAPIKeyDraft(
            enteredKey: apiKey,
            storedRuntimeKey: APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName)
        )
    }

    private var canVerifyAPIKey: Bool {
        apiKeyDraft.canVerify
    }

    private var apiKeyCardPresentation: VoiceInkProviderAPIKeyCardPresentation {
        VoiceInkProviderAPIKeyCardPresentation(providerDisplayName: model.provider.rawValue)
    }

    private var streamingModePresentation: VoiceInkTranscriptionStreamingModePresentation {
        VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: streamingEnabled,
            isStreamingOnly: isStreamingOnly,
            isPreloadEnabled: preloadEnabled
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection
            }
            .padding(16)
            
            // Expandable configuration section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                configurationSection
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
    
    private var isStreamingOnly: Bool {
        model.streamingPreferenceSnapshot.isStreamingOnly
    }

    private var streamingModeBadge: some View {
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
                    if !isStreamingOnly {
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
    
    private var actionSection: some View {
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
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(apiKeyCardPresentation.configurationSectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            HStack(spacing: 8) {
                SecureField(apiKeyCardPresentation.apiKeyFieldPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isVerifying)
                
                Button(action: verifyAPIKey) {
                    HStack(spacing: 4) {
                        if isVerifying {
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
                .disabled(!canVerifyAPIKey || isVerifying)
            }
            
            if let feedback = verificationProgress.macOSInlineFeedback {
                Text(feedback.text)
                    .font(.caption)
                    .foregroundColor(feedback.tone.macOSStatusColor)
            }
        }
    }
    
    private func loadSavedAPIKey() {
        if let savedKey = APIKeyManager.shared.getStoredAPIKey(forProvider: model.provider.apiKeyProviderName) {
            apiKey = savedKey
        }

        if APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName) {
            verificationProgress = .success
        }
    }
    
    private func verifyAPIKey() {
        let draft = apiKeyDraft
        guard let keyToVerify = draft.verificationCandidate else { return }

        verificationProgress = .verifying
        guard let provider = model.provider.coreTranscriptionModelProvider else {
            verificationProgress = .unsupportedProviderFailure
            return
        }

        Task {
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)

            await MainActor.run {
                let plan = draft.verificationApplicationPlan(for: result)
                verificationProgress = plan.progress

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
        apiKey = ""
        verificationProgress = .idle

        if isCurrent {
            transcriptionModelManager.clearCurrentTranscriptionModel()
        }

        transcriptionModelManager.refreshAllAvailableModels()

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }

}
