import Foundation
import VoiceInkCore

final class AIEnhancementRetryPublicAPITests: XCTestCase {
    func testMovedAIEnhancementRetrySymbolsExposePublicAPI() async throws {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.missingAPIKey),
            .notConfigured
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.localCLIExecutionFailure(
                VoiceInkLocalCLIExecutionError.timeout(seconds: 45.9)
            ),
            .customError("Local CLI command timed out after 45 seconds.")
        )
        XCTAssertEqual(
            VoiceInkOllamaEnhancementFailure.transportFailure(.httpStatus(404)),
            .modelNotFound
        )
        XCTAssertEqual(
            VoiceInkOllamaServiceDiagnostics.modelFetchFailedMessage(errorDescription: "server down"),
            "Error fetching models: server down"
        )

        var retryState = VoiceInkAIEnhancementRetryState(maxAttempts: 2)
        XCTAssertEqual(retryState.recordFailure(.networkError), .retryAfterDelay(1))

        let plan = retryState.recordNonEnhancementError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        )
        var retryDecisions: [VoiceInkAIEnhancementRetryDecision] = []
        var transportFailures: [Bool] = []
        try await plan?.applyRuntimeState { decision, isTransportNetworkFailure in
            retryDecisions.append(decision)
            transportFailures.append(isTransportNetworkFailure)
        }
        XCTAssertEqual(retryDecisions, [.fail(.networkError)])
        XCTAssertEqual(transportFailures, [true])

        XCTAssertEqual(
            VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: 1).delaySinceLastRequest(
                lastRequest: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 100.25)
            ) ?? -1,
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
                for: .retryImmediately,
                failedAttempts: 1,
                maxAttempts: 3
            ),
            "Request timed out, retrying immediately... (Attempt 1/3)"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .timeout,
                attempts: 3,
                retryOnTimeoutEnabled: false
            ),
            "Request timed out, failing immediately (retry disabled)."
        )
    }
}
