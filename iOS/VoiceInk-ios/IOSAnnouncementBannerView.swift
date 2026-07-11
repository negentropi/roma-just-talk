import SwiftUI
import VoiceInkCore

struct IOSAnnouncementBannerView: View {
    @Environment(\.openURL) private var openURL
    let presentation: VoiceInkAnnouncementPresentation
    let onDismiss: () -> Void
    @State private var isShowingLinkFailure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(presentation.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: presentation.closeButtonSystemImageName)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(presentation.dismissButtonTitle)
            }

            if presentation.shouldShowDescription {
                Text(presentation.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack {
                if let url = presentation.learnMoreURL {
                    Button(presentation.learnMoreButtonTitle) {
                        openURL(url) { accepted in
                            if accepted {
                                onDismiss()
                            } else {
                                isShowingLinkFailure = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(presentation.dismissButtonTitle, action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .alert(
            VoiceInkIOSHelpSupportPresentation.linkFailureTitle,
            isPresented: $isShowingLinkFailure
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(VoiceInkIOSHelpSupportPresentation.linkFailureMessage)
        }
    }
}
