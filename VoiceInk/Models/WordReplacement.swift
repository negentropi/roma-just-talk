import Foundation
import SwiftData
import VoiceInkCore

@Model
final class WordReplacement {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true
    var matchingKindRawValue: String?
    var approvalOriginRawValue: String?
    var sourceTranscriptionID: UUID?
    var sourceVariantRawValue: String?
    var literalOriginalText: String?
    var literalReplacementText: String?

    init(originalText: String, replacementText: String, dateAdded: Date = Date(), isEnabled: Bool = true) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
    }

    convenience init(record: VoiceInkWordReplacementRecord) {
        self.init(
            originalText: record.matchingKind == .literal ? "" : record.originalText,
            replacementText: record.matchingKind == .literal ? "" : record.replacementText,
            dateAdded: record.dateAdded,
            isEnabled: record.isEnabled
        )
        id = record.id
        matchingKindRawValue = record.matchingKind.rawValue
        approvalOriginRawValue = record.provenance?.origin.rawValue
        sourceTranscriptionID = record.provenance?.sourceTranscriptionID
        sourceVariantRawValue = record.provenance?.sourceVariant.rawValue
        if record.matchingKind == .literal {
            // Older CloudKit clients only read the legacy pair, which must never match literal rules.
            literalOriginalText = record.originalText
            literalReplacementText = record.replacementText
        }
    }

    var matchingKind: VoiceInkWordReplacementMatchingKind? {
        guard let matchingKindRawValue else { return .legacyCommaAlternatives }
        return VoiceInkWordReplacementMatchingKind(rawValue: matchingKindRawValue)
    }

    var record: VoiceInkWordReplacementRecord {
        get throws {
            let kind: VoiceInkWordReplacementMatchingKind
            if let storedKind = matchingKindRawValue {
                guard let decoded = VoiceInkWordReplacementMatchingKind(rawValue: storedKind) else {
                    throw StoredValueError.unsupportedMatchingKind(storedKind)
                }
                kind = decoded
            } else {
                // Stored rows predating matching kinds use comma-separated alternatives.
                kind = .legacyCommaAlternatives
            }

            let source: String
            let replacement: String
            switch kind {
            case .legacyCommaAlternatives:
                guard literalOriginalText == nil, literalReplacementText == nil else {
                    throw StoredValueError.invalidMatchingRepresentation
                }
                source = originalText
                replacement = replacementText
            case .literal:
                guard originalText.isEmpty, replacementText.isEmpty,
                      let literalOriginalText, let literalReplacementText else {
                    throw StoredValueError.invalidMatchingRepresentation
                }
                source = literalOriginalText
                replacement = literalReplacementText
            }

            let provenance: VoiceInkWordReplacementProvenance?
            if approvalOriginRawValue == nil, sourceTranscriptionID == nil, sourceVariantRawValue == nil {
                provenance = nil
            } else {
                guard approvalOriginRawValue == VoiceInkWordReplacementApprovalOrigin.historyManual.rawValue,
                      let sourceTranscriptionID,
                      let storedVariant = sourceVariantRawValue,
                      let variant = VoiceInkWordReplacementSourceVariant(rawValue: storedVariant) else {
                    throw StoredValueError.invalidProvenance
                }
                provenance = .init(sourceTranscriptionID: sourceTranscriptionID, sourceVariant: variant)
            }
            return try .init(
                id: id, originalText: source, replacementText: replacement,
                dateAdded: dateAdded, isEnabled: isEnabled, matchingKind: kind, provenance: provenance
            )
        }
    }

    var voiceInkRule: VoiceInkWordReplacementRule {
        get throws {
            let value = try record
            return .init(
                originalText: value.originalText,
                replacementText: value.replacementText,
                matchingKind: value.matchingKind
            )
        }
    }

    enum StoredValueError: LocalizedError, Equatable {
        case unsupportedMatchingKind(String)
        case invalidMatchingRepresentation
        case invalidProvenance

        var errorDescription: String? {
            switch self {
            case .unsupportedMatchingKind(let value):
                "Unsupported word replacement matching kind: \(value)."
            case .invalidMatchingRepresentation:
                "The word replacement has incomplete or conflicting matching data."
            case .invalidProvenance:
                "The word replacement has incomplete or unsupported approval provenance."
            }
        }
    }
}
