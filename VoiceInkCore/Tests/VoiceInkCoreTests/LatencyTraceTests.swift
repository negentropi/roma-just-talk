import Foundation
@testable import VoiceInkCore

final class LatencyTraceTests: XCTestCase {
    func testOldTokenCannotFinishReplacementTrace() {
        let trace = VoiceInkLatencyTrace.shared
        let oldToken = trace.start(event: "test.old")
        let replacementToken = trace.start(event: "test.replacement")

        XCTAssertEqual(trace.currentToken(), replacementToken)

        trace.finish(event: "test.old.finished_late", token: oldToken)

        XCTAssertEqual(trace.currentToken(), replacementToken)
        trace.finish(event: "test.replacement.finished", token: replacementToken)
        XCTAssertNil(trace.currentToken())
    }

    func testLateEventCannotReactivateFinishedTrace() {
        let trace = VoiceInkLatencyTrace.shared
        let token = trace.start(event: "test.active")
        trace.finish(event: "test.finished", token: token)

        trace.event("test.late_event", token: token)

        XCTAssertNil(trace.currentToken())
    }

    func testExecutorCheckpointReportsEnqueueToResumeDelay() {
        let trace = VoiceInkLatencyTrace.shared
        let token = trace.start(event: "test.executor")
        let enqueuedAt = ProcessInfo.processInfo.systemUptime
        let checkpoint = trace.executorEnqueued(
            "test.work",
            token: token,
            at: enqueuedAt
        )

        XCTAssertEqual(checkpoint?.enqueuedEventName, "test.work.executor_enqueued")
        XCTAssertEqual(checkpoint?.resumedEventName, "test.work.executor_resumed")
        XCTAssertEqual(
            checkpoint.map { trace.executorDelayMilliseconds($0, resumedAt: enqueuedAt + 0.125) },
            125
        )

        trace.executorResumed(checkpoint, at: enqueuedAt + 0.125)
        trace.finish(event: "test.executor.finished", token: token)
    }
}
