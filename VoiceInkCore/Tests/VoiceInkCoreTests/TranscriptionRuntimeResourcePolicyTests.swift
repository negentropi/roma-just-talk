import Foundation
import VoiceInkCore

final class TranscriptionRuntimeResourcePolicyTests: XCTestCase {
    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalWhisperModel)
        XCTAssertEqual(plan.modelSelectionResourceAction, .preserveLocalWhisperModel)
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalFluidAudioModel)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }

    func testCloudRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }
}
