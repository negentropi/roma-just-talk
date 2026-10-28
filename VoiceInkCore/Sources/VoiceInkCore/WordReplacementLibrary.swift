import Foundation

public enum VoiceInkWordReplacementSourceVariant: String, Codable, Sendable {
    case recognition
    case processed
    case enhanced
}

public enum VoiceInkWordReplacementApprovalOrigin: String, Codable, Sendable {
    case historyManual
}

public struct VoiceInkWordReplacementProvenance: Codable, Equatable, Sendable {
    public let origin: VoiceInkWordReplacementApprovalOrigin
    public let sourceTranscriptionID: UUID
    public let sourceVariant: VoiceInkWordReplacementSourceVariant

    public init(sourceTranscriptionID: UUID, sourceVariant: VoiceInkWordReplacementSourceVariant) {
        origin = .historyManual
        self.sourceTranscriptionID = sourceTranscriptionID
        self.sourceVariant = sourceVariant
    }
}

public enum VoiceInkWordReplacementRecordError: Error, Equatable {
    case blankOriginalText
    case blankReplacementText
    case invalidDate
}

public struct VoiceInkWordReplacementRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let originalText: String
    public let replacementText: String
    public let dateAdded: Date
    public let isEnabled: Bool
    public let matchingKind: VoiceInkWordReplacementMatchingKind
    public let provenance: VoiceInkWordReplacementProvenance?

    public init(
        id: UUID,
        originalText: String,
        replacementText: String,
        dateAdded: Date,
        isEnabled: Bool,
        matchingKind: VoiceInkWordReplacementMatchingKind,
        provenance: VoiceInkWordReplacementProvenance? = nil
    ) throws {
        let hasSource = matchingKind == .literal
            ? !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !VoiceInkDictionaryPolicy.tokens(from: originalText).isEmpty
        guard hasSource else { throw VoiceInkWordReplacementRecordError.blankOriginalText }
        guard !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceInkWordReplacementRecordError.blankReplacementText
        }
        guard dateAdded.timeIntervalSinceReferenceDate.isFinite else {
            throw VoiceInkWordReplacementRecordError.invalidDate
        }
        self.id = id
        self.originalText = originalText
        self.replacementText = replacementText
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.matchingKind = matchingKind
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalText, replacementText, dateAdded, isEnabled, matchingKind, provenance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            originalText: values.decode(String.self, forKey: .originalText),
            replacementText: values.decode(String.self, forKey: .replacementText),
            dateAdded: values.decode(Date.self, forKey: .dateAdded),
            isEnabled: values.decode(Bool.self, forKey: .isEnabled),
            matchingKind: values.decode(VoiceInkWordReplacementMatchingKind.self, forKey: .matchingKind),
            provenance: values.contains(.provenance)
                ? values.decode(VoiceInkWordReplacementProvenance.self, forKey: .provenance) : nil
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && exactText(lhs.originalText, rhs.originalText)
            && exactText(lhs.replacementText, rhs.replacementText) && lhs.dateAdded == rhs.dateAdded
            && lhs.isEnabled == rhs.isEnabled && lhs.matchingKind == rhs.matchingKind
            && lhs.provenance == rhs.provenance
    }

    // String equality folds canonical spellings; persisted identity must retain their actual bytes.
    fileprivate static func exactText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
    }

    fileprivate var sources: [String] {
        matchingKind == .literal ? [originalText] : VoiceInkDictionaryPolicy.tokens(from: originalText)
    }
}

public struct VoiceInkWordReplacementLibraryConflict: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case identity
        case source
    }

    public let incoming: VoiceInkWordReplacementRecord
    public let existing: VoiceInkWordReplacementRecord
    public let reason: Reason
}

public struct VoiceInkWordReplacementLibraryDuplicate: Equatable, Sendable {
    public let incomingID: UUID
    public let existingID: UUID
}

public struct VoiceInkWordReplacementLibraryImportPlan: Equatable, Sendable {
    public let recordsToInsert: [VoiceInkWordReplacementRecord]
    public let duplicates: [VoiceInkWordReplacementLibraryDuplicate]
    public let conflicts: [VoiceInkWordReplacementLibraryConflict]

    public var canApply: Bool { conflicts.isEmpty }
}

public struct VoiceInkWordReplacementLibrary: Codable, Equatable, Sendable {
    public let version: Int
    public let records: [VoiceInkWordReplacementRecord]

    public init(records: [VoiceInkWordReplacementRecord]) {
        version = 1
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: values, debugDescription: "Unsupported word replacement library version."
            )
        }
        self.init(records: try values.decode([VoiceInkWordReplacementRecord].self, forKey: .records))
    }

    public func preflightImport(existingRecords: [VoiceInkWordReplacementRecord]) -> VoiceInkWordReplacementLibraryImportPlan {
        var observed = existingRecords
        var retained = existingRecords
        var retainedIDs = Dictionary(existingRecords.map { ($0.id, $0.id) }, uniquingKeysWith: { first, _ in first })
        var insertions = [VoiceInkWordReplacementRecord]()
        var duplicates = [VoiceInkWordReplacementLibraryDuplicate]()
        var conflicts = [VoiceInkWordReplacementLibraryConflict]()

        for incoming in records {
            defer {
                if !observed.contains(incoming) { observed.append(incoming) }
            }
            let sameIdentity = observed.filter { $0.id == incoming.id }
            if !sameIdentity.isEmpty {
                let changed = sameIdentity.filter { $0 != incoming }
                if !changed.isEmpty {
                    conflicts += changed.map { .init(incoming: incoming, existing: $0, reason: .identity) }
                    continue
                }
                if let retainedID = retainedIDs[incoming.id] {
                    duplicates.append(.init(incomingID: incoming.id, existingID: retainedID))
                    continue
                }
            }

            let overlapping = retained.filter { existing in
                incoming.sources.contains { source in existing.sources.contains { sameSource(source, $0) } }
            }
            guard !overlapping.isEmpty else {
                insertions.append(incoming)
                retained.append(incoming)
                retainedIDs[incoming.id] = incoming.id
                continue
            }

            let conflicting = overlapping.filter { existing in
                incoming.matchingKind != existing.matchingKind
                    || !sameSources(incoming.sources, existing.sources)
                    || !VoiceInkWordReplacementRecord.exactText(incoming.replacementText, existing.replacementText)
            }
            if conflicting.isEmpty, let existing = overlapping.first {
                duplicates.append(.init(incomingID: incoming.id, existingID: existing.id))
                retainedIDs[incoming.id] = existing.id
            } else {
                conflicts += conflicting.map { .init(incoming: incoming, existing: $0, reason: .source) }
            }
        }

        return VoiceInkWordReplacementLibraryImportPlan(
            recordsToInsert: conflicts.isEmpty ? insertions : [], duplicates: duplicates, conflicts: conflicts
        )
    }

    private func sameSource(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }

    private func sameSources(_ lhs: [String], _ rhs: [String]) -> Bool {
        // Legacy passes are sequential: alternative order and multiplicity can change output.
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { sameSource($0, $1) }
    }
}
