import Foundation

public extension RomaSupportContactPolicy {
    static var commonIssuesURL: URL {
        URL(string: commonIssuesURLString)!
    }
}

public enum RomaIOSHelpSupportPresentation {
    public static let settingsRowTitle = "Help & Support"
    public static let settingsRowSystemImageName = "questionmark.circle"
    public static let navigationTitle = "Help & Support"
    public static let resourcesSectionTitle = "Resources"
    public static let shareDocumentationTitle = "Share Documentation"
    public static let shareDocumentationSubject = "Roma Just Talk Documentation"
    public static let linkFailureTitle = "Couldn’t Open Link"
    public static let linkFailureMessage = "The selected link could not be opened. Please try again."
    public static let emailFailureTitle = "Couldn’t Open Mail"
    public static let emailFailureMessage = "Email support at \(RomaSupportContactPolicy.emailAddress)."
}
