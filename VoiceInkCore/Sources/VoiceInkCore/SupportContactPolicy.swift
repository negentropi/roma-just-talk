import Foundation

public enum VoiceInkSupportContactPolicy {
    public static let emailAddress = "support@tryvoiceink.com"
    public static let emailSubject = "VoiceInk Support Request"
    public static let commonIssuesURLString = "https://tryvoiceink.com/common-issues"

    public static func emailBody(systemInformation: String) -> String {
        """

        ------------------------
        ✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨
        ▶️ Create a quick screen recording showing the issue!
        ▶️ It helps me understand and fix the problem much faster.

        📝 ISSUE DETAILS:
        - What steps did you take before the issue occurred?
        - What did you expect to happen?
        - What actually happened instead?


        ## 📋 COMMON ISSUES:
        Check out our Common Issues page before sending an email: \(commonIssuesURLString)
        ------------------------

        System Information:
        \(systemInformation)


        """
    }

    public static func mailtoURL(subject: String = emailSubject) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]
        return components.url
    }
}
