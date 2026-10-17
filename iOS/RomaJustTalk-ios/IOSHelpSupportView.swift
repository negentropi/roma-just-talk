import SwiftUI
import RomaCore

struct IOSHelpSupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var actionFailure: ActionFailure?

    var body: some View {
        List {
            Section(RomaIOSHelpSupportPresentation.resourcesSectionTitle) {
                ForEach(RomaHelpResourcesPresentation.resources) { resource in
                    Button {
                        open(resource.destination)
                    } label: {
                        HStack {
                            Label(resource.title, systemImage: resource.systemImageName)
                            Spacer()
                            Image(systemName: RomaHelpResourcesPresentation.externalLinkSystemImageName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ShareLink(
                    item: RomaSupportContactPolicy.commonIssuesURL,
                    subject: Text(RomaIOSHelpSupportPresentation.shareDocumentationSubject)
                ) {
                    Label(
                        RomaIOSHelpSupportPresentation.shareDocumentationTitle,
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .navigationTitle(RomaIOSHelpSupportPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func open(_ destination: RomaHelpResourceDestination) {
        let url: URL?
        let failure: ActionFailure
        switch destination {
        case .url(let resourceURL):
            url = resourceURL
            failure = .link
        case .supportEmail:
            url = RomaSupportContactPolicy.mailtoURL()
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
            RomaIOSHelpSupportPresentation.linkFailureTitle
        case .email:
            RomaIOSHelpSupportPresentation.emailFailureTitle
        }
    }

    var message: String {
        switch self {
        case .link:
            RomaIOSHelpSupportPresentation.linkFailureMessage
        case .email:
            RomaIOSHelpSupportPresentation.emailFailureMessage
        }
    }
}

#Preview {
    NavigationStack {
        IOSHelpSupportView()
    }
}
