import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()

    var body: some View {
        let presentation = provider.apiKeyFormPresentation
        let isKeyVerified = settings.providerAccess.isKeyVerified(for: provider)
        let controlPresentation = apiKeyFormState.iOSControlPresentation(
            storedRuntimeKey: settings.apiKey(for: provider)
        )

        Form {
            Section(header: Text(presentation.apiKeySectionTitle)) {
                if apiKeyFormState.isEditing {
                    let saveAction = controlPresentation.saveRuntimeAction {
                        settings.setAPIKey(apiKeyFormState.enteredKey, for: provider)
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
                            let verifyAction = controlPresentation.verifyRuntimeAction(verify: verifyKey)
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
                    if let storedKeyPresentation = apiKeyFormState.iOSStoredKeyPresentation(
                        storedKey: settings.storedAPIKey(for: provider)
                    ) {
                        HStack {
                            let feedback = storedKeyPresentation.feedback
                            Label(feedback.text, systemImage: feedback.effectiveSystemImageName)
                                .foregroundStyle(feedback.tone.statusColor)
                            Spacer()
                            Button(presentation.changeButtonTitle) {
                                let editPlan = apiKeyFormState.iOSStoredKeyEditPlan(
                                    settings.storedAPIKey(for: provider)
                                )
                                apiKeyFormState = editPlan.formState
                                settings.applyProviderAPIKeyEditPlan(editPlan, for: provider)
                            }
                        }
                        if let existing = storedKeyPresentation.obfuscatedKey {
                            Text(existing).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let feedback = apiKeyFormState.iOSVisibleResultFeedback(isKeyVerified: isKeyVerified) {
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
            apiKeyFormState = .loaded(
                storedKey: settings.storedAPIKey(for: provider),
                isVerified: settings.providerAccess.isKeyVerified(for: provider)
            )
        }
        .onChange(of: apiKeyFormState.enteredKey) { _, _ in
            apiKeyFormState = apiKeyFormState.keyEdited()
        }
    }

    private func verifyKey() {
        Task {
            let startPlan = apiKeyFormState.verificationStartPlan(
                storedRuntimeKey: settings.apiKey(for: provider),
                missingCandidatePolicy: .applyFailurePlan
            )
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
        }
    }

}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
