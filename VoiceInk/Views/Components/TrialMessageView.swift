import SwiftUI
import VoiceInkCore

struct TrialMessageView: View {
    let presentation: VoiceInkLicenseTrialBanner
    var onAddLicenseKey: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: presentation.systemImageName)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    onAddLicenseKey?()
                }) {
                    Text(presentation.enterLicenseButtonTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSWorkspace.shared.open(VoiceInkLicenseLinks.purchaseURL)
                }) {
                    Text(presentation.purchaseButtonTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
    }
    
    private var iconColor: Color {
        switch presentation.tone {
        case .warning: return .orange
        case .expired: return .red
        case .info: return .blue
        }
    }
    
    private var backgroundColor: Color {
        switch presentation.tone {
        case .warning: return Color.orange.opacity(0.1)
        case .expired: return Color.red.opacity(0.1)
        case .info: return Color.blue.opacity(0.1)
        }
    }
}
