import Foundation
@testable import VoiceInkCore

final class AIEnhancementErrorTests: XCTestCase {
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
}
