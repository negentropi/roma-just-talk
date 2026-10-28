import Foundation
import SwiftData
import VoiceInkCore

enum TranscriptionHistoryQuery {
    /// Rows deleted elsewhere (discarded empty results, auto-cleanup) must not stay selected.
    static func isLive(_ transcription: Transcription) -> Bool {
        !transcription.isDeleted && transcription.modelContext != nil
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
