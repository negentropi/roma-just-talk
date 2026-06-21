import Foundation
@testable import VoiceInkCore

final class AppIdentityTests: XCTestCase {
    func testAppIdentityPreservesSharedVisibleNames() {
        XCTAssertEqual(VoiceInkAppIdentity.bundleIdentifier, "com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.loggingSubsystem, "com.prakashjoshipax.voiceink")
        XCTAssertEqual(VoiceInkAppIdentity.displayName, "roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.compactDisplayName, "roma-just-talk")
        XCTAssertEqual(VoiceInkAppIdentity.sidebarSubtitle, "speak before hotkey")
        XCTAssertEqual(VoiceInkAppIdentity.iCloudContainerIdentifier, "iCloud.com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.iOSAppGroupIdentifier, "group.com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkScheme, "voiceink")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkHost, "record")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkURL.absoluteString, "voiceink://record")
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName,
            "com.prakashjoshipax.VoiceInk.stopRecording"
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            "com.prakashjoshipax.VoiceInk.recordingStateChanged"
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName.rawValue,
            "stopRecordingFromKeyboard"
        )
        XCTAssertEqual(VoiceInkAppIdentity.welcomeTitle, "Welcome to roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.startUsingTitle, "Start Using roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.onboardingWindowTitle, "roma-just-talk Onboarding")
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFailureMessage,
            "roma-just-talk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
        )
    }

    func testMacOSStorageAlertPresentationPreservesStartupCopy() {
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFallbackWarningPresentation,
            VoiceInkMacOSStorageAlertPresentation(
                title: "Storage Warning",
                message: "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions.",
                buttonTitle: "OK"
            )
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFailurePresentation,
            VoiceInkMacOSStorageAlertPresentation(
                title: "Critical Storage Error",
                message: "roma-just-talk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists.",
                buttonTitle: "Quit"
            )
        )
    }

    func testMacOSApplicationSupportDirectoryUsesBundleIdentifier() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        XCTAssertEqual(
            VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: baseDirectory).path,
            "/tmp/Application Support/com.prakashjoshipax.VoiceInk"
        )
    }

    func testBundleScopedErrorDomainUsesBundleIdentifier() {
        XCTAssertEqual(
            VoiceInkAppIdentity.errorDomain(component: "AudioRecorder"),
            "com.prakashjoshipax.VoiceInk.AudioRecorder"
        )
    }

    func testIOSRecordDeepLinkContractRoundTripsThroughSharedCore() throws {
        let url = VoiceInkAppDeepLink.record.url

        XCTAssertEqual(url, VoiceInkAppIdentity.iOSRecordDeepLinkURL)
        XCTAssertEqual(url.scheme, VoiceInkAppIdentity.iOSRecordDeepLinkScheme)
        XCTAssertEqual(url.host, VoiceInkAppIdentity.iOSRecordDeepLinkHost)
        XCTAssertEqual(VoiceInkAppDeepLink(url: url), .record)
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "voiceink://settings"))))
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "roma://record"))))
    }
}
