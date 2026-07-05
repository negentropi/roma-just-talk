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

public enum VoiceInkOllamaEnhancementFailure: Error, Equatable, Sendable {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

    public static func transportFailure(
        _ failure: VoiceInkOllamaTransportFailure
    ) -> VoiceInkOllamaEnhancementFailure {
        switch failure {
        case .invalidURL:
            return .invalidURL
        case .httpStatus(let statusCode):
            return httpFailure(statusCode: statusCode)
        case .network:
            return .serviceUnavailable
        case .invalidResponse, .missingCredential:
            return .invalidResponse
        case .invalidRequest:
            return .invalidRequest
        case .timeout:
            return .timeout
        }
    }

    public static func httpFailure(statusCode: Int) -> VoiceInkOllamaEnhancementFailure {
        if statusCode == 404 {
            return .modelNotFound
        }
        if statusCode == 500 {
            return .serverError
        }
        return .invalidResponse
    }

    public var enhancementError: VoiceInkAIEnhancementError {
        switch self {
        case .timeout:
            return .timeout
        case .invalidURL, .serviceUnavailable, .invalidResponse, .modelNotFound, .serverError, .invalidRequest:
            return .customError(message)
        }
    }

    public var message: String {
        switch self {
        case .invalidURL:
            return "Invalid Ollama server URL"
        case .serviceUnavailable:
            return "Ollama service is not available"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .modelNotFound:
            return "Selected model not found"
        case .serverError:
            return "Ollama server error"
        case .invalidRequest:
            return "System prompt is required"
        case .timeout:
            return "Ollama request timed out"
        }
    }
}

public enum VoiceInkOllamaTransportFailure: Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case network
    case invalidResponse
    case invalidRequest
    case missingCredential
    case timeout
}

public enum VoiceInkOllamaServiceDiagnostics {
    public static let invalidBaseURLMessage = "Invalid Ollama base URL"

    public static func modelFetchFailedMessage(errorDescription: String) -> String {
        "Error fetching models: \(errorDescription)"
    }
}

extension VoiceInkOllamaEnhancementFailure: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension VoiceInkAIEnhancementError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}
