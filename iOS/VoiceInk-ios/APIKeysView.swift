import SwiftUI
import VoiceInkCore

struct APIKeysView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        List {
            ForEach(settings.providerAccess.apiKeyListRows()) { row in
                NavigationLink(destination: ProviderAPIKeyView(provider: row.provider)) {
                    HStack {
                        Text(row.presentation.title)
                        Spacer()
                        Image(systemName: row.presentation.statusSystemImageName)
                            .foregroundStyle(row.presentation.tone.statusColor)
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
