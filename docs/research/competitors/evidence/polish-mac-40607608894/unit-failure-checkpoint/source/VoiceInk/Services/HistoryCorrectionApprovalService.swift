import Foundation
import SwiftData
import VoiceInkCore

/// Explicit History approval; it never observes typing or infers successful editor delivery.
@MainActor
enum HistoryCorrectionApprovalService {
    struct Source: Sendable {
        let transcriptionID: UUID
        let variant: VoiceInkWordReplacementSourceVariant
        let text: String
    }

    struct Preview: Sendable {
        let source: Source
        let range: NSRange
        let record: VoiceInkWordReplacementRecord
        let importPlan: VoiceInkWordReplacementLibraryImportPlan
    }

    enum Outcome {
        case inserted(WordReplacement)
        case alreadyExists(UUID)
    }

    enum ApprovalError: LocalizedError, Equatable {
        case sourceUnavailable
        case sourceChanged
        case variantUnavailable
        case blankPhrase
        case blankReplacement
        case invalidRange

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable: "The source History record is no longer available."
            case .sourceChanged: "The displayed transcript changed. Reopen Save correction to review its current text."
            case .variantUnavailable: "This transcript text variant is no longer available."
            case .blankPhrase: "Choose a nonblank phrase from the captured transcript."
            case .blankReplacement: "Enter a nonblank replacement for the chosen phrase."
            case .invalidRange: "Choose a complete phrase within the captured transcript."
            }
        }
    }

    static func capture(
        transcriptionID: UUID,
        variant: VoiceInkWordReplacementSourceVariant,
        expectedText: String,
        using context: ModelContext
    ) throws -> Source {
        let current = try sourceText(transcriptionID: transcriptionID, variant: variant, using: context)
        guard exact(current, expectedText) else { throw ApprovalError.sourceChanged }
        return Source(transcriptionID: transcriptionID, variant: variant, text: current)
    }

    static func occurrences(of phrase: String, in source: Source) throws -> [NSRange] {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApprovalError.blankPhrase
        }
        let text = source.text as NSString
        var ranges = [NSRange]()
        var offset = 0
        while offset < text.length {
            let range = text.range(
                of: phrase, options: .literal, range: NSRange(location: offset, length: text.length - offset)
            )
            guard range.location != NSNotFound else { break }
            guard let snapshot = WritingTarget.TextSnapshot(value: source.text, range: range),
                  exact(snapshot.selectedText, phrase) else { throw ApprovalError.invalidRange }
            ranges.append(range)
            // Advance one scalar rather than match length so repeated/overlapping phrases stay selectable.
            let unit = text.character(at: range.location)
            offset = range.location + ((0xD800...0xDBFF).contains(unit) ? 2 : 1)
        }
        return ranges
    }

    static func preview(
        source: Source,
        range: NSRange,
        replacementText: String,
        using context: ModelContext
    ) throws -> Preview {
        try validate(source, range: range, using: context)
        guard let snapshot = WritingTarget.TextSnapshot(value: source.text, range: range) else {
            throw ApprovalError.invalidRange
        }
        guard !snapshot.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApprovalError.blankPhrase
        }
        guard !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApprovalError.blankReplacement
        }
        let record = try VoiceInkWordReplacementRecord(
            id: UUID(), originalText: snapshot.selectedText, replacementText: replacementText,
            dateAdded: Date(), isEnabled: true, matchingKind: .literal,
            provenance: .init(sourceTranscriptionID: source.transcriptionID, sourceVariant: source.variant)
        )
        let plan = VoiceInkWordReplacementLibrary(records: [record]).preflightImport(
            existingRecords: try DictionaryService.snapshotWordReplacementRecords(using: context)
        )
        return Preview(source: source, range: range, record: record, importPlan: plan)
    }

    @discardableResult
    static func approve(_ preview: Preview, using context: ModelContext) throws -> Outcome {
        try validate(preview.source, range: preview.range, using: context)
        guard let snapshot = WritingTarget.TextSnapshot(value: preview.source.text, range: preview.range),
              exact(snapshot.selectedText, preview.record.originalText),
              preview.record.matchingKind == .literal,
              preview.record.provenance == .init(
                sourceTranscriptionID: preview.source.transcriptionID, sourceVariant: preview.source.variant
              ) else { throw ApprovalError.sourceChanged }
        // A preview is not mutation authority: recheck the current library immediately before saving.
        let plan = VoiceInkWordReplacementLibrary(records: [preview.record]).preflightImport(
            existingRecords: try DictionaryService.snapshotWordReplacementRecords(using: context)
        )
        guard plan.canApply else { throw DictionaryService.LibraryConflictError(conflicts: plan.conflicts) }
        if let duplicate = plan.duplicates.first { return .alreadyExists(duplicate.existingID) }
        return .inserted(try DictionaryService.insertWordReplacement(preview.record, context: context))
    }

    static func sourceExists(
        for provenance: VoiceInkWordReplacementProvenance,
        using context: ModelContext
    ) throws -> Bool {
        try transcription(id: provenance.sourceTranscriptionID, using: context) != nil
    }

    private static func validate(_ source: Source, range: NSRange, using context: ModelContext) throws {
        let current = try sourceText(transcriptionID: source.transcriptionID, variant: source.variant, using: context)
        guard exact(current, source.text) else { throw ApprovalError.sourceChanged }
        guard range.length > 0,
              WritingTarget.TextSnapshot(value: source.text, range: range) != nil else {
            throw ApprovalError.invalidRange
        }
    }

    private static func sourceText(
        transcriptionID: UUID,
        variant: VoiceInkWordReplacementSourceVariant,
        using context: ModelContext
    ) throws -> String {
        guard let source = try transcription(id: transcriptionID, using: context) else {
            throw ApprovalError.sourceUnavailable
        }
        switch variant {
        case .recognition:
            guard let value = source.recognitionText else { throw ApprovalError.variantUnavailable }
            return value
        case .processed: return source.text
        case .enhanced:
            guard let value = source.enhancedText else { throw ApprovalError.variantUnavailable }
            return value
        }
    }

    private static func transcription(id: UUID, using context: ModelContext) throws -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
    }
}
