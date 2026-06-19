import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var tempKey: String = ""
    @State private var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle
    @State private var editingKey: Bool = true

    private var isKeyVerified: Bool {
        settings.isKeyVerified(for: provider)
    }

    private var apiKeyDraft: VoiceInkProviderAPIKeyDraft {
        VoiceInkProviderAPIKeyDraft(
            enteredKey: tempKey,
            storedRuntimeKey: settings.apiKey(for: provider)
        )
    }

    private var hasEnteredAPIKey: Bool {
        apiKeyDraft.hasEnteredKey
    }

    private var canVerifyAPIKey: Bool {
        apiKeyDraft.canVerify
    }

    private var formPresentation: VoiceInkProviderAPIKeyFormPresentation {
        provider.apiKeyFormPresentation
    }

    var body: some View {
        let presentation = formPresentation

        Form {
            Section(header: Text(presentation.apiKeySectionTitle)) {
                if editingKey {
                    SecureField(presentation.apiKeyPlaceholder, text: $tempKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(action: saveKey) {
                            Label(presentation.saveButtonTitle, systemImage: "checkmark.circle.fill")
                        }
                        .disabled(!hasEnteredAPIKey)
                        Spacer()
                        if verificationProgress.isVerifying {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Button(action: verifyKey) {
                                Label(presentation.verifyButtonTitle, systemImage: "checkmark.seal")
                            }
                            .disabled(!canVerifyAPIKey)
                        }
                    }
                } else {
                    HStack {
                        let feedback = VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
                        Label(feedback.text, systemImage: feedback.systemImageName ?? "checkmark.seal.fill")
                            .foregroundStyle(color(for: feedback.tone))
                        Spacer()
                        Button(presentation.changeButtonTitle) {
                            editingKey = true
                            verificationProgress = .idle
                            tempKey = settings.storedAPIKey(for: provider)
                            settings.setKeyVerified(false, for: provider)
                        }
                    }
                    if let existing = VoiceInkSecretPresentation.obfuscatedAPIKey(settings.storedAPIKey(for: provider)) {
                        Text(existing).font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Only show verification result when actively verifying and not already verified
                if let feedback = verificationProgress.iOSResultFeedback, !isKeyVerified {
                    Label(feedback.text, systemImage: feedback.systemImageName ?? "info.circle")
                        .foregroundStyle(color(for: feedback.tone))
                }
            }
            
            Section(header: Text(presentation.consoleSectionTitle)) {
                Link(destination: provider.consoleURL) {
                    HStack {
                        Image(systemName: "link")
                        Text(presentation.consoleLinkTitle)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tempKey = settings.storedAPIKey(for: provider)
            editingKey = !isKeyVerified
            verificationProgress = .idle
        }
        .onChange(of: tempKey) { _, _ in
            verificationProgress = .idle
        }
    }

    private func saveKey() {
        settings.setAPIKey(tempKey, for: provider)
    }

    private func verifyKey() {
        Task {
            verificationProgress = .verifying
            let draft = apiKeyDraft
            guard let keyToVerify = draft.verificationCandidate else {
                verificationProgress = VoiceInkProviderAPIKeyDraft
                    .missingVerificationCandidatePlan()
                    .progress
                return
            }
            
            let result = await apiKeyVerifier.verifyStoredAPIKeyDetailed(keyToVerify, for: provider)
            let plan = draft.verificationApplicationPlan(for: result)
            
            verificationProgress = plan.progress
            if plan.shouldMarkKeyVerified {
                if let keyToSave = plan.keyToSave {
                    settings.setAPIKey(keyToSave, for: provider)
                }
                settings.setKeyVerified(true, for: provider)
                editingKey = false
            }
        }
    }

    private func color(for tone: VoiceInkProviderAPIKeyVerificationTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
