import Foundation
@testable import VoiceInkCore

final class AudioRoutingPolicyTests: XCTestCase {
    func testPlatformDefaultsKeepPhoneSystemManagedAndMacCustom() {
        XCTAssertEqual(VoiceInkPlatformAudioInputPolicy.defaultMode(for: .iOS), .systemDefault)
        XCTAssertEqual(VoiceInkPlatformAudioInputPolicy.defaultMode(for: .macOS), .custom)
    }

    func testIOSNormalizesUnsupportedPrioritizedModeToSystemManaged() {
        XCTAssertEqual(
            VoiceInkPlatformAudioInputPolicy.normalizedIOSMode(.prioritized),
            .systemDefault
        )
    }

    func testIOSCustomRouteUsesAvailableSelectionAndFallsBackWhenUnavailable() {
        XCTAssertEqual(
            VoiceInkIOSAudioRouteSelectionPolicy.selection(
                inputMode: .custom,
                selectedInputUID: "airpods",
                availableInputUIDs: ["built-in", "airpods"]
            ),
            VoiceInkIOSAudioRouteSelection(
                inputMode: .custom,
                preferredInputUID: "airpods",
                usedSystemFallback: false
            )
        )
        XCTAssertEqual(
            VoiceInkIOSAudioRouteSelectionPolicy.selection(
                inputMode: .custom,
                selectedInputUID: "missing",
                availableInputUIDs: ["built-in"]
            ),
            VoiceInkIOSAudioRouteSelection(
                inputMode: .custom,
                preferredInputUID: nil,
                usedSystemFallback: true
            )
        )
    }
}
