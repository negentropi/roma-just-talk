import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()

    private var isKeyVerified: Bool {
        settings.isKeyVerified(for: provider)
    }

    private var apiKeyDraft: VoiceInkProviderAPIKeyDraft {
        apiKeyFormState.draft(
            storedRuntimeKey: settings.apiKey(for: provider)
        )
    }

    var body: some View {
        let presentation = provider.apiKeyFormPresentation

        Form {
            Section(header: Text(presentation.apiKeySectionTitle)) {
                if apiKeyFormState.isEditing {
                    SecureField(presentation.apiKeyPlaceholder, text: $apiKeyFormState.enteredKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(action: saveKey) {
                            Label(
                                presentation.saveButtonTitle,
                                systemImage: presentation.saveButtonSystemImageName
                            )
                        }
                        .disabled(!apiKeyDraft.hasEnteredKey)
                        Spacer()
                        if apiKeyFormState.verificationProgress.isVerifying {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Button(action: verifyKey) {
                                Label(
                                    presentation.verifyButtonTitle,
                                    systemImage: presentation.verifyButtonSystemImageName
                                )
                            }
                            .disabled(!apiKeyDraft.canVerify)
                        }
                    }
                } else {
                    HStack {
                        let feedback = VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
                        Label(feedback.text, systemImage: feedback.effectiveSystemImageName)
                            .foregroundStyle(feedback.tone.statusColor)
                        Spacer()
                        Button(presentation.changeButtonTitle) {
                            apiKeyFormState = apiKeyFormState.editingStoredKey(
                                settings.storedAPIKey(for: provider)
                            )
                            settings.setKeyVerified(false, for: provider)
                        }
                    }
                    if let existing = VoiceInkSecretPresentation.obfuscatedAPIKey(settings.storedAPIKey(for: provider)) {
                        Text(existing).font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Only show verification result when actively verifying and not already verified
                if let feedback = apiKeyFormState.verificationProgress.iOSResultFeedback, !isKeyVerified {
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
                isVerified: isKeyVerified
            )
        }
        .onChange(of: apiKeyFormState.enteredKey) { _, _ in
            apiKeyFormState = apiKeyFormState.keyEdited()
        }
    }

    private func saveKey() {
        settings.setAPIKey(apiKeyFormState.enteredKey, for: provider)
    }

    private func verifyKey() {
        Task {
            apiKeyFormState = apiKeyFormState.verifying()
            let draft = apiKeyDraft
            guard let keyToVerify = draft.verificationCandidate else {
                apiKeyFormState = apiKeyFormState.applyingVerificationPlan(
                    VoiceInkProviderAPIKeyDraft.missingVerificationCandidatePlan()
                )
                return
            }
            
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)
            let plan = draft.verificationApplicationPlan(for: result)
            
            apiKeyFormState = apiKeyFormState.applyingVerificationPlan(plan)
            if plan.shouldMarkKeyVerified {
                if let keyToSave = plan.keyToSave {
                    settings.setAPIKey(keyToSave, for: provider)
                }
                settings.setKeyVerified(true, for: provider)
            }
        }
    }

}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
