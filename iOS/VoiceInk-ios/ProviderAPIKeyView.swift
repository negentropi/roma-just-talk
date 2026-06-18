import SwiftUI
import VoiceInkCore

struct ProviderAPIKeyView: View {
    let provider: VoiceInkProviderKind
    @StateObject private var settings = AppSettings.shared
    private let apiKeyVerifier = VoiceInkProviderAPIKeyVerifier()
    @State private var tempKey: String = ""
    @State private var isVerifying: Bool = false
    @State private var verifyResult: Bool? = nil
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

    var body: some View {
        Form {
            Section(header: Text("\(provider.displayName) API Key")) {
                if editingKey {
                    SecureField("\(provider.displayName) API Key", text: $tempKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(action: saveKey) {
                            Label("Save", systemImage: "checkmark.circle.fill")
                        }
                        .disabled(!hasEnteredAPIKey)
                        Spacer()
                        if isVerifying {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Button(action: verifyKey) {
                                Label("Verify", systemImage: "checkmark.seal")
                            }
                            .disabled(!canVerifyAPIKey)
                        }
                    }
                } else {
                    HStack {
                        Label("Key verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Change") {
                            editingKey = true
                            verifyResult = nil
                            tempKey = settings.storedAPIKey(for: provider)
                            settings.setKeyVerified(false, for: provider)
                        }
                    }
                    if let existing = VoiceInkSecretPresentation.obfuscatedAPIKey(settings.storedAPIKey(for: provider)) {
                        Text(existing).font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Only show verification result when actively verifying and not already verified
                if let verifyResult = verifyResult, !isKeyVerified {
                    Label(verifyResult ? "Key verified" : "Verification failed", systemImage: verifyResult ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(verifyResult ? .green : .red)
                }
            }
            
            Section(header: Text("Get API Key")) {
                Link(destination: provider.consoleURL) {
                    HStack {
                        Image(systemName: "link")
                        Text("\(provider.displayName) API Console")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tempKey = settings.storedAPIKey(for: provider)
            editingKey = !isKeyVerified
            verifyResult = nil
        }
        .onChange(of: tempKey) { _, _ in
            verifyResult = nil
        }
    }

    private func saveKey() {
        settings.setAPIKey(tempKey, for: provider)
    }

    private func verifyKey() {
        Task {
            isVerifying = true
            let draft = apiKeyDraft
            guard let keyToVerify = draft.verificationCandidate else {
                verifyResult = false
                isVerifying = false
                return
            }
            
            let ok = await apiKeyVerifier.verifyStoredAPIKey(keyToVerify, for: provider)
            
            verifyResult = ok
            isVerifying = false
            if ok {
                if let keyToSave = draft.keyToSaveAfterSuccessfulVerification {
                    settings.setAPIKey(keyToSave, for: provider)
                }
                settings.setKeyVerified(true, for: provider)
                editingKey = false
            }
        }
    }

}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
