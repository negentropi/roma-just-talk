import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()
    @State private var customBaseURL = ""
    @State private var customModel = ""
    private let providerSettingsPresentation = VoiceInkAIEnhancementProviderSettingsPresentation.iOS

    var body: some View {
        let snapshot = settings.providerAccess.apiKeyFormSnapshot(
            for: provider,
            formState: apiKeyFormState
        )
        let presentation = snapshot.presentation
        let controlPresentation = snapshot.controlPresentation

        Form {
            if provider == .customAI {
                Section(header: Text(providerSettingsPresentation.sectionTitle)) {
                    TextField(
                        providerSettingsPresentation.customProviderBaseURLPlaceholder,
                        text: $customBaseURL
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    TextField(
                        providerSettingsPresentation.customProviderModelPlaceholder,
                        text: $customModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(providerSettingsPresentation.ollamaSaveButtonTitle) {
                        settings.updateCustomEnhancementConfiguration(
                            baseURL: customBaseURL,
                            model: customModel
                        )
                    }
                    .disabled(!canSaveCustomConfiguration)
                }
            }

            Section(header: Text(presentation.apiKeySectionTitle)) {
                if snapshot.isEditing {
                    let saveAction = controlPresentation.saveRuntimeAction {
                        settings.setAPIKey(snapshot.enteredKey, for: provider)
                    }
                    SecureField(presentation.apiKeyPlaceholder, text: $apiKeyFormState.enteredKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(action: saveAction ?? {}) {
                            Label(
                                presentation.saveButtonTitle,
                                systemImage: presentation.saveButtonSystemImageName
                            )
                        }
                        .disabled(saveAction == nil)
                        Spacer()
                        if controlPresentation.isVerificationProgressVisible {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            let startPlan = snapshot.verificationStartPlan(
                                missingCandidatePolicy: .applyFailurePlan
                            )
                            let verifyAction = controlPresentation.verifyRuntimeAction {
                                verifyKey(startPlan: startPlan)
                            }
                            Button(action: verifyAction ?? {}) {
                                Label(
                                    presentation.verifyButtonTitle,
                                    systemImage: presentation.verifyButtonSystemImageName
                                )
                            }
                            .disabled(controlPresentation.isVerifyButtonDisabled)
                        }
                    }
                } else {
                    if let storedKeyPresentation = snapshot.storedKeyPresentation {
                        HStack {
                            let feedback = storedKeyPresentation.feedback
                            Label(feedback.text, systemImage: feedback.effectiveSystemImageName)
                                .foregroundStyle(feedback.tone.statusColor)
                            Spacer()
                            Button(presentation.changeButtonTitle) {
                                apiKeyFormState = snapshot.storedKeyEditPlan.formState
                                settings.applyProviderAPIKeyEditPlan(snapshot.storedKeyEditPlan, for: provider)
                            }
                        }
                        if let existing = storedKeyPresentation.obfuscatedKey {
                            Text(existing).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let feedback = snapshot.visibleResultFeedback {
                    Label(feedback.text, systemImage: feedback.effectiveSystemImageName)
                        .foregroundStyle(feedback.tone.statusColor)
                }
            }
            
            Section(header: Text(presentation.consoleSectionTitle)) {
                Link(destination: provider.consoleURL) {
                    HStack {
                        Image(systemName: presentation.consoleLeadingSystemImageName)
                        Text(presentation.consoleLinkTitle)
                        Spacer()
                        Image(systemName: presentation.consoleTrailingSystemImageName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKeyFormState = snapshot.loadedFormState
            if provider == .customAI {
                customBaseURL = VoiceInkDynamicAIProviderPreference.customProviderBaseURL()
                customModel = VoiceInkDynamicAIProviderPreference.customProviderModel()
            }
        }
        .onChange(of: apiKeyFormState.enteredKey) { _, _ in
            apiKeyFormState = apiKeyFormState.keyEdited()
        }
        .task {
            if provider == .openRouter {
                await settings.refreshOpenRouterModels()
            }
        }
    }

    private func verifyKey(startPlan: VoiceInkProviderAPIKeyVerificationStartPlan) {
        Task {
            guard let result = await startPlan.applyRuntimeState(
                setFormState: { apiKeyFormState = $0 },
                verifyCandidate: { keyToVerify in
                    await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)
                }
            ) else {
                return
            }

            apiKeyFormState
                .verificationCompletionPlan(startPlan: startPlan, result: result)
                .applyRuntimeState(
                    setFormState: { apiKeyFormState = $0 },
                    applyVerificationPlan: { settings.applyAPIKeyVerificationPlan($0, for: provider) }
                )
            if provider == .openRouter, result.isValid {
                await settings.refreshOpenRouterModels()
            }
        }
    }

    private var canSaveCustomConfiguration: Bool {
        URL(string: customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && VoiceInkProviderCredential.nonBlank(customModel) != nil
    }

}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
