import SwiftUI
import VoiceInkCore

struct APIKeysView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        List {
            ForEach(VoiceInkProviderKind.allCases.filter(\.requiresUserAPIKey)) { provider in
                NavigationLink(destination: ProviderAPIKeyView(provider: provider)) {
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        if settings.isKeyVerified(for: provider) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cloud Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { APIKeysView() }
}
