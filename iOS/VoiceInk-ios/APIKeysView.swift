import SwiftUI
import VoiceInkCore

struct APIKeysView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        List {
            ForEach(VoiceInkProviderKind.userAPIKeyProviders) { provider in
                NavigationLink(destination: ProviderAPIKeyView(provider: provider)) {
                    let presentation = settings.apiKeyListRowPresentation(for: provider)

                    HStack {
                        Text(presentation.title)
                        Spacer()
                        Image(systemName: presentation.statusSystemImageName)
                            .foregroundStyle(presentation.tone.statusColor)
                    }
                }
            }
        }
        .navigationTitle(VoiceInkModelManagementFilter.cloud.settingsSectionTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { APIKeysView() }
}
