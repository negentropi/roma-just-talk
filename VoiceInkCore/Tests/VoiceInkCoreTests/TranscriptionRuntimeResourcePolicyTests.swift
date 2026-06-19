import Foundation
import VoiceInkCore

final class TranscriptionRuntimeResourcePolicyTests: XCTestCase {
    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalWhisperModel)
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalFluidAudioModel)
    }

    func testCloudRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
    }
}
