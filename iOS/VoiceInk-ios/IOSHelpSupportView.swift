import SwiftUI
import VoiceInkCore

struct IOSHelpSupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var actionFailure: ActionFailure?

    var body: some View {
        List {
            Section(VoiceInkIOSHelpSupportPresentation.resourcesSectionTitle) {
                ForEach(VoiceInkHelpResourcesPresentation.resources) { resource in
                    Button {
                        open(resource.destination)
                    } label: {
                        HStack {
                            Label(resource.title, systemImage: resource.systemImageName)
                            Spacer()
                            Image(systemName: VoiceInkHelpResourcesPresentation.externalLinkSystemImageName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ShareLink(
                    item: VoiceInkSupportContactPolicy.commonIssuesURL,
                    subject: Text(VoiceInkIOSHelpSupportPresentation.shareDocumentationSubject)
                ) {
                    Label(
                        VoiceInkIOSHelpSupportPresentation.shareDocumentationTitle,
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .navigationTitle(VoiceInkIOSHelpSupportPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func open(_ destination: VoiceInkHelpResourceDestination) {
        let url: URL?
        let failure: ActionFailure
        switch destination {
        case .url(let resourceURL):
            url = resourceURL
            failure = .link
        case .supportEmail:
            url = VoiceInkSupportContactPolicy.mailtoURL()
            failure = .email
        }

        guard let url else {
            actionFailure = failure
            return
        }
        openURL(url) { accepted in
            if !accepted {
                actionFailure = failure
            }
        }
    }
}

private enum ActionFailure: String, Identifiable {
    case link
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link:
            VoiceInkIOSHelpSupportPresentation.linkFailureTitle
        case .email:
            VoiceInkIOSHelpSupportPresentation.emailFailureTitle
        }
    }

    var message: String {
        switch self {
        case .link:
            VoiceInkIOSHelpSupportPresentation.linkFailureMessage
        case .email:
            VoiceInkIOSHelpSupportPresentation.emailFailureMessage
        }
    }
}

#Preview {
    NavigationStack {
        IOSHelpSupportView()
    }
}
