import Foundation
@testable import VoiceInkCore

final class MicrophoneCheckTests: XCTestCase {
    func testAMutedOrVirtualInputIsReportedAsSilent() {
        // BlackHole with nothing playing records exact zeros.
        XCTAssertEqual(VoiceInkMicrophoneCheck.finding(durationSeconds: 3, peakDecibels: -140), .silent)
    }

    func testAQuietRoomIsNotMistakenForAMissingMicrophone() {
        // A real microphone in a quiet room still peaks around -60 dBFS from its noise floor.
        XCTAssertEqual(VoiceInkMicrophoneCheck.finding(durationSeconds: 3, peakDecibels: -60), .noWords)
    }

    func testAnAccidentalTapOfTheShortcutAsksNothing() {
        XCTAssertNil(VoiceInkMicrophoneCheck.finding(durationSeconds: 0.4, peakDecibels: -140))
    }

    func testTheMessageNamesTheMicrophone() {
        XCTAssertTrue(VoiceInkMicrophoneCheck.message(for: .silent, deviceName: "BlackHole 2ch").contains("BlackHole 2ch"))
    }
}
