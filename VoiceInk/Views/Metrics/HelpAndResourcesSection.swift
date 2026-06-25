import SwiftUI
import VoiceInkCore

struct HelpAndResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(VoiceInkHelpResourcesPresentation.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(VoiceInkHelpResourcesPresentation.resources) { resource in
                    resourceLink(resource)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false, cornerRadius: 22))
    }
    
    private func resourceLink(_ resource: VoiceInkHelpResourcePresentation) -> some View {
        Button(action: {
            switch resource.destination {
            case .url(let url):
                NSWorkspace.shared.open(url)
            case .supportEmail:
                EmailSupport.openSupportEmail()
            }
        }) {
            HStack {
                Image(systemName: resource.systemImageName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                
                Text(resource.title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: VoiceInkHelpResourcesPresentation.externalLinkSystemImageName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}
