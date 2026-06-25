import Foundation

public protocol VoiceInkSessionMetricSource {
    var text: String { get }
    var enhancedText: String? { get }
    var duration: TimeInterval { get }
    var transcriptionDuration: TimeInterval? { get }
    var enhancementDuration: TimeInterval? { get }
}

public struct VoiceInkSessionMetricValues: Equatable, Sendable {
    public let wordCount: Int
    public let audioDuration: TimeInterval
    public let transcriptionDuration: TimeInterval?
    public let speedFactor: Double?
    public let enhancementDuration: TimeInterval?
}

public struct VoiceInkSessionMetricDraft: Equatable, Sendable {
    public let transcriptionId: UUID
    public let timestamp: Date
    public let source: String
    public let wordCount: Int
    public let audioDuration: TimeInterval
    public let transcriptionModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let speedFactor: Double?
    public let powerModeName: String?
    public let aiEnhancementModelName: String?
    public let enhancementDuration: TimeInterval?
}

public enum VoiceInkSessionMetricPolicy {
    public static let recorderSource = "recorder"
    public static let completedTranscriptionStatusRawValue = VoiceInkTranscriptionStatus.completed.rawValue

    public static func values(for source: some VoiceInkSessionMetricSource) -> VoiceInkSessionMetricValues {
        let audioDuration = max(source.duration, 0)
        let transcriptionDuration = positiveDuration(source.transcriptionDuration)
        let enhancementDuration = positiveDuration(source.enhancementDuration)
        let speedFactor = transcriptionDuration.flatMap { duration in
            audioDuration > 0 ? audioDuration / duration : nil
        }

        return VoiceInkSessionMetricValues(
            wordCount: VoiceInkWordCounter.count(in: textForCounting(from: source)),
            audioDuration: audioDuration,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            enhancementDuration: enhancementDuration
        )
    }

    public static func recorderDraft(
        transcriptionId: UUID,
        timestamp: Date,
        source: some VoiceInkSessionMetricSource,
        transcriptionModelName: String?,
        powerModeName: String?,
        aiEnhancementModelName: String?
    ) -> VoiceInkSessionMetricDraft {
        let values = values(for: source)
        return VoiceInkSessionMetricDraft(
            transcriptionId: transcriptionId,
            timestamp: timestamp,
            source: recorderSource,
            wordCount: values.wordCount,
            audioDuration: values.audioDuration,
            transcriptionModelName: transcriptionModelName,
            transcriptionDuration: values.transcriptionDuration,
            speedFactor: values.speedFactor,
            powerModeName: powerModeName,
            aiEnhancementModelName: aiEnhancementModelName,
            enhancementDuration: values.enhancementDuration
        )
    }

    static func textForCounting(from source: some VoiceInkSessionMetricSource) -> String {
        if let enhancedText = source.enhancedText,
           source.enhancementDuration != nil,
           !enhancedText.isEmpty {
            return enhancedText
        }

        return source.text
    }

    private static func positiveDuration(_ duration: TimeInterval?) -> TimeInterval? {
        duration.flatMap { $0 > 0 ? $0 : nil }
    }
}

public enum VoiceInkSessionMetricMigrationPreference {
    public static let completionKey = "HasCompletedStatsMigration"

    public static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completionKey)
    }

    public static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }
}

public enum VoiceInkSessionMetricMigrationDiagnostics {
    public static func completedMessage(insertedCount: Int) -> String {
        "Completed stats migration with \(insertedCount) session metric(s)"
    }

    public static func failedMessage(localizedDescription: String) -> String {
        "Stats migration failed: \(localizedDescription)"
    }
}
