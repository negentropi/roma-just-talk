import Foundation
import SwiftData
import VoiceInkCore

enum TranscriptionHistoryQuery {
    /// Drops rows deleted by any context (discarded results, auto-cleanup) from a selection.
    static func liveSelection(_ selection: Set<Transcription>, in context: ModelContext) -> Set<Transcription> {
        guard !selection.isEmpty,
              let liveIDs = try? Set(context.fetchIdentifiers(FetchDescriptor<Transcription>()))
        else { return selection }
        return selection.filter { liveIDs.contains($0.persistentModelID) }
    }

    static func latestIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func cursorDescriptor(
        after timestamp: Date? = nil,
        searchText: String
    ) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = VoiceInkHistoryPaginationPolicy.defaultPageSize
        return descriptor
    }

    static func selectionDescriptor(searchText: String) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>()

        if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.propertiesToFetch = [\.id]
        return descriptor
    }
}
