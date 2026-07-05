import Foundation
@testable import VoiceInkCore

final class AIEnhancementRetryPolicyTests: XCTestCase {
    func testErrorDescriptionsPreserveExistingMacOSMessages() {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.notConfigured.errorDescription,
            "AI provider not configured. Please check your API key."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.enhancementFailed.errorDescription,
            "AI enhancement failed to process the text."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.networkError.errorDescription,
            "Network connection failed. Check your internet."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.serverError.errorDescription,
            "The AI provider's server encountered an error. Please try again later."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.rateLimitExceeded.errorDescription,
            "Rate limit exceeded. Please try again later."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.timeout.errorDescription,
            "Enhancement request timed out. Check your connection or increase the timeout duration."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.customError("provider down").errorDescription,
            "provider down"
        )
    }

    func testHTTPErrorMappingPreservesMacOSRetryCategories() {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.httpError(statusCode: 429, message: "too many requests"),
            .rateLimitExceeded
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.httpError(statusCode: 500, message: "bad gateway"),
            .serverError
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.httpError(statusCode: 599, message: "edge timeout"),
            .serverError
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.httpError(statusCode: 400, message: "bad request"),
            .customError("HTTP 400: bad request")
        )
    }

    func testTransportFailureMappingPreservesMacOSLLMKitCategories() {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.missingAPIKey),
            .notConfigured
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.httpStatus(statusCode: 429, message: "slow down")),
            .rateLimitExceeded
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.httpStatus(statusCode: 500, message: "server down")),
            .serverError
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.httpStatus(statusCode: 400, message: "bad input")),
            .customError("HTTP 400: bad input")
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.noResultReturned),
            .enhancementFailed
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.network),
            .networkError
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.timeout),
            .timeout
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.invalidRequest(description: "bad response")),
            .customError("bad response")
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.invalidRequest(description: "")),
            .customError("An unknown error occurred.")
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.invalidRequest(description: nil)),
            .customError("An unknown error occurred.")
        )
    }

    func testTransportNetworkErrorMapsRetryableFoundationErrors() {
        let retryableCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost
        ]

        for code in retryableCodes {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            XCTAssertEqual(
                VoiceInkAIEnhancementError.transportNetworkError(for: error),
                .networkError
            )
        }
    }

    func testTransportNetworkErrorRejectsNonRetryableFoundationErrors() {
        XCTAssertNil(VoiceInkAIEnhancementError.transportNetworkError(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertNil(VoiceInkAIEnhancementError.transportNetworkError(
            for: NSError(domain: "VoiceInk", code: NSURLErrorTimedOut)
        ))
    }

    func testLocalCLIExecutionFailureMapsCoreErrorsAndGenericFallbacks() {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.localCLIExecutionFailure(
                VoiceInkLocalCLIExecutionError.timeout(seconds: 45.9)
            ),
            .customError("Local CLI command timed out after 45 seconds.")
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.localCLIExecutionFailure(
                NSError(
                    domain: "VoiceInkLocalCLI",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "sandbox denied"]
                )
            ),
            .customError("sandbox denied")
        )
    }

    func testOllamaEnhancementFailurePolicyPreservesMacOSMessagesAndRetryShape() {
        let expectedMessages: [(VoiceInkOllamaEnhancementFailure, String)] = [
            (.invalidURL, "Invalid Ollama server URL"),
            (.serviceUnavailable, "Ollama service is not available"),
            (.invalidResponse, "Invalid response from Ollama server"),
            (.modelNotFound, "Selected model not found"),
            (.serverError, "Ollama server error"),
            (.invalidRequest, "System prompt is required"),
            (.timeout, "Ollama request timed out")
        ]

        for (failure, message) in expectedMessages {
            XCTAssertEqual(failure.message, message)
            XCTAssertEqual(failure.errorDescription, message)
        }

        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.httpFailure(statusCode: 404), .modelNotFound)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.httpFailure(statusCode: 500), .serverError)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.httpFailure(statusCode: 599), .invalidResponse)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.timeout.enhancementError, .timeout)
        XCTAssertEqual(
            VoiceInkOllamaEnhancementFailure.serverError.enhancementError,
            .customError("Ollama server error")
        )
    }

    func testOllamaTransportFailuresMapToSharedFailurePolicy() {
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.invalidURL), .invalidURL)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.httpStatus(404)), .modelNotFound)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.httpStatus(500)), .serverError)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.httpStatus(400)), .invalidResponse)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.network), .serviceUnavailable)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.invalidResponse), .invalidResponse)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.invalidRequest), .invalidRequest)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.missingCredential), .invalidResponse)
        XCTAssertEqual(VoiceInkOllamaEnhancementFailure.transportFailure(.timeout), .timeout)
    }

    func testOllamaServiceDiagnosticsPreserveMacOSConsoleCopy() {
        XCTAssertEqual(
            VoiceInkOllamaServiceDiagnostics.invalidBaseURLMessage,
            "Invalid Ollama base URL"
        )
        XCTAssertEqual(
            VoiceInkOllamaServiceDiagnostics.modelFetchFailedMessage(errorDescription: "server down"),
            "Error fetching models: server down"
        )
    }

    func testDefaultRetryStatePreservesMacOSAttemptAndDelayDefaults() {
        var state = VoiceInkAIEnhancementRetryState()

        XCTAssertEqual(state.maxAttempts, 3)
        XCTAssertTrue(state.retryOnTimeout)
        XCTAssertEqual(state.failedAttempts, 0)
        XCTAssertEqual(state.nextDelay, 1)
        XCTAssertEqual(state.recordFailure(.networkError), .retryAfterDelay(1))
        XCTAssertEqual(state.recordFailure(.serverError), .retryAfterDelay(2))
        XCTAssertEqual(state.recordFailure(.rateLimitExceeded), .fail(.rateLimitExceeded))
    }

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

    func testNonEnhancementErrorRetryPlanHandlesOnlyRetryableTransportFailures() {
        var state = VoiceInkAIEnhancementRetryState(
            maxAttempts: 2,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(
            state.recordNonEnhancementError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            ),
            VoiceInkAIEnhancementNonEnhancementErrorRetryPlan(
                decision: .retryAfterDelay(1),
                isTransportNetworkFailure: true
            )
        )
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(
            state.recordNonEnhancementError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            ),
            VoiceInkAIEnhancementNonEnhancementErrorRetryPlan(
                decision: .fail(.networkError),
                isTransportNetworkFailure: true
            )
        )
        XCTAssertEqual(state.failedAttempts, 2)

        var nonRetryableState = VoiceInkAIEnhancementRetryState()
        XCTAssertNil(nonRetryableState.recordNonEnhancementError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertEqual(nonRetryableState.failedAttempts, 0)
    }

    func testNonEnhancementErrorRetryPlanAppliesRuntimeState() async throws {
        let plan = VoiceInkAIEnhancementNonEnhancementErrorRetryPlan(
            decision: .retryAfterDelay(1),
            isTransportNetworkFailure: true
        )

        var decisions: [VoiceInkAIEnhancementRetryDecision] = []
        var transportNetworkFailures: [Bool] = []
        try await plan.applyRuntimeState { decision, transportNetworkFailure in
            decisions.append(decision)
            transportNetworkFailures.append(transportNetworkFailure)
        }

        XCTAssertEqual(decisions, [.retryAfterDelay(1)])
        XCTAssertEqual(transportNetworkFailures, [true])
    }

    func testRateLimitPolicySkipsDelayWithoutLastRequest() {
        let policy = VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: 1)

        XCTAssertNil(policy.delaySinceLastRequest(
            lastRequest: nil,
            now: Date(timeIntervalSince1970: 100)
        ))
    }

    func testRateLimitPolicyReturnsRemainingDelay() {
        let policy = VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: 1)
        let lastRequest = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 100.25)

        XCTAssertEqual(
            policy.delaySinceLastRequest(lastRequest: lastRequest, now: now) ?? -1,
            0.75,
            accuracy: 0.0001
        )
    }

    func testRateLimitPolicySkipsDelayAfterIntervalExpires() {
        let policy = VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: 1)
        let lastRequest = Date(timeIntervalSince1970: 100)

        XCTAssertNil(policy.delaySinceLastRequest(
            lastRequest: lastRequest,
            now: Date(timeIntervalSince1970: 101)
        ))
        XCTAssertNil(VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: -1).delaySinceLastRequest(
            lastRequest: lastRequest,
            now: Date(timeIntervalSince1970: 100)
        ))
    }

    func testRetryProgressPresentationPreservesMacOSLogMessages() {
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
                for: .retryAfterDelay(2),
                failedAttempts: 2,
                maxAttempts: 3
            ),
            "Request failed, retrying in 2.0s... (Attempt 2/3)"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
                for: .retryImmediately,
                failedAttempts: 1,
                maxAttempts: 3
            ),
            "Request timed out, retrying immediately... (Attempt 1/3)"
        )
        XCTAssertNil(
            VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
                for: .fail(.networkError),
                failedAttempts: 3,
                maxAttempts: 3
            )
        )
    }

    func testRetryFailurePresentationPreservesMacOSLogMessages() {
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .timeout,
                attempts: 3,
                retryOnTimeoutEnabled: true
            ),
            "Request timed out after 3 retries."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .timeout,
                attempts: 3,
                retryOnTimeoutEnabled: false
            ),
            "Request timed out, failing immediately (retry disabled)."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .networkError,
                attempts: 3,
                retryOnTimeoutEnabled: true,
                transportNetworkFailure: true
            ),
            "Request failed after 3 retries with network error."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .serverError,
                attempts: 3,
                retryOnTimeoutEnabled: true
            ),
            "Request failed after 3 retries."
        )
        XCTAssertNil(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .notConfigured,
                attempts: 3,
                retryOnTimeoutEnabled: true
            )
        )
    }
}
