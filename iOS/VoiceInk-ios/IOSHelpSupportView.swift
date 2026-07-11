import SwiftUI
import VoiceInkCore

struct IOSHelpSupportView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var announcementsStore: IOSAnnouncementsStore
    @AppStorage(VoiceInkAnnouncementPreference.isEnabledKey)
    private var announcementsEnabled = VoiceInkAnnouncementPreference.defaultIsEnabled
    @State private var actionFailure: ActionFailure?

    var body: some View {
        List {
            Section(VoiceInkIOSHelpSupportPresentation.resourcesSectionTitle) {
                ForEach(VoiceInkIOSHelpSupportPresentation.resources) { resource in
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
                    subject: Text(VoiceInkIOSHelpSupportPresentation.commonIssuesResource.title)
                ) {
                    Label(
                        VoiceInkIOSHelpSupportPresentation.shareCommonIssuesTitle,
                        systemImage: "square.and.arrow.up"
                    )
                }
            }

            Section(VoiceInkIOSHelpSupportPresentation.announcementsSectionTitle) {
                Toggle(
                    VoiceInkIOSHelpSupportPresentation.announcementsToggleTitle,
                    isOn: $announcementsEnabled
                )

                if announcementsEnabled {
                    announcementStatus

                    Button {
                        Task { await announcementsStore.refresh() }
                    } label: {
                        Label(
                            VoiceInkIOSHelpSupportPresentation.refreshAnnouncementsButtonTitle,
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(announcementsStore.isLoading)
                }
            }
        }
        .navigationTitle(VoiceInkIOSHelpSupportPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if announcementsEnabled,
               announcementsStore.currentAnnouncement == nil,
               announcementsStore.errorMessage == nil {
                await announcementsStore.refresh()
            }
        }
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var announcementStatus: some View {
        if announcementsStore.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        } else if let announcement = announcementsStore.currentAnnouncement {
            VStack(alignment: .leading, spacing: 8) {
                Text(announcement.title)
                    .font(.headline)
                if announcement.shouldShowDescription {
                    Text(announcement.descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if let url = announcement.learnMoreURL {
                        Button(announcement.learnMoreButtonTitle) {
                            openURL(url) { accepted in
                                if accepted {
                                    announcementsStore.dismissCurrentAnnouncement()
                                } else {
                                    actionFailure = .link
                                }
                            }
                        }
                    }
                    Button(announcement.dismissButtonTitle, role: .destructive) {
                        announcementsStore.dismissCurrentAnnouncement()
                    }
                }
            }
        } else if let errorMessage = announcementsStore.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    VoiceInkIOSHelpSupportPresentation.announcementLoadFailureTitle,
                    systemImage: "wifi.exclamationmark"
                )
                    .font(.headline)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(VoiceInkIOSHelpSupportPresentation.retryButtonTitle) {
                    Task { await announcementsStore.refresh() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(VoiceInkIOSHelpSupportPresentation.noAnnouncementTitle)
                    .font(.headline)
                Text(VoiceInkIOSHelpSupportPresentation.noAnnouncementDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
        IOSHelpSupportView(announcementsStore: IOSAnnouncementsStore())
    }
}
