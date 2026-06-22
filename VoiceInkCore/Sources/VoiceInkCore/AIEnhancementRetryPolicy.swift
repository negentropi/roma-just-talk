import Foundation

public enum VoiceInkAIEnhancementRetryDecision: Equatable, Sendable {
    case retryAfterDelay(TimeInterval)
    case retryImmediately
    case fail(VoiceInkAIEnhancementError)
}

public struct VoiceInkAIEnhancementRetryState: Equatable, Sendable {
    public let maxAttempts: Int
    public let retryOnTimeout: Bool
    public private(set) var failedAttempts: Int
    public private(set) var nextDelay: TimeInterval

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1,
        retryOnTimeout: Bool = true
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryOnTimeout = retryOnTimeout
        self.failedAttempts = 0
        self.nextDelay = initialDelay
    }

    public mutating func recordFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        switch error {
        case .networkError, .serverError, .rateLimitExceeded:
            return recordBackoffFailure(error)
        case .timeout where retryOnTimeout:
            return recordImmediateFailure(error)
        case .timeout, .notConfigured, .enhancementFailed, .customError:
            return .fail(error)
        }
    }

    public mutating func recordTransportNetworkFailure() -> VoiceInkAIEnhancementRetryDecision {
        recordBackoffFailure(.networkError)
    }

    private mutating func recordBackoffFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        let delay = nextDelay
        nextDelay *= 2
        return .retryAfterDelay(delay)
    }

    private mutating func recordImmediateFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        return .retryImmediately
    }
}

public struct VoiceInkAIEnhancementRateLimitPolicy: Equatable, Sendable {
    public let minimumInterval: TimeInterval

    public init(minimumInterval: TimeInterval = 1) {
        self.minimumInterval = max(0, minimumInterval)
    }

    public func delaySinceLastRequest(lastRequest: Date?, now: Date) -> TimeInterval? {
        guard let lastRequest else {
            return nil
        }

        let remainingDelay = minimumInterval - now.timeIntervalSince(lastRequest)
        return remainingDelay > 0 ? remainingDelay : nil
    }
}

public enum VoiceInkAIEnhancementRetryFailurePresentation {
    public static func diagnosticMessage(
        for error: VoiceInkAIEnhancementError,
        attempts: Int,
        retryOnTimeoutEnabled: Bool,
        transportNetworkFailure: Bool = false
    ) -> String? {
        switch error {
        case .timeout where retryOnTimeoutEnabled:
            return "Request timed out after \(attempts) retries."
        case .timeout:
            return "Request timed out, failing immediately (retry disabled)."
        case .networkError where transportNetworkFailure:
            return "Request failed after \(attempts) retries with network error."
        case .networkError, .serverError, .rateLimitExceeded:
            return "Request failed after \(attempts) retries."
        default:
            return nil
        }
    }
}
