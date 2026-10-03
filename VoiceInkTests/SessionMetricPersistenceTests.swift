import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

struct SessionMetricPersistenceTests {
    @Test @MainActor
    func concurrentDuplicateDraftsCommitExactlyOneMetric() async throws {
        let directory = try ModelStoreTestDirectory()
        defer { directory.remove() }
        let stores = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let draft = modelStoreTestDraft()
        let writerTask = stores.metricWriter
        let inserted = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask { try await writerTask.value.record([draft, draft]) }
            }
            var total = 0
            for try await count in group { total += count }
            return total
        }
        #expect(inserted == 1)

        let reopened = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let rows = try reopened.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>())
        #expect(rows.count == 1)
        let metric = try #require(rows.first)
        #expect(metric.transcriptionId == draft.transcriptionId)
        #expect(metric.wordCount == 3)
        #expect(metric.audioDuration == 6)
        #expect(metric.speedFactor == 3)
        #expect(metric.transcriptionModelName == "fixture model")
    }

    @Test @MainActor
    func readOnlyFailureRollsBackAndPartialRetryPreservesCommittedMetric() async throws {
        let directory = try ModelStoreTestDirectory()
        defer { directory.remove() }
        let stores = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let committed = modelStoreTestDraft()
        let pending = modelStoreTestDraft()
        #expect(try await stores.metricWriter.value.record([committed]) == 1)
        let schema = Schema([SessionMetric.self])
        let readOnly = try ModelContainer(for: schema, configurations: ModelConfiguration(
            "stats", schema: schema, url: directory.url.appendingPathComponent("stats.store"),
            allowsSave: false, cloudKitDatabase: .none
        ))
        let context = ModelContext(readOnly)
        context.autosaveEnabled = false
        context.insert(SessionMetric(draft: pending))
        var rejectsSave = false
        do { try context.save() } catch { rejectsSave = true }
        try #require(rejectsSave, "The real read-only store must reject a save before it is used as a failure fixture.")
        context.rollback()

        let failingWriter = await Task.detached { SessionMetricRecorder(modelContainer: readOnly) }.value
        for _ in 0..<2 {
            var rejected = false
            do { _ = try await failingWriter.record([committed, pending]) } catch { rejected = true }
            #expect(rejected)
        }

        let reopened = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        #expect(try await reopened.metricWriter.value.record([committed, pending]) == 1)
        #expect(try await reopened.metricWriter.value.record([committed, pending]) == 0)
        let final = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let rows = try final.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>())
        #expect(Set(rows.map(\.transcriptionId)) == [committed.transcriptionId, pending.transcriptionId])
        #expect(rows.count == 2)
        #expect(rows.reduce(0) { $0 + $1.wordCount } == 6)
    }

    @Test @MainActor
    func capturedMetricPersistsAfterTranscriptAndAudioAreDeleted() async throws {
        let directory = try ModelStoreTestDirectory()
        defer { directory.remove() }
        let stores = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let audio = directory.url.appendingPathComponent("recording.wav")
        try Data([1, 2, 3, 4]).write(to: audio)
        let transcript = Transcription(
            text: "one two three", duration: 6, audioFileURL: audio.path,
            transcriptionDuration: 2, transcriptionStatus: .completed
        )
        let draft = VoiceInkSessionMetricPolicy.recorderDraft(
            transcriptionId: transcript.id, timestamp: transcript.timestamp, source: transcript,
            transcriptionModelName: "fixture model", powerModeName: nil, aiEnhancementModelName: nil
        )
        stores.transcription.mainContext.insert(transcript)
        try stores.transcription.mainContext.save()
        stores.transcription.mainContext.delete(transcript)
        try stores.transcription.mainContext.save()
        try FileManager.default.removeItem(at: audio)
        #expect(try await stores.metricWriter.value.record([draft]) == 1)

        let reopened = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        #expect(try reopened.transcription.mainContext.fetchCount(FetchDescriptor<Transcription>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        let metric = try #require(reopened.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>()).first)
        #expect(metric.transcriptionId == draft.transcriptionId)
        #expect(metric.wordCount == 3)
        #expect(metric.audioDuration == 6)
    }
}
