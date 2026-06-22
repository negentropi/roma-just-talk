import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var apiKeyFormState = VoiceInkProviderAPIKeyFormState()

    var body: some View {
        let presentation = provider.apiKeyFormPresentation
        let isKeyVerified = settings.isKeyVerified(for: provider)
        let controlPresentation = apiKeyFormState.iOSControlPresentation(
            storedRuntimeKey: settings.apiKey(for: provider)
        )

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
                        .disabled(controlPresentation.isSaveButtonDisabled)
                        Spacer()
                        switch controlPresentation.verificationControl {
                        case .progress:
                            ProgressView().progressViewStyle(.circular)
                        case .verifyButton(let isDisabled):
                            Button(action: verifyKey) {
                                Label(
                                    presentation.verifyButtonTitle,
                                    systemImage: presentation.verifyButtonSystemImageName
                                )
                            }
                            .disabled(isDisabled)
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
                                if let verificationFlag = editPlan.verificationFlagToPersist {
                                    settings.setKeyVerified(verificationFlag, for: provider)
                                }
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
                isVerified: settings.isKeyVerified(for: provider)
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
            let startPlan = apiKeyFormState.verificationStartPlan(
                storedRuntimeKey: settings.apiKey(for: provider),
                missingCandidatePolicy: .applyFailurePlan
            )
            apiKeyFormState = startPlan.formState
            guard let keyToVerify = startPlan.candidate else {
                return
            }
            
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)
            let plan = startPlan.draft.verificationApplicationPlan(for: result)
            
            apiKeyFormState = apiKeyFormState.applyingVerificationPlan(plan)
            settings.applyAPIKeyVerificationPlan(plan, for: provider)
        }
    }

}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
