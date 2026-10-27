import Testing
import Foundation

public enum VoiceInkLocalCLIExecutionError: Error, LocalizedError, Equatable, Sendable {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }

            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        }
    }
}

public enum VoiceInkAIEnhancementError: Error, Equatable, Sendable {
    case notConfigured
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)

    public static func transportFailure(
        _ failure: VoiceInkAIEnhancementTransportFailure
    ) -> VoiceInkAIEnhancementError {
        switch failure {
        case .missingAPIKey:
            return .notConfigured
        case .httpStatus(let statusCode, let message):
            return httpError(statusCode: statusCode, message: message)
        case .noResultReturned:
            return .enhancementFailed
        case .network:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidRequest(let description):
            guard let description, !description.isEmpty else {
                return .customError("An unknown error occurred.")
            }
            return .customError(description)
        }
    }

    public static func httpError(statusCode: Int, message: String) -> VoiceInkAIEnhancementError {
        if statusCode == 429 {
            return .rateLimitExceeded
        }
        if (500...599).contains(statusCode) {
            return .serverError
        }
        return .customError("HTTP \(statusCode): \(message)")
    }

    public static func transportNetworkError(for error: Error) -> VoiceInkAIEnhancementError? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }

        let retryableNetworkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost
        ]

        return retryableNetworkCodes.contains(nsError.code) ? .networkError : nil
    }

    public static func localCLIExecutionFailure(_ error: Error) -> VoiceInkAIEnhancementError {
        if let localCLIError = error as? VoiceInkLocalCLIExecutionError {
            return .customError(localCLIError.errorDescription ?? "An unknown Local CLI error occurred.")
        }

        return .customError(error.localizedDescription)
    }
}

public enum VoiceInkAIEnhancementTransportFailure: Equatable, Sendable {
    case missingAPIKey
    case httpStatus(statusCode: Int, message: String)
    case noResultReturned
    case network
    case timeout
    case invalidRequest(description: String?)
}

public enum VoiceInkClarityError: Error, Equatable, Sendable {
    case invalidResponse
    case emptyOutput
}

public enum VoiceInkWritingActionError: LocalizedError, Equatable, Sendable {
    case missingTranslationTarget
    case missingSelection
    case selectionTooLong
    case emptyTranscript
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .missingTranslationTarget:
            "Choose a translation target in Writing Actions before recording."
        case .missingSelection:
            "Select editable text before starting this writing action."
        case .selectionTooLong:
            "Select a shorter passage, up to 24,000 characters."
        case .emptyTranscript:
            "No spoken instructions were recognized. Your original text was kept."
        case .emptyOutput:
            "The writing service returned no text. Your original text was kept."
        }
    }
}

public struct VoiceInkAIEnhancementResult: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let modelName: String?
    public let promptName: String?
    public let requestSystemMessage: String?
    public let requestUserMessage: String?

    public init(
        text: String,
        duration: TimeInterval,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) {
        self.text = text
        self.duration = duration
        self.modelName = modelName
        self.promptName = promptName
        self.requestSystemMessage = requestSystemMessage
        self.requestUserMessage = requestUserMessage
    }

    public static func completed(
        text: String,
        startedAt startDate: Date,
        endedAt endDate: Date,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) -> VoiceInkAIEnhancementResult {
        VoiceInkAIEnhancementResult(
            text: text,
            duration: endDate.timeIntervalSince(startDate),
            modelName: modelName,
            promptName: promptName,
            requestSystemMessage: requestSystemMessage,
            requestUserMessage: requestUserMessage
        )
    }
}


@Suite(.serialized)
struct VoiceInkTests {
    @Suite(.serialized)
    struct ClarityProviderTests {
        @Test @MainActor func extractedMacroShapes() async throws {
            let operation: () async throws -> VoiceInkAIEnhancementResult = { throw CancellationError() }
            let item: (String, VoiceInkClarityError) = ("", .invalidResponse)
            await #expect(throws: item.1) { try await operation() }
            await #expect(throws: VoiceInkAIEnhancementError.customError("Local CLI command timed out after 5 seconds.")) { try await operation() }
            await #expect(throws: VoiceInkAIEnhancementError.customError("Local CLI command returned empty output.")) { try await operation() }
            await #expect(throws: VoiceInkWritingActionError.emptyOutput) { try await operation() }
            let url = URL(fileURLWithPath: "/tmp/never-read-by-typecheck")
            #expect(try Data(contentsOf: url).elementsEqual("expected".utf8))
            let output: String? = "literal"
            #expect(output?.utf8.elementsEqual("literal".utf8) == true)
            #expect("e\u{0301}".utf16.elementsEqual("e\u{0301}".utf16))
            let predicate = true
            try #require(predicate)
            try #require(predicate, "The finite Local CLI fixture did not receive its request.")
        }
    }
}
