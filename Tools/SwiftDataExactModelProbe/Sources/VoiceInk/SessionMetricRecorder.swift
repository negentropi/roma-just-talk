import Foundation
import SwiftData
import VoiceInkCore

@ModelActor
actor SessionMetricRecorder {
    @discardableResult
    func record(_ drafts: [VoiceInkSessionMetricDraft]) throws -> Int {
        modelContext.autosaveEnabled = false
        var insertedIDs = Set<UUID>()
        do {
            for draft in drafts {
                guard !insertedIDs.contains(draft.transcriptionId) else { continue }
                let transcriptionID = draft.transcriptionId
                let descriptor = FetchDescriptor<SessionMetric>(
                    predicate: #Predicate<SessionMetric> { $0.transcriptionId == transcriptionID }
                )
                guard try modelContext.fetchCount(descriptor) == 0 else { continue }
                modelContext.insert(SessionMetric(draft: draft))
                insertedIDs.insert(transcriptionID)
            }
            if !insertedIDs.isEmpty {
                try modelContext.save()
            }
            return insertedIDs.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
