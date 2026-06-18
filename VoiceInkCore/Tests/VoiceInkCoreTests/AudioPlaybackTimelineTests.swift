import Foundation
import VoiceInkCore

final class AudioPlaybackTimelineTests: XCTestCase {
    func testProgressClampsCurrentTimeAgainstDuration() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: -1, duration: 10), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: 10), 0.5)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 12, duration: 10), 1)
    }

    func testProgressReturnsZeroForInvalidDuration() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: 0), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: -1), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: .infinity, duration: 10), 0)
    }

    func testLocationProgressClampsAgainstWidth() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: -10, width: 100), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 25, width: 100), 0.25)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 125, width: 100), 1)
    }

    func testLocationProgressReturnsZeroForInvalidWidth() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 10, width: 0), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 10, width: -5), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: .infinity, width: 100), 0)
    }

    func testTimeAtLocationUsesClampedLocationProgress() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 25, width: 100, duration: 40), 10)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: -25, width: 100, duration: 40), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 125, width: 100, duration: 40), 40)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 25, width: 100, duration: 0), 0)
    }

    func testSampleProgressUsesStableWaveformPosition() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 0, sampleCount: 200), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 100, sampleCount: 200), 0.5)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 250, sampleCount: 200), 1)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 1, sampleCount: 0), 0)
    }
}
