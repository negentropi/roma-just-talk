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
