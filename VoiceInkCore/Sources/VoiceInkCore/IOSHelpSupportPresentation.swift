import Foundation

public extension VoiceInkSupportContactPolicy {
    static var commonIssuesURL: URL {
        URL(string: commonIssuesURLString)!
    }
}

extension VoiceInkAnnouncementPresentation: Identifiable {}

public enum VoiceInkIOSHelpSupportPresentation {
    public static let settingsRowTitle = "Help & Support"
    public static let settingsRowSystemImageName = "questionmark.circle"
    public static let navigationTitle = "Help & Support"
    public static let resourcesSectionTitle = "Resources"
    public static let announcementsSectionTitle = "Announcements"
    public static let announcementsToggleTitle = "Show Announcements"
    public static let refreshAnnouncementsButtonTitle = "Check for Announcements"
    public static let noAnnouncementTitle = "No current announcements"
    public static let noAnnouncementDetail = "New product news and important notices will appear here."
    public static let announcementLoadFailureTitle = "Announcements unavailable"
    public static let retryButtonTitle = "Try Again"
    public static let shareCommonIssuesTitle = "Share Common Issues"
    public static let linkFailureTitle = "Couldn’t Open Link"
    public static let linkFailureMessage = "The selected link could not be opened. Please try again."
    public static let emailFailureTitle = "Couldn’t Open Mail"
    public static let emailFailureMessage = "Email support at \(VoiceInkSupportContactPolicy.emailAddress)."

    public static let commonIssuesResource = VoiceInkHelpResourcePresentation(
        id: .commonIssues,
        systemImageName: "wrench.and.screwdriver.fill",
        title: "Common Issues",
        destination: .url(VoiceInkSupportContactPolicy.commonIssuesURL)
    )

    public static var resources: [VoiceInkHelpResourcePresentation] {
        [commonIssuesResource] + VoiceInkHelpResourcesPresentation.resources
    }
}

public enum VoiceInkAnnouncementFetchDiagnostics {
    public static let genericFailureMessage = "Check your connection and try again."

    public static func failureMessage(errorDescription: String) -> String {
        errorDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? genericFailureMessage
            : errorDescription
    }
}
