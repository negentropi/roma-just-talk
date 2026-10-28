import Foundation
import SwiftData

/// Dictionary commits never save or roll back the caller's pending edits.
@MainActor
enum DictionaryPersistence {
    struct RefreshFailure: LocalizedError {
        let underlying: Error

        var errorDescription: String? {
            "Your changes were saved, but the Dictionary list could not refresh. Reopen the Dictionary to review it before making more changes. \(underlying.localizedDescription)"
        }
    }

    struct StoredRevision {
        let id: UUID
        private let dateAdded: Date
        private let isEnabled: Bool
        private let strings: [String?]

        init(_ entry: WordReplacement) {
            id = entry.id
            dateAdded = entry.dateAdded
            isEnabled = entry.isEnabled
            strings = [entry.originalText, entry.replacementText, entry.matchingKindRawValue,
                entry.approvalOriginRawValue, entry.sourceTranscriptionID?.uuidString,
                entry.sourceVariantRawValue, entry.literalOriginalText, entry.literalReplacementText]
        }

        func matches(_ entry: WordReplacement) -> Bool {
            let other = StoredRevision(entry)
            return id == other.id && dateAdded == other.dateAdded && isEnabled == other.isEnabled
                && zip(strings, other.strings).allSatisfy { lhs, rhs in
                    switch (lhs, rhs) {
                    case (.none, .none): true
                    case (.some(let lhs), .some(let rhs)):
                        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
                    default: false
                    }
                }
        }
    }

    static func commit<Value>(
        in container: ModelContainer,
        saveFailure: (Error) -> Error = { $0 },
        _ changes: (ModelContext) throws -> Value
    ) throws -> Value {
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        do {
            // Return values and persistent identifiers only; writer models stay in this scope.
            let result = try changes(writer)
            do {
                if writer.hasChanges { try writer.save() }
            } catch {
                throw saveFailure(error)
            }
            return result
        } catch {
            writer.rollback()
            throw error
        }
    }

    static func refresh(in context: ModelContext, vocabulary: Bool = false) throws -> [WordReplacement] {
        do {
            // Default pending-change merging preserves dirty rows; persisted-only reads do not.
            let rules = try context.fetch(FetchDescriptor<WordReplacement>())
            if vocabulary { _ = try context.fetch(FetchDescriptor<VocabularyWord>()) }
            return rules
        } catch {
            // This read is after a durable commit. Never roll back or repeat that write.
            throw RefreshFailure(underlying: error)
        }
    }
}
