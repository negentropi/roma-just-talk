import Foundation
import SwiftData

@MainActor
struct VoiceInkModelStores {
    let transcription: ModelContainer
    let dictionary: ModelContainer
    let metrics: ModelContainer
    let metricWriter: Task<SessionMetricRecorder, Never>

    init(transcription: ModelContainer, dictionary: ModelContainer, metrics: ModelContainer) {
        self.transcription = transcription
        self.dictionary = dictionary
        self.metrics = metrics
        metricWriter = Task.detached(priority: .utility) {
            SessionMetricRecorder(modelContainer: metrics)
        }
    }

    static func persistent(
        at directory: URL,
        dictionaryCloudKit: ModelConfiguration.CloudKitDatabase
    ) throws -> VoiceInkModelStores {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcriptionSchema = Schema([Transcription.self])
        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        let metricsSchema = Schema([SessionMetric.self])
        return try VoiceInkModelStores(
            transcription: ModelContainer(for: transcriptionSchema, configurations: ModelConfiguration(
                "default", schema: transcriptionSchema,
                url: directory.appendingPathComponent("default.store"), cloudKitDatabase: .none
            )),
            dictionary: ModelContainer(for: dictionarySchema, configurations: ModelConfiguration(
                "dictionary", schema: dictionarySchema,
                url: directory.appendingPathComponent("dictionary.store"), cloudKitDatabase: dictionaryCloudKit
            )),
            metrics: ModelContainer(for: metricsSchema, configurations: ModelConfiguration(
                "stats", schema: metricsSchema,
                url: directory.appendingPathComponent("stats.store"), cloudKitDatabase: .none
            ))
        )
    }

    static func inMemory() throws -> VoiceInkModelStores {
        let transcriptionSchema = Schema([Transcription.self])
        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        let metricsSchema = Schema([SessionMetric.self])
        return try VoiceInkModelStores(
            transcription: ModelContainer(for: transcriptionSchema, configurations: ModelConfiguration(
                "default", schema: transcriptionSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )),
            dictionary: ModelContainer(for: dictionarySchema, configurations: ModelConfiguration(
                "dictionary", schema: dictionarySchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )),
            metrics: ModelContainer(for: metricsSchema, configurations: ModelConfiguration(
                "stats", schema: metricsSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            ))
        )
    }
}
