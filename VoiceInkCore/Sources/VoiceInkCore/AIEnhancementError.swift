import Foundation

public enum VoiceInkAIEnhancementError: Error, Equatable, Sendable {
    case notConfigured
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)

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
}

public enum VoiceInkOllamaEnhancementFailure: Error, Equatable, Sendable {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

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
