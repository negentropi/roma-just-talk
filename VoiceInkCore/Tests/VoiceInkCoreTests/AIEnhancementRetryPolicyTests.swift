@testable import VoiceInkCore

final class AIEnhancementRetryPolicyTests: XCTestCase {
    func testBackoffFailuresRetryUntilAttemptLimit() {
        var state = VoiceInkAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordFailure(.networkError), .retryAfterDelay(1))
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(state.nextDelay, 2)

        XCTAssertEqual(state.recordFailure(.serverError), .retryAfterDelay(2))
        XCTAssertEqual(state.failedAttempts, 2)
        XCTAssertEqual(state.nextDelay, 4)

        XCTAssertEqual(state.recordFailure(.rateLimitExceeded), .fail(.rateLimitExceeded))
        XCTAssertEqual(state.failedAttempts, 3)
    }

    func testTimeoutRetriesImmediatelyWhenEnabled() {
        var state = VoiceInkAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordFailure(.timeout), .retryImmediately)
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(state.nextDelay, 1)

        XCTAssertEqual(state.recordFailure(.timeout), .retryImmediately)
        XCTAssertEqual(state.failedAttempts, 2)

        XCTAssertEqual(state.recordFailure(.timeout), .fail(.timeout))
        XCTAssertEqual(state.failedAttempts, 3)
    }

    func testTimeoutFailsImmediatelyWhenDisabled() {
        var state = VoiceInkAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: false
        )

        XCTAssertEqual(state.recordFailure(.timeout), .fail(.timeout))
        XCTAssertEqual(state.failedAttempts, 0)
    }

    func testNonRetryableEnhancementErrorsFailWithoutCountingAttempt() {
        var state = VoiceInkAIEnhancementRetryState()

        XCTAssertEqual(state.recordFailure(.notConfigured), .fail(.notConfigured))
        XCTAssertEqual(state.recordFailure(.enhancementFailed), .fail(.enhancementFailed))
        XCTAssertEqual(state.recordFailure(.customError("bad request")), .fail(.customError("bad request")))
        XCTAssertEqual(state.failedAttempts, 0)
    }

    func testTransportNetworkFailureMapsToSharedNetworkError() {
        var state = VoiceInkAIEnhancementRetryState(
            maxAttempts: 2,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordTransportNetworkFailure(), .retryAfterDelay(1))
        XCTAssertEqual(state.recordTransportNetworkFailure(), .fail(.networkError))
    }
}
