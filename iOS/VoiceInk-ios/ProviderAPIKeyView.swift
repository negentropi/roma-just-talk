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
                        .disabled(tempKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        if isVerifying {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Button(action: verifyKey) {
                                Label("Verify", systemImage: "checkmark.seal")
                            }
                            .disabled(tempKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && settings.apiKey(for: provider).isEmpty)
                        }
                    }
                } else {
                    HStack {
                        Label("Key verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Change") {
                            editingKey = true
                            verifyResult = nil
                            tempKey = currentAPIKey()
                            settings.setKeyVerified(false, for: provider)
                        }
                    }
                    if let existing = obfuscatedKey() {
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
            tempKey = currentAPIKey()
            editingKey = !isKeyVerified
            verifyResult = nil
        }
        .onChange(of: tempKey) { _, _ in
            verifyResult = nil
        }
    }

    private func currentAPIKey() -> String {
        settings.storedAPIKey(for: provider)
    }

    private func saveKey() {
        settings.setAPIKey(tempKey, for: provider)
    }

    private func verifyKey() {
        Task {
            isVerifying = true
            let entered = tempKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let keyToVerify = entered.isEmpty ? settings.apiKey(for: provider) : entered
            
            let ok = await verifiedAPIKey(keyToVerify)
            
            verifyResult = ok
            isVerifying = false
            if ok {
                if !entered.isEmpty { settings.setAPIKey(entered, for: provider) }
                settings.setKeyVerified(true, for: provider)
                editingKey = false
            }
        }
    }

    private func verifiedAPIKey(_ key: String) async -> Bool {
        await apiKeyVerifier.verifyStoredAPIKey(key, for: provider)
    }

    private func obfuscatedKey() -> String? {
        VoiceInkSecretPresentation.obfuscatedAPIKey(currentAPIKey())
    }
}

#Preview {
    NavigationStack { ProviderAPIKeyView(provider: .groq) }
}
