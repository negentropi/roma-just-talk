import Foundation
@testable import VoiceInkCore

final class SupportContactPolicyTests: XCTestCase {
    func testSupportContactPolicyPreservesEmailIdentityAndSubject() {
        XCTAssertEqual(VoiceInkSupportContactPolicy.emailAddress, "support@tryvoiceink.com")
        XCTAssertEqual(VoiceInkSupportContactPolicy.emailSubject, "VoiceInk Support Request")
        XCTAssertEqual(VoiceInkSupportContactPolicy.commonIssuesURLString, "https://tryvoiceink.com/common-issues")
    }

    func testSupportEmailBodyPreservesMacOSSupportCopyAndSystemInformationSlot() {
        let body = VoiceInkSupportContactPolicy.emailBody(systemInformation: "macOS: test\nApp: roma just talk")

        XCTAssertTrue(body.contains("------------------------"))
        XCTAssertTrue(body.contains("✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨"))
        XCTAssertTrue(body.contains("▶️ Create a quick screen recording showing the issue!"))
        XCTAssertTrue(body.contains("📝 ISSUE DETAILS:"))
        XCTAssertTrue(body.contains("## 📋 COMMON ISSUES:"))
        XCTAssertTrue(body.contains("Check out our Common Issues page before sending an email: https://tryvoiceink.com/common-issues"))
        XCTAssertTrue(body.contains("System Information:\nmacOS: test\nApp: roma just talk"))
        XCTAssertTrue(body.hasSuffix("\n\n"))
    }

    func testSupportMailtoURLPreservesRecipientAndEncodesSubject() throws {
        let url = try XCTUnwrap(VoiceInkSupportContactPolicy.mailtoURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, VoiceInkSupportContactPolicy.emailAddress)
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "subject", value: VoiceInkSupportContactPolicy.emailSubject)
        ])
        XCTAssertEqual(url.absoluteString, "mailto:support@tryvoiceink.com?subject=VoiceInk%20Support%20Request")
    }
}
