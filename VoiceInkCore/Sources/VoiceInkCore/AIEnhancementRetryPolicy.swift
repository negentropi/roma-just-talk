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

    public mutating func recordNonEnhancementError(_ error: Error) -> VoiceInkAIEnhancementNonEnhancementErrorRetryPlan? {
        guard VoiceInkAIEnhancementError.transportNetworkError(for: error) == .networkError else {
            return nil
        }

        return VoiceInkAIEnhancementNonEnhancementErrorRetryPlan(
            decision: recordTransportNetworkFailure(),
            isTransportNetworkFailure: true
        )
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

public struct VoiceInkAIEnhancementNonEnhancementErrorRetryPlan: Equatable, Sendable {
    public let decision: VoiceInkAIEnhancementRetryDecision
    public let isTransportNetworkFailure: Bool

    public init(decision: VoiceInkAIEnhancementRetryDecision, isTransportNetworkFailure: Bool) {
        self.decision = decision
        self.isTransportNetworkFailure = isTransportNetworkFailure
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

public enum VoiceInkAIEnhancementRetryProgressPresentation {
    public static func diagnosticMessage(
        for decision: VoiceInkAIEnhancementRetryDecision,
        failedAttempts: Int,
        maxAttempts: Int
    ) -> String? {
        switch decision {
        case .retryAfterDelay(let delay):
            return "Request failed, retrying in \(delay)s... (Attempt \(failedAttempts)/\(maxAttempts))"
        case .retryImmediately:
            return "Request timed out, retrying immediately... (Attempt \(failedAttempts)/\(maxAttempts))"
        case .fail:
            return nil
        }
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
