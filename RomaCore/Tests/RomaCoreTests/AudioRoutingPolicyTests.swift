import Foundation
@testable import RomaCore

final class AudioRoutingPolicyTests: XCTestCase {
    func testPlatformDefaultsKeepPhoneSystemManagedAndMacCustom() {
        XCTAssertEqual(RomaPlatformAudioInputPolicy.defaultMode(for: .iOS), .systemDefault)
        XCTAssertEqual(RomaPlatformAudioInputPolicy.defaultMode(for: .macOS), .custom)
    }

    func testIOSNormalizesUnsupportedPrioritizedModeToSystemManaged() {
        XCTAssertEqual(
            RomaPlatformAudioInputPolicy.normalizedIOSMode(.prioritized),
            .systemDefault
        )
    }

    func testIOSCustomRouteUsesAvailableSelectionAndFallsBackWhenUnavailable() {
        XCTAssertEqual(
            RomaIOSAudioRouteSelectionPolicy.selection(
                inputMode: .custom,
                selectedInputUID: "airpods",
                availableInputUIDs: ["built-in", "airpods"]
            ),
            RomaIOSAudioRouteSelection(
                inputMode: .custom,
                preferredInputUID: "airpods",
                usedSystemFallback: false
            )
        )
        XCTAssertEqual(
            RomaIOSAudioRouteSelectionPolicy.selection(
                inputMode: .custom,
                selectedInputUID: "missing",
                availableInputUIDs: ["built-in"]
            ),
            RomaIOSAudioRouteSelection(
                inputMode: .custom,
                preferredInputUID: nil,
                usedSystemFallback: true
            )
        )
    }
}
