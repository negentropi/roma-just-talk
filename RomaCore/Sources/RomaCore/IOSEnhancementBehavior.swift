import Foundation

public struct RomaPostProcessingExecutionConfiguration: Equatable, Sendable {
    public static let maximumAttempts = 3
    public static let `default` = RomaPostProcessingExecutionConfiguration(
        timeoutSeconds: TimeInterval(RomaPreferenceDefault.enhancementTimeoutSeconds),
        retryOnTimeout: RomaPreferenceDefault.enhancementRetryOnTimeout
    )

    public let timeoutSeconds: TimeInterval
    public let retryOnTimeout: Bool

    public init(timeoutSeconds: TimeInterval, retryOnTimeout: Bool) {
        self.timeoutSeconds = max(timeoutSeconds, 0.01)
        self.retryOnTimeout = retryOnTimeout
    }

    public static func current(in defaults: UserDefaults = .standard) -> Self {
        RomaPostProcessingExecutionConfiguration(
            timeoutSeconds: RomaAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
            retryOnTimeout: RomaAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults)
        )
    }
}

public enum RomaPostProcessingExecutionError: LocalizedError, Equatable, Sendable {
    case timedOut(seconds: TimeInterval, attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds, let attempts):
            return "AI enhancement timed out after \(attempts) attempt\(attempts == 1 ? "" : "s") at \(Int(seconds)) seconds each. The original transcription was kept."
        }
    }
}

public enum RomaPostProcessingExecutionPolicy {
    public static func execute(
        configuration: RomaPostProcessingExecutionConfiguration,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let attemptLimit = configuration.retryOnTimeout
            ? RomaPostProcessingExecutionConfiguration.maximumAttempts
            : 1

        for attempt in 1...attemptLimit {
            do {
                return try await executeOnce(
                    timeoutSeconds: configuration.timeoutSeconds,
                    operation: operation
                )
            } catch RomaPostProcessingExecutionError.timedOut {
                guard attempt < attemptLimit else {
                    throw RomaPostProcessingExecutionError.timedOut(
                        seconds: configuration.timeoutSeconds,
                        attempts: attempt
                    )
                }
            }
        }

        throw RomaPostProcessingExecutionError.timedOut(
            seconds: configuration.timeoutSeconds,
            attempts: attemptLimit
        )
    }

    private static func executeOnce(
        timeoutSeconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw RomaPostProcessingExecutionError.timedOut(
                    seconds: timeoutSeconds,
                    attempts: 1
                )
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }
}

public enum RomaPostProcessingBehaviorPreference {
    public static func saveSkipShortEnhancement(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.skipShortEnhancement)
    }

    public static func saveShortEnhancementWordThreshold(
        _ threshold: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(max(threshold, 1), forKey: RomaUserDefaultsKey.shortEnhancementWordThreshold)
    }

    public static func saveTimeoutSeconds(
        _ seconds: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(max(seconds, 1), forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)
    }

    public static func saveRetryOnTimeout(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public enum RomaIOSKeyboardEnhancementContextPreference {
    public static let userDefaultsKey = "iOSUseKeyboardEnhancementContext"
    public static let defaultIsEnabled = true

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }
}
