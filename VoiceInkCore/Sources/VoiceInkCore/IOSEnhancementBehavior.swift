import Foundation

public struct VoiceInkPostProcessingExecutionConfiguration: Equatable, Sendable {
    public static let maximumAttempts = 3
    public static let `default` = VoiceInkPostProcessingExecutionConfiguration(
        timeoutSeconds: TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds),
        retryOnTimeout: VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    )

    public let timeoutSeconds: TimeInterval
    public let retryOnTimeout: Bool

    public init(timeoutSeconds: TimeInterval, retryOnTimeout: Bool) {
        self.timeoutSeconds = max(timeoutSeconds, 0.01)
        self.retryOnTimeout = retryOnTimeout
    }

    public static func current(in defaults: UserDefaults = .standard) -> Self {
        VoiceInkPostProcessingExecutionConfiguration(
            timeoutSeconds: VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
            retryOnTimeout: VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults)
        )
    }
}

public enum VoiceInkPostProcessingExecutionError: LocalizedError, Equatable, Sendable {
    case timedOut(seconds: TimeInterval, attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds, let attempts):
            return "AI enhancement timed out after \(attempts) attempt\(attempts == 1 ? "" : "s") at \(Int(seconds)) seconds each. The original transcription was kept."
        }
    }
}

public enum VoiceInkPostProcessingExecutionPolicy {
    public static func execute(
        configuration: VoiceInkPostProcessingExecutionConfiguration,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let attemptLimit = configuration.retryOnTimeout
            ? VoiceInkPostProcessingExecutionConfiguration.maximumAttempts
            : 1

        for attempt in 1...attemptLimit {
            do {
                return try await executeOnce(
                    timeoutSeconds: configuration.timeoutSeconds,
                    operation: operation
                )
            } catch VoiceInkPostProcessingExecutionError.timedOut {
                guard attempt < attemptLimit else {
                    throw VoiceInkPostProcessingExecutionError.timedOut(
                        seconds: configuration.timeoutSeconds,
                        attempts: attempt
                    )
                }
            }
        }

        throw VoiceInkPostProcessingExecutionError.timedOut(
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
                throw VoiceInkPostProcessingExecutionError.timedOut(
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

public enum VoiceInkPostProcessingBehaviorPreference {
    public static func saveSkipShortEnhancement(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
    }

    public static func saveShortEnhancementWordThreshold(
        _ threshold: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(max(threshold, 1), forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)
    }

    public static func saveTimeoutSeconds(
        _ seconds: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(max(seconds, 1), forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
    }

    public static func saveRetryOnTimeout(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public enum VoiceInkIOSKeyboardEnhancementContextPreference {
    public static let userDefaultsKey = "iOSUseKeyboardEnhancementContext"
    public static let defaultIsEnabled = true

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }
}
