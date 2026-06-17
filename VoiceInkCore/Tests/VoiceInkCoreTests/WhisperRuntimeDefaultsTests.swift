@testable import VoiceInkCore

final class WhisperRuntimeDefaultsTests: XCTestCase {
    func testThreadCountKeepsExistingBounds() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 1), 1)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 4), 2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 12), 8)
    }

    func testRuntimeConstantsMatchExistingWhisperWrappers() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.transcriptionTemperature, 0.2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadThreshold, 0.50)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs, 250)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs, 100)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs, 30)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap, 0.1)
    }
}
