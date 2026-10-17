import Foundation

public enum RomaCustomVocabularyTerms {
    public static func normalized(_ terms: [String], limit: Int? = nil) -> [String] {
        var seen = Set<String>()
        var unique = [String]()

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            unique.append(trimmed)

            if let limit, unique.count >= limit {
                break
            }
        }

        return unique
    }

    public static func normalized(_ terms: [String], for use: RomaCustomVocabularyUse) -> [String] {
        guard use.acceptsTerms else { return [] }
        return normalized(terms, limit: use.termLimit)
    }
}

public enum RomaCustomVocabularyUse: Equatable, Sendable {
    case batchTranscription(RomaProviderKind)
    case streamingTranscription(RomaProviderKind)
    case postProcessingContext

    fileprivate var acceptsTerms: Bool {
        switch self {
        case .batchTranscription(.soniox),
             .batchTranscription(.speechmatics),
             .batchTranscription(.assemblyAI),
             .streamingTranscription(.deepgram),
             .streamingTranscription(.soniox),
             .streamingTranscription(.speechmatics),
             .streamingTranscription(.assemblyAI),
             .postProcessingContext:
            return true
        case .batchTranscription, .streamingTranscription:
            return false
        }
    }

    var termLimit: Int? {
        switch self {
        case .streamingTranscription(.deepgram):
            return 50
        case .batchTranscription, .streamingTranscription, .postProcessingContext:
            return nil
        }
    }
}

public protocol RomaDictionaryDraftRuntimeSubmission {
    associatedtype Plan
    associatedtype DraftState

    var plan: Plan { get }
    var draftStateAfterSubmit: DraftState { get }
    var alertPresentation: RomaDictionaryAlertPresentation? { get }
}

public extension RomaDictionaryDraftRuntimeSubmission {
    @discardableResult
    func applyRuntimeState(
        applyPlan: (Plan) -> Void,
        setDraftState: (DraftState) -> Void,
        setAlertPresentation: (RomaDictionaryAlertPresentation?) -> Void
    ) -> Self {
        applyPlan(plan)
        return applyRuntimeState(
            setDraftState: setDraftState,
            setAlertPresentation: setAlertPresentation
        )
    }

    @discardableResult
    func applyRuntimeState(
        setDraftState: (DraftState) -> Void,
        setAlertPresentation: (RomaDictionaryAlertPresentation?) -> Void
    ) -> Self {
        setDraftState(draftStateAfterSubmit)
        setAlertPresentation(alertPresentation)
        return self
    }
}

public struct RomaFillerWordSubmissionPlan: Equatable, Sendable {
    public let updatedWords: [String]
    public let draftAfterSubmit: String
    public let alertPresentation: RomaDictionaryAlertPresentation?
    public let didInsert: Bool

    public init(
        updatedWords: [String],
        draftAfterSubmit: String,
        alertPresentation: RomaDictionaryAlertPresentation?,
        didInsert: Bool = false
    ) {
        self.updatedWords = updatedWords
        self.draftAfterSubmit = draftAfterSubmit
        self.alertPresentation = alertPresentation
        self.didInsert = didInsert
    }

    public func updatedWordsIfChanged(from currentWords: [String]) -> [String]? {
        RomaPreferenceList.changedElements(from: currentWords, to: updatedWords)
    }

    public func applyRuntimeState(
        currentWords: [String],
        setWords: ([String]) -> Void
    ) {
        guard let updatedWords = updatedWordsIfChanged(from: currentWords) else { return }
        setWords(updatedWords)
    }
}

public struct RomaFillerWordDraftSubmission: Equatable, Sendable, RomaDictionaryDraftRuntimeSubmission {
    public let plan: RomaFillerWordSubmissionPlan
    public let draftStateAfterSubmit: RomaFillerWordDraftState

    public init(
        plan: RomaFillerWordSubmissionPlan,
        draftStateAfterSubmit: RomaFillerWordDraftState
    ) {
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: RomaDictionaryAlertPresentation? {
        plan.alertPresentation
    }
}

public struct RomaFillerWordDraftState: Equatable, Sendable {
    public var draft: String

    public init(draft: String = "") {
        self.draft = draft
    }

    public var canSubmit: Bool {
        RomaFillerWords.hasDraft(draft)
    }

    public func submitting(existingWords: [String]) -> RomaFillerWordDraftSubmission {
        let plan = RomaFillerWords.submissionPlan(draft, existingWords: existingWords)
        return RomaFillerWordDraftSubmission(
            plan: plan,
            draftStateAfterSubmit: RomaFillerWordDraftState(draft: plan.draftAfterSubmit)
        )
    }
}

public struct RomaFillerWordEditorPresentation: Equatable, Sendable {
    public let shouldShowEditor: Bool
    public let shouldShowWordList: Bool

    public init(
        shouldShowEditor: Bool,
        shouldShowWordList: Bool
    ) {
        self.shouldShowEditor = shouldShowEditor
        self.shouldShowWordList = shouldShowWordList
    }
}

public enum RomaFillerWords {
    public static let duplicateWordMessage = "This filler word is already in the list."

    public static let defaultWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    public static func normalizedWord(_ word: String) -> String? {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    public static func hasDraft(_ word: String) -> Bool {
        normalizedWord(word) != nil
    }

    public static func editorPresentation(
        isEnabled: Bool,
        words: [String]
    ) -> RomaFillerWordEditorPresentation {
        RomaFillerWordEditorPresentation(
            shouldShowEditor: isEnabled,
            shouldShowWordList: isEnabled && !words.isEmpty
        )
    }

    public static func submissionPlan(
        _ draft: String,
        existingWords words: [String]
    ) -> RomaFillerWordSubmissionPlan {
        guard let wordToInsert = normalizedWord(draft) else {
            return RomaFillerWordSubmissionPlan(
                updatedWords: words,
                draftAfterSubmit: draft,
                alertPresentation: nil
            )
        }

        guard !words.contains(where: { $0.lowercased() == wordToInsert }) else {
            return RomaFillerWordSubmissionPlan(
                updatedWords: words,
                draftAfterSubmit: draft,
                alertPresentation: .duplicateFillerWord(message: duplicateWordMessage)
            )
        }

        return RomaFillerWordSubmissionPlan(
            updatedWords: words + [wordToInsert],
            draftAfterSubmit: "",
            alertPresentation: nil,
            didInsert: true
        )
    }

    public static func removing(_ word: String, from words: [String]) -> [String] {
        let removalKey = word.lowercased()
        return words.filter { $0.lowercased() != removalKey }
    }

    public static func removing(at offsets: IndexSet, from words: [String]) -> [String] {
        RomaPreferenceList.removing(at: offsets, from: words)
    }
}

public struct RomaVocabularySubmissionPlan: Equatable, Sendable {
    public let wordsToInsert: [String]
    public let draftAfterSubmit: String
    public let alertPresentation: RomaDictionaryAlertPresentation?

    public var shouldInsert: Bool {
        !wordsToInsert.isEmpty
    }

    public var shouldComplete: Bool {
        alertPresentation == nil && draftAfterSubmit.isEmpty
    }

    public init(
        wordsToInsert: [String],
        draftAfterSubmit: String,
        alertPresentation: RomaDictionaryAlertPresentation?
    ) {
        self.wordsToInsert = wordsToInsert
        self.draftAfterSubmit = draftAfterSubmit
        self.alertPresentation = alertPresentation
    }

    public func applying(to existingWords: [String]) -> [String] {
        guard alertPresentation == nil, shouldInsert else { return existingWords }
        return existingWords + wordsToInsert
    }

    public func updatedWordsIfChanged(from existingWords: [String]) -> [String]? {
        let updatedWords = applying(to: existingWords)
        return RomaPreferenceList.changedElements(from: existingWords, to: updatedWords)
    }

    public func applyRuntimeState(
        currentWords: [String],
        setWords: ([String]) -> Void
    ) {
        guard let updatedWords = updatedWordsIfChanged(from: currentWords) else { return }
        setWords(updatedWords)
    }
}

public struct RomaVocabularyDraftSubmission: Equatable, Sendable, RomaDictionaryDraftRuntimeSubmission {
    public let submittedDraft: String
    public let plan: RomaVocabularySubmissionPlan
    public let draftStateAfterSubmit: RomaVocabularyDraftState

    public init(
        submittedDraft: String,
        plan: RomaVocabularySubmissionPlan,
        draftStateAfterSubmit: RomaVocabularyDraftState
    ) {
        self.submittedDraft = submittedDraft
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: RomaDictionaryAlertPresentation? {
        plan.alertPresentation
    }

    @discardableResult
    public func applyPersistenceRuntimeState(
        insertVocabularyWord: (String) -> String?
    ) -> Self {
        guard plan.shouldInsert else { return self }

        let failureMessages = plan.wordsToInsert.compactMap { word -> String? in
            insertVocabularyWord(word).map {
                RomaDictionaryAlertPresentation.failedToAddVocabularyWord(
                    word,
                    localizedDescription: $0
                )
            }
        }

        guard !failureMessages.isEmpty else { return self }

        let failurePlan = RomaVocabularySubmissionPlan(
            wordsToInsert: plan.wordsToInsert,
            draftAfterSubmit: submittedDraft,
            alertPresentation: RomaDictionaryAlertPresentation.failedToAddVocabularyWords(failureMessages)
        )
        return RomaVocabularyDraftSubmission(
            submittedDraft: submittedDraft,
            plan: failurePlan,
            draftStateAfterSubmit: RomaVocabularyDraftState(draft: failurePlan.draftAfterSubmit)
        )
    }
}

public struct RomaVocabularyDraftState: Equatable, Sendable {
    public var draft: String

    public init(draft: String = "") {
        self.draft = draft
    }

    public var canSubmit: Bool {
        RomaDictionaryPolicy.hasVocabularyDraft(draft)
    }

    public func submitting(existingWords: [String]) -> RomaVocabularyDraftSubmission {
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
            input: draft,
            existingWords: existingWords
        )
        return RomaVocabularyDraftSubmission(
            submittedDraft: draft,
            plan: plan,
            draftStateAfterSubmit: RomaVocabularyDraftState(draft: plan.draftAfterSubmit)
        )
    }
}

public struct RomaWordReplacementRule: Codable, Equatable, Sendable {
    public let originalText: String
    public let replacementText: String

    public init(originalText: String, replacementText: String) {
        self.originalText = originalText
        self.replacementText = replacementText
    }
}

public enum RomaWordReplacementEngine {
    public static func apply(_ rules: [RomaWordReplacementRule], to text: String) -> String {
        guard !rules.isEmpty else {
            return text
        }

        var modifiedText = text

        for rule in orderedRules(rules) {
            apply(rule, to: &modifiedText)
        }

        return modifiedText
    }

    private static func orderedRules(_ rules: [RomaWordReplacementRule]) -> [RomaWordReplacementRule] {
        rules.sorted { $0.originalText.count > $1.originalText.count }
    }

    private static func apply(_ rule: RomaWordReplacementRule, to modifiedText: inout String) {
        let variants = rule.originalText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for original in variants {
            if usesWordBoundaries(for: original) {
                let escaped = NSRegularExpression.escapedPattern(for: original)
                let pattern = "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: rule.replacementText
                    )
                }
            } else {
                modifiedText = modifiedText.replacingOccurrences(
                    of: original,
                    with: rule.replacementText,
                    options: .caseInsensitive
                )
            }
        }
    }

    private static func usesWordBoundaries(for text: String) -> Bool {
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,
            0x30A0...0x30FF,
            0x4E00...0x9FFF,
            0xAC00...0xD7AF,
            0x0E00...0x0E7F,
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts where range.contains(scalar.value) {
                return false
            }
        }

        return true
    }
}

public struct RomaWordReplacementInsertPlan: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String
    public let errorMessage: String?

    public var shouldInsert: Bool {
        errorMessage == nil && !RomaDictionaryPolicy.tokens(from: originalText).isEmpty && !replacementText.isEmpty
    }
}

public struct RomaWordReplacementSubmissionPlan: Equatable, Sendable {
    public let ruleToInsert: RomaWordReplacementRule?
    public let originalDraftAfterSubmit: String
    public let replacementDraftAfterSubmit: String
    public let alertPresentation: RomaDictionaryAlertPresentation?

    public var shouldInsert: Bool {
        ruleToInsert != nil
    }

    public var shouldComplete: Bool {
        alertPresentation == nil
            && ruleToInsert != nil
            && originalDraftAfterSubmit.isEmpty
            && replacementDraftAfterSubmit.isEmpty
    }

    public init(
        ruleToInsert: RomaWordReplacementRule?,
        originalDraftAfterSubmit: String,
        replacementDraftAfterSubmit: String,
        alertPresentation: RomaDictionaryAlertPresentation?
    ) {
        self.ruleToInsert = ruleToInsert
        self.originalDraftAfterSubmit = originalDraftAfterSubmit
        self.replacementDraftAfterSubmit = replacementDraftAfterSubmit
        self.alertPresentation = alertPresentation
    }

    public func applying(to existingRules: [RomaWordReplacementRule]) -> [RomaWordReplacementRule] {
        guard alertPresentation == nil, let ruleToInsert else { return existingRules }
        return existingRules + [ruleToInsert]
    }

    public func updatedRulesIfChanged(
        from existingRules: [RomaWordReplacementRule]
    ) -> [RomaWordReplacementRule]? {
        let updatedRules = applying(to: existingRules)
        return RomaPreferenceList.changedElements(from: existingRules, to: updatedRules)
    }

    public func applyRuntimeState(
        currentRules: [RomaWordReplacementRule],
        setRules: ([RomaWordReplacementRule]) -> Void
    ) {
        guard let updatedRules = updatedRulesIfChanged(from: currentRules) else { return }
        setRules(updatedRules)
    }
}

public struct RomaWordReplacementDraftSubmission: Equatable, Sendable, RomaDictionaryDraftRuntimeSubmission {
    public let submittedOriginal: String
    public let submittedReplacement: String
    public let plan: RomaWordReplacementSubmissionPlan
    public let draftStateAfterSubmit: RomaWordReplacementDraftState

    public init(
        submittedOriginal: String,
        submittedReplacement: String,
        plan: RomaWordReplacementSubmissionPlan,
        draftStateAfterSubmit: RomaWordReplacementDraftState
    ) {
        self.submittedOriginal = submittedOriginal
        self.submittedReplacement = submittedReplacement
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: RomaDictionaryAlertPresentation? {
        plan.alertPresentation
    }

    @discardableResult
    public func applyPersistenceRuntimeState(
        insertWordReplacementRule: (RomaWordReplacementRule) -> String?
    ) -> Self {
        guard let rule = plan.ruleToInsert,
              let localizedDescription = insertWordReplacementRule(rule) else {
            return self
        }

        let failurePlan = RomaWordReplacementSubmissionPlan(
            ruleToInsert: rule,
            originalDraftAfterSubmit: submittedOriginal,
            replacementDraftAfterSubmit: submittedReplacement,
            alertPresentation: .wordReplacement(
                message: RomaDictionaryAlertPresentation.failedToAddWordReplacement(
                    localizedDescription: localizedDescription
                )
            )
        )
        return RomaWordReplacementDraftSubmission(
            submittedOriginal: submittedOriginal,
            submittedReplacement: submittedReplacement,
            plan: failurePlan,
            draftStateAfterSubmit: RomaWordReplacementDraftState(
                original: failurePlan.originalDraftAfterSubmit,
                replacement: failurePlan.replacementDraftAfterSubmit
            )
        )
    }
}

public struct RomaWordReplacementDraftState: Equatable, Sendable {
    public var original: String
    public var replacement: String

    public init(original: String = "", replacement: String = "") {
        self.original = original
        self.replacement = replacement
    }

    public var hasDraft: Bool {
        !original.isEmpty || !replacement.isEmpty
    }

    public var canSubmit: Bool {
        RomaDictionaryPolicy.canSaveWordReplacementDraft(
            original: original,
            replacement: replacement
        )
    }

    public func submitting(existingOriginalTexts: [String]) -> RomaWordReplacementDraftSubmission {
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )
        return RomaWordReplacementDraftSubmission(
            submittedOriginal: original,
            submittedReplacement: replacement,
            plan: plan,
            draftStateAfterSubmit: RomaWordReplacementDraftState(
                original: plan.originalDraftAfterSubmit,
                replacement: plan.replacementDraftAfterSubmit
            )
        )
    }

    public func submitting(existingRules: [RomaWordReplacementRule]) -> RomaWordReplacementDraftSubmission {
        submitting(existingOriginalTexts: existingRules.map(\.originalText))
    }
}

public struct RomaWordReplacementEditSubmission: Equatable, Sendable {
    public let submittedOriginal: String
    public let submittedReplacement: String
    public let plan: RomaWordReplacementInsertPlan
    public let alertPresentation: RomaDictionaryAlertPresentation?

    public init(
        submittedOriginal: String,
        submittedReplacement: String,
        plan: RomaWordReplacementInsertPlan,
        alertPresentation: RomaDictionaryAlertPresentation?
    ) {
        self.submittedOriginal = submittedOriginal
        self.submittedReplacement = submittedReplacement
        self.plan = plan
        self.alertPresentation = alertPresentation
    }

    public var shouldUpdate: Bool {
        alertPresentation == nil && plan.shouldInsert
    }

    public var shouldComplete: Bool {
        shouldUpdate
    }
}

public struct RomaWordReplacementEditState: Equatable, Sendable {
    public var original: String
    public var replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }

    public var canSave: Bool {
        RomaDictionaryPolicy.canSaveWordReplacementDraft(
            original: original,
            replacement: replacement
        )
    }

    public func submitting(existingOriginalTexts: [String]) -> RomaWordReplacementEditSubmission {
        let plan = RomaDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )
        return RomaWordReplacementEditSubmission(
            submittedOriginal: original,
            submittedReplacement: replacement,
            plan: plan,
            alertPresentation: plan.errorMessage.map(RomaDictionaryAlertPresentation.wordReplacement)
        )
    }

    public func submitting(existingRules: [RomaWordReplacementRule]) -> RomaWordReplacementEditSubmission {
        submitting(existingOriginalTexts: existingRules.map(\.originalText))
    }
}

public struct RomaWordReplacementBackupImportPlan: Equatable, Sendable {
    public let rulesToInsert: [RomaWordReplacementRule]
    public let skippedInvalidReplacementCount: Int

    public init(
        rulesToInsert: [RomaWordReplacementRule],
        skippedInvalidReplacementCount: Int
    ) {
        self.rulesToInsert = rulesToInsert
        self.skippedInvalidReplacementCount = skippedInvalidReplacementCount
    }
}

public struct RomaDictionaryBackupImportPlan: Equatable, Sendable {
    private let hasVocabularyBackupRecords: Bool
    private let hasWordReplacementBackupRecords: Bool
    private let vocabularyWordsToInsert: [String]
    private let wordReplacementRulesToInsert: [RomaWordReplacementRule]
    private let skippedInvalidReplacementCount: Int

    private var insertedVocabularyWordCount: Int {
        vocabularyWordsToInsert.count
    }

    private var insertedWordReplacementCount: Int {
        wordReplacementRulesToInsert.count
    }

    private var shouldSave: Bool {
        insertedVocabularyWordCount > 0 || insertedWordReplacementCount > 0
    }

    private var shouldInvalidateWordReplacementCache: Bool {
        insertedWordReplacementCount > 0
    }

    fileprivate init(
        hasVocabularyBackupRecords: Bool,
        hasWordReplacementBackupRecords: Bool,
        vocabularyWordsToInsert: [String],
        wordReplacementRulesToInsert: [RomaWordReplacementRule],
        skippedInvalidReplacementCount: Int
    ) {
        self.hasVocabularyBackupRecords = hasVocabularyBackupRecords
        self.hasWordReplacementBackupRecords = hasWordReplacementBackupRecords
        self.vocabularyWordsToInsert = vocabularyWordsToInsert
        self.wordReplacementRulesToInsert = wordReplacementRulesToInsert
        self.skippedInvalidReplacementCount = skippedInvalidReplacementCount
    }

    public func applyRuntimeState(
        reportNoVocabularyBackupRecords: () -> Void,
        reportNoWordReplacementBackupRecords: () -> Void,
        insertVocabularyWord: (String) -> Void,
        insertWordReplacementRule: (RomaWordReplacementRule) -> Void,
        reportNoDictionaryEntriesImported: () -> Void,
        save: () throws -> Void,
        invalidateWordReplacementCache: () -> Void,
        reportImportedEntryCounts: (Int, Int) -> Void,
        reportSkippedInvalidReplacementCount: (Int) -> Void
    ) throws {
        if !hasVocabularyBackupRecords {
            reportNoVocabularyBackupRecords()
        }
        if !hasWordReplacementBackupRecords {
            reportNoWordReplacementBackupRecords()
        }

        for word in vocabularyWordsToInsert {
            insertVocabularyWord(word)
        }
        for rule in wordReplacementRulesToInsert {
            insertWordReplacementRule(rule)
        }

        guard shouldSave else {
            reportNoDictionaryEntriesImported()
            if skippedInvalidReplacementCount > 0 {
                reportSkippedInvalidReplacementCount(skippedInvalidReplacementCount)
            }
            return
        }

        try save()

        if shouldInvalidateWordReplacementCache {
            invalidateWordReplacementCache()
        }
        reportImportedEntryCounts(insertedVocabularyWordCount, insertedWordReplacementCount)
        if skippedInvalidReplacementCount > 0 {
            reportSkippedInvalidReplacementCount(skippedInvalidReplacementCount)
        }
    }
}

public struct RomaDictionaryBackupExportPlan: Equatable, Sendable {
    private let vocabularyBackupRecords: [RomaVocabularyWordBackup]?
    private let wordReplacementBackupRecords: [String: String]?

    fileprivate init(
        vocabularyBackupRecords: [RomaVocabularyWordBackup]?,
        wordReplacementBackupRecords: [String: String]?
    ) {
        self.vocabularyBackupRecords = vocabularyBackupRecords
        self.wordReplacementBackupRecords = wordReplacementBackupRecords
    }

    public func applyRuntimeState(
        setVocabularyBackupRecords: ([RomaVocabularyWordBackup]?) -> Void,
        setWordReplacementBackupRecords: ([String: String]?) -> Void
    ) {
        setVocabularyBackupRecords(vocabularyBackupRecords)
        setWordReplacementBackupRecords(wordReplacementBackupRecords)
    }
}

public struct RomaVocabularyWordBackup: Codable, Equatable, Sendable {
    public let word: String

    public init(word: String) {
        self.word = word
    }
}

public struct RomaDictionaryAlertPresentation: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String

    public init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String = "OK"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
    }

    public static func duplicateFillerWord(message: String) -> RomaDictionaryAlertPresentation {
        RomaDictionaryAlertPresentation(
            id: "duplicateFillerWord-\(message)",
            title: "Duplicate Word",
            message: message
        )
    }

    public static func vocabulary(message: String) -> RomaDictionaryAlertPresentation {
        RomaDictionaryAlertPresentation(
            id: "vocabulary-\(message)",
            title: "Vocabulary",
            message: message
        )
    }

    public static func wordReplacement(message: String) -> RomaDictionaryAlertPresentation {
        RomaDictionaryAlertPresentation(
            id: "wordReplacement-\(message)",
            title: "Word Replacement",
            message: message
        )
    }

    public static func failedToAddVocabularyWord(
        _ word: String,
        localizedDescription: String
    ) -> String {
        "Failed to add '\(word)': \(localizedDescription)"
    }

    public static func failedToAddVocabularyWords(
        _ failureMessages: [String]
    ) -> RomaDictionaryAlertPresentation {
        vocabulary(message: failureMessages.joined(separator: "; "))
    }

    public static func failedToAddWordReplacement(localizedDescription: String) -> String {
        "Failed to add replacement: \(localizedDescription)"
    }

    public static func failedToSaveWordReplacementChanges(localizedDescription: String) -> String {
        "Failed to save changes: \(localizedDescription)"
    }

    public static func failedToRemoveVocabularyWord(localizedDescription: String) -> String {
        "Failed to remove word: \(localizedDescription)"
    }

    public static func failedToRemoveWordReplacement(localizedDescription: String) -> String {
        "Failed to remove replacement: \(localizedDescription)"
    }
}

public struct RomaDictionarySettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let heroDescription: String?
    public let sectionSelectorTitle: String?
    public let settingsButtonHelp: String?
    public let wordReplacementsSection: RomaDictionarySettingsSectionPresentation
    public let vocabularySection: RomaDictionarySettingsSectionPresentation
    public let vocabularyHelpText: String?
    public let vocabularyPlaceholder: String
    public let addVocabularyButtonHelp: String?
    public let wordReplacementHelpText: String?
    public let originalTextPlaceholder: String
    public let replacementTextPlaceholder: String
    public let wordReplacementArrowSystemImageName: String
    public let addReplacementButtonTitle: String
    public let addReplacementButtonHelp: String?
    public let shortcutsSectionTitle: String?
    public let quickAddShortcutTitle: String?
    public let closeButtonHelp: String?

    public static let iOS = RomaDictionarySettingsPresentation(
        sectionTitle: "Dictionary",
        heroDescription: nil,
        sectionSelectorTitle: nil,
        settingsButtonHelp: nil,
        wordReplacementsSection: RomaDictionarySettingsSectionPresentation(
            title: "Word Replacements",
            description: "",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularySection: RomaDictionarySettingsSectionPresentation(
            title: "Vocabulary",
            description: "",
            systemImageName: "character.book.closed.fill"
        ),
        vocabularyHelpText: nil,
        vocabularyPlaceholder: "Vocabulary term",
        addVocabularyButtonHelp: nil,
        wordReplacementHelpText: nil,
        originalTextPlaceholder: "Original text",
        replacementTextPlaceholder: "Replacement text",
        wordReplacementArrowSystemImageName: "arrow.right",
        addReplacementButtonTitle: "Add Replacement",
        addReplacementButtonHelp: nil,
        shortcutsSectionTitle: nil,
        quickAddShortcutTitle: nil,
        closeButtonHelp: nil
    )

    public static let macOS = RomaDictionarySettingsPresentation(
        sectionTitle: "Dictionary Settings",
        heroDescription: "Enhance Roma Just Talk's transcription accuracy by teaching it your vocabulary",
        sectionSelectorTitle: "Select Section",
        settingsButtonHelp: "Dictionary settings",
        wordReplacementsSection: RomaDictionarySettingsSectionPresentation(
            title: "Word Replacements",
            description: "Automatically replace specific words/phrases with custom formatted text ",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularySection: RomaDictionarySettingsSectionPresentation(
            title: "Vocabulary",
            description: "Add words to help Roma Just Talk recognize them properly",
            systemImageName: "character.book.closed.fill"
        ),
        vocabularyHelpText: "Add words to help Roma Just Talk recognize them properly. (Requires AI enhancement)",
        vocabularyPlaceholder: "Add word to vocabulary",
        addVocabularyButtonHelp: "Add word",
        wordReplacementHelpText: "Define word replacements to automatically replace specific words or phrases",
        originalTextPlaceholder: "Original text (use commas for multiple)",
        replacementTextPlaceholder: "Replacement text",
        wordReplacementArrowSystemImageName: "arrow.right",
        addReplacementButtonTitle: "Add Replacement",
        addReplacementButtonHelp: "Add word replacement",
        shortcutsSectionTitle: "Shortcuts",
        quickAddShortcutTitle: "Quick Add to Dictionary",
        closeButtonHelp: "Close"
    )
}

public struct RomaDictionarySettingsSectionPresentation: Equatable, Sendable {
    public let title: String
    public let description: String
    public let systemImageName: String

    public init(
        title: String,
        description: String,
        systemImageName: String
    ) {
        self.title = title
        self.description = description
        self.systemImageName = systemImageName
    }
}

public enum RomaDictionarySettingsSection: String, CaseIterable, Sendable {
    case wordReplacements
    case vocabulary

    public static let defaultSelection: Self = .wordReplacements

    public func presentation(
        in presentation: RomaDictionarySettingsPresentation
    ) -> RomaDictionarySettingsSectionPresentation {
        switch self {
        case .wordReplacements:
            return presentation.wordReplacementsSection
        case .vocabulary:
            return presentation.vocabularySection
        }
    }
}

public struct RomaDictionaryQuickAddPresentation: Equatable, Sendable {
    public let vocabularyMode: RomaDictionaryQuickAddModePresentation
    public let replacementMode: RomaDictionaryQuickAddModePresentation
    public let vocabularyPlaceholder: String
    public let originalLabel: String
    public let originalPlaceholder: String
    public let replacementLabel: String
    public let replacementPlaceholder: String
    public let submitHintTitle: String
    public let dismissHintTitle: String

    public static let macOS = RomaDictionaryQuickAddPresentation(
        vocabularyMode: RomaDictionaryQuickAddModePresentation(
            title: "Vocabulary",
            systemImageName: "character.book.closed.fill"
        ),
        replacementMode: RomaDictionaryQuickAddModePresentation(
            title: "Word Replacement",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularyPlaceholder: "e.g. Roma Just Talk, Kubernetes",
        originalLabel: "Replace",
        originalPlaceholder: "e.g. my email, my mail",
        replacementLabel: "With",
        replacementPlaceholder: "e.g. name@example.com",
        submitHintTitle: "Add",
        dismissHintTitle: "Dismiss"
    )
}

public struct RomaDictionaryQuickAddModePresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }
}

public struct RomaWordReplacementInfoPresentation: Equatable, Sendable {
    public let title: String
    public let multipleOriginalsHelpText: String
    public let multipleOriginalsExampleText: String
    public let examplesTitle: String
    public let originalLabel: String
    public let replacementLabel: String
    public let examples: [RomaWordReplacementExamplePresentation]

    public static let macOS = RomaWordReplacementInfoPresentation(
        title: "How to use Word Replacements",
        multipleOriginalsHelpText: "Separate multiple originals with commas:",
        multipleOriginalsExampleText: "Roma jus talk, Rome a just talk, Roma just taught",
        examplesTitle: "Examples",
        originalLabel: "Original:",
        replacementLabel: "Replacement:",
        examples: [
            RomaWordReplacementExamplePresentation(
                originalText: "my website link",
                replacementText: "https://roma-just-talk.com"
            ),
            RomaWordReplacementExamplePresentation(
                originalText: "Roma jus talk, Rome a just talk",
                replacementText: "Roma Just Talk"
            )
        ]
    )
}

public struct RomaWordReplacementExamplePresentation: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String

    public init(originalText: String, replacementText: String) {
        self.originalText = originalText
        self.replacementText = replacementText
    }
}

public struct RomaWordReplacementEditPresentation: Equatable, Sendable {
    public let cancelButtonTitle: String
    public let title: String
    public let saveButtonTitle: String
    public let descriptionText: String
    public let originalFieldTitle: String
    public let requiredText: String
    public let originalPlaceholder: String
    public let replacementFieldTitle: String

    public static let macOS = RomaWordReplacementEditPresentation(
        cancelButtonTitle: "Cancel",
        title: "Edit Word Replacement",
        saveButtonTitle: "Save",
        descriptionText: "Update the word or phrase that should be automatically replaced.",
        originalFieldTitle: "Original Text",
        requiredText: "Required",
        originalPlaceholder: "Enter word or phrase to replace (use commas for multiple)",
        replacementFieldTitle: "Replacement Text"
    )

    public static let iOS = macOS
}

public struct RomaVocabularyListPresentation: Equatable, Sendable {
    public let wordsTitlePrefix: String
    public let sortHelpText: String
    public let removeButtonHelp: String

    public static let macOS = RomaVocabularyListPresentation(
        wordsTitlePrefix: "Vocabulary Words",
        sortHelpText: "Sort alphabetically",
        removeButtonHelp: "Remove word"
    )

    public func wordsTitle(count: Int) -> String {
        "\(wordsTitlePrefix) (\(count))"
    }
}

public struct RomaWordReplacementListPresentation: Equatable, Sendable {
    public let originalColumnTitle: String
    public let replacementColumnTitle: String
    public let sortOriginalHelpText: String
    public let sortReplacementHelpText: String
    public let editButtonHelp: String
    public let removeButtonHelp: String

    public static let macOS = RomaWordReplacementListPresentation(
        originalColumnTitle: "Original",
        replacementColumnTitle: "Replacement",
        sortOriginalHelpText: "Sort by original",
        sortReplacementHelpText: "Sort by replacement",
        editButtonHelp: "Edit replacement",
        removeButtonHelp: "Remove replacement"
    )

    public static let iOS = macOS
}

public enum RomaVocabularySortMode: String, CaseIterable, Sendable {
    case wordAscending = "wordAsc"
    case wordDescending = "wordDesc"

    public static let defaultMode: Self = .wordAscending

    public var indicatorSystemImageName: String {
        switch self {
        case .wordAscending:
            return "chevron.up"
        case .wordDescending:
            return "chevron.down"
        }
    }

    public func toggled() -> Self {
        switch self {
        case .wordAscending:
            return .wordDescending
        case .wordDescending:
            return .wordAscending
        }
    }
}

public enum RomaWordReplacementSortColumn: Sendable {
    case original
    case replacement
}

public enum RomaWordReplacementSortMode: String, CaseIterable, Sendable {
    case originalAscending = "originalAsc"
    case originalDescending = "originalDesc"
    case replacementAscending = "replacementAsc"
    case replacementDescending = "replacementDesc"

    public static let defaultMode: Self = .originalAscending

    public var activeColumn: RomaWordReplacementSortColumn {
        switch self {
        case .originalAscending, .originalDescending:
            return .original
        case .replacementAscending, .replacementDescending:
            return .replacement
        }
    }

    public var indicatorSystemImageName: String {
        switch self {
        case .originalAscending, .replacementAscending:
            return "chevron.up"
        case .originalDescending, .replacementDescending:
            return "chevron.down"
        }
    }

    public func toggled(for column: RomaWordReplacementSortColumn) -> Self {
        switch column {
        case .original:
            return self == .originalAscending ? .originalDescending : .originalAscending
        case .replacement:
            return self == .replacementAscending ? .replacementDescending : .replacementAscending
        }
    }
}

public enum RomaDictionaryListSortPreference {
    public static let vocabularySortModeKey = "vocabularySortMode"
    public static let wordReplacementSortModeKey = "wordReplacementSortMode"

    public static func vocabularySortMode(from defaults: UserDefaults = .standard) -> RomaVocabularySortMode {
        guard let rawValue = defaults.string(forKey: vocabularySortModeKey),
              let mode = RomaVocabularySortMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveVocabularySortMode(
        _ mode: RomaVocabularySortMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: vocabularySortModeKey)
    }

    public static func wordReplacementSortMode(from defaults: UserDefaults = .standard) -> RomaWordReplacementSortMode {
        guard let rawValue = defaults.string(forKey: wordReplacementSortModeKey),
              let mode = RomaWordReplacementSortMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveWordReplacementSortMode(
        _ mode: RomaWordReplacementSortMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: wordReplacementSortModeKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: vocabularySortModeKey)
        defaults.removeObject(forKey: wordReplacementSortModeKey)
    }
}

public enum RomaDictionaryListSortPolicy {
    public static func sortedVocabulary<Item>(
        _ items: [Item],
        mode: RomaVocabularySortMode,
        word: (Item) -> String
    ) -> [Item] {
        items.sorted { lhs, rhs in
            let ordering = word(lhs).localizedCaseInsensitiveCompare(word(rhs))
            switch mode {
            case .wordAscending:
                return ordering == .orderedAscending
            case .wordDescending:
                return ordering == .orderedDescending
            }
        }
    }

    public static func removingVocabulary<Item>(
        atSortedOffsets offsets: IndexSet,
        from items: [Item],
        mode: RomaVocabularySortMode,
        word: (Item) -> String
    ) -> [Item] {
        let indexedItems = Array(items.enumerated())
        let sortedItems = sortedVocabulary(indexedItems, mode: mode) { word($0.element) }
        let originalOffsets = Set(offsets.compactMap { offset in
            sortedItems.indices.contains(offset) ? sortedItems[offset].offset : nil
        })

        return indexedItems.compactMap { item in
            originalOffsets.contains(item.offset) ? nil : item.element
        }
    }

    public static func sortedWordReplacements<Item>(
        _ items: [Item],
        mode: RomaWordReplacementSortMode,
        originalText: (Item) -> String,
        replacementText: (Item) -> String
    ) -> [Item] {
        items.sorted { lhs, rhs in
            let ordering: ComparisonResult
            switch mode.activeColumn {
            case .original:
                ordering = originalText(lhs).localizedCaseInsensitiveCompare(originalText(rhs))
            case .replacement:
                ordering = replacementText(lhs).localizedCaseInsensitiveCompare(replacementText(rhs))
            }

            switch mode {
            case .originalAscending, .replacementAscending:
                return ordering == .orderedAscending
            case .originalDescending, .replacementDescending:
                return ordering == .orderedDescending
            }
        }
    }

    public static func removingWordReplacements<Item>(
        atSortedOffsets offsets: IndexSet,
        from items: [Item],
        mode: RomaWordReplacementSortMode,
        originalText: (Item) -> String,
        replacementText: (Item) -> String
    ) -> [Item] {
        let indexedItems = Array(items.enumerated())
        let sortedItems = sortedWordReplacements(
            indexedItems,
            mode: mode,
            originalText: { originalText($0.element) },
            replacementText: { replacementText($0.element) }
        )
        let originalOffsets = Set(offsets.compactMap { offset in
            sortedItems.indices.contains(offset) ? sortedItems[offset].offset : nil
        })

        return indexedItems.compactMap { item in
            originalOffsets.contains(item.offset) ? nil : item.element
        }
    }
}

public struct RomaDictionarySettingsSnapshot: Equatable, Sendable {
    public let fillerWords: [String]
    public let customVocabularyTerms: [String]
    public let wordReplacements: [RomaWordReplacementRule]
    public let vocabularySortMode: RomaVocabularySortMode
    public let wordReplacementSortMode: RomaWordReplacementSortMode

    public init(
        fillerWords: [String],
        customVocabularyTerms: [String],
        wordReplacements: [RomaWordReplacementRule],
        vocabularySortMode: RomaVocabularySortMode,
        wordReplacementSortMode: RomaWordReplacementSortMode
    ) {
        self.fillerWords = fillerWords
        self.customVocabularyTerms = customVocabularyTerms
        self.wordReplacements = wordReplacements
        self.vocabularySortMode = vocabularySortMode
        self.wordReplacementSortMode = wordReplacementSortMode
    }

    public init(
        fillerWords: [String],
        customVocabularyTerms: [String],
        wordReplacements: [RomaWordReplacementRule],
        defaults: UserDefaults = .standard
    ) {
        self.init(
            fillerWords: fillerWords,
            customVocabularyTerms: customVocabularyTerms,
            wordReplacements: wordReplacements,
            vocabularySortMode: RomaDictionaryListSortPreference.vocabularySortMode(from: defaults),
            wordReplacementSortMode: RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults)
        )
    }

    public var sortedCustomVocabularyTerms: [String] {
        RomaDictionaryListSortPolicy.sortedVocabulary(
            customVocabularyTerms,
            mode: vocabularySortMode,
            word: { $0 }
        )
    }

    public var sortedWordReplacements: [RomaWordReplacementRule] {
        RomaDictionaryListSortPolicy.sortedWordReplacements(
            wordReplacements,
            mode: wordReplacementSortMode,
            originalText: { $0.originalText },
            replacementText: { $0.replacementText }
        )
    }

    public func fillerWordSubmission(
        _ draftState: RomaFillerWordDraftState
    ) -> RomaFillerWordDraftSubmission {
        draftState.submitting(existingWords: fillerWords)
    }

    public func customVocabularySubmission(
        _ draftState: RomaVocabularyDraftState
    ) -> RomaVocabularyDraftSubmission {
        draftState.submitting(existingWords: customVocabularyTerms)
    }

    public func wordReplacementSubmission(
        _ draftState: RomaWordReplacementDraftState
    ) -> RomaWordReplacementDraftSubmission {
        draftState.submitting(existingRules: wordReplacements)
    }

    public func wordReplacementEditSubmission(
        _ editState: RomaWordReplacementEditState,
        replacing rule: RomaWordReplacementRule
    ) -> RomaWordReplacementEditSubmission {
        var existingRules = wordReplacements
        if let index = existingRules.firstIndex(of: rule) {
            existingRules.remove(at: index)
        }
        return editState.submitting(existingRules: existingRules)
    }

    public func applyFillerWordSubmission(
        _ plan: RomaFillerWordSubmissionPlan,
        setWords: ([String]) -> Void
    ) {
        plan.applyRuntimeState(currentWords: fillerWords, setWords: setWords)
    }

    public func applyCustomVocabularySubmission(
        _ plan: RomaVocabularySubmissionPlan,
        setWords: ([String]) -> Void
    ) {
        plan.applyRuntimeState(currentWords: customVocabularyTerms, setWords: setWords)
    }

    public func applyWordReplacementSubmission(
        _ plan: RomaWordReplacementSubmissionPlan,
        setRules: ([RomaWordReplacementRule]) -> Void
    ) {
        plan.applyRuntimeState(currentRules: wordReplacements, setRules: setRules)
    }

    public func applyWordReplacementEditSubmission(
        _ submission: RomaWordReplacementEditSubmission,
        replacing rule: RomaWordReplacementRule,
        setRules: ([RomaWordReplacementRule]) -> Void
    ) {
        guard submission.shouldUpdate,
              let index = wordReplacements.firstIndex(of: rule) else {
            return
        }

        let updatedRule = RomaWordReplacementRule(
            originalText: submission.plan.originalText,
            replacementText: submission.plan.replacementText
        )
        guard updatedRule != rule else { return }

        var updatedRules = wordReplacements
        updatedRules[index] = updatedRule
        setRules(updatedRules)
    }

    public func removingFillerWords(at offsets: IndexSet) -> [String] {
        RomaFillerWords.removing(at: offsets, from: fillerWords)
    }

    public func removingCustomVocabularyTerms(
        atSortedOffsets offsets: IndexSet
    ) -> [String] {
        RomaDictionaryListSortPolicy.removingVocabulary(
            atSortedOffsets: offsets,
            from: customVocabularyTerms,
            mode: vocabularySortMode,
            word: { $0 }
        )
    }

    public func removingWordReplacements(
        atSortedOffsets offsets: IndexSet
    ) -> [RomaWordReplacementRule] {
        RomaDictionaryListSortPolicy.removingWordReplacements(
            atSortedOffsets: offsets,
            from: wordReplacements,
            mode: wordReplacementSortMode,
            originalText: { $0.originalText },
            replacementText: { $0.replacementText }
        )
    }
}

public enum RomaDictionaryPolicy {
    public static func hasVocabularyDraft(_ input: String) -> Bool {
        !tokens(from: input).isEmpty
    }

    public static func vocabularySubmissionPlan(
        input: String,
        existingWords: [String]
    ) -> RomaVocabularySubmissionPlan {
        let words = tokens(from: input)
        guard !words.isEmpty else {
            return RomaVocabularySubmissionPlan(
                wordsToInsert: [],
                draftAfterSubmit: input,
                alertPresentation: nil
            )
        }

        let existingKeys = Set(existingWords.map { $0.lowercased() })

        if words.count == 1, let word = words.first, existingKeys.contains(word.lowercased()) {
            return RomaVocabularySubmissionPlan(
                wordsToInsert: [],
                draftAfterSubmit: input,
                alertPresentation: .vocabulary(message: "'\(word)' is already in the vocabulary")
            )
        }

        let wordsToInsert = vocabularyWordsToInsert(words, existingWords: existingWords)

        return RomaVocabularySubmissionPlan(
            wordsToInsert: wordsToInsert,
            draftAfterSubmit: "",
            alertPresentation: nil
        )
    }

    public static func vocabularyWordsToInsert(
        _ words: [String],
        existingWords: [String]
    ) -> [String] {
        var insertedKeys = Set(existingWords.map { $0.lowercased() })
        var wordsToInsert = [String]()

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !insertedKeys.contains(key) else { continue }

            wordsToInsert.append(trimmed)
            insertedKeys.insert(key)
        }

        return wordsToInsert
    }

    public static func vocabularyBackupRecords(from words: [String]) -> [RomaVocabularyWordBackup] {
        words.map { RomaVocabularyWordBackup(word: $0) }
    }

    public static func vocabularyWordsToInsert(
        from backupRecords: [RomaVocabularyWordBackup],
        existingWords: [String]
    ) -> [String] {
        vocabularyWordsToInsert(
            backupRecords.map(\.word),
            existingWords: existingWords
        )
    }

    public static func dictionaryBackupImportPlan(
        vocabularyWords: [RomaVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        existingWords: [String],
        existingOriginalTexts: [String]
    ) -> RomaDictionaryBackupImportPlan {
        let wordReplacementPlan = wordReplacements.map {
            wordReplacementBackupImportPlan(
                from: $0,
                existingOriginalTexts: existingOriginalTexts
            )
        } ?? RomaWordReplacementBackupImportPlan(
            rulesToInsert: [],
            skippedInvalidReplacementCount: 0
        )

        return RomaDictionaryBackupImportPlan(
            hasVocabularyBackupRecords: vocabularyWords != nil,
            hasWordReplacementBackupRecords: wordReplacements != nil,
            vocabularyWordsToInsert: vocabularyWords.map {
                vocabularyWordsToInsert(
                    from: $0,
                    existingWords: existingWords
                )
            } ?? [],
            wordReplacementRulesToInsert: wordReplacementPlan.rulesToInsert,
            skippedInvalidReplacementCount: wordReplacementPlan.skippedInvalidReplacementCount
        )
    }

    public static func dictionaryBackupExportPlan(
        vocabularyWords: [String],
        wordReplacementRules: [RomaWordReplacementRule]
    ) -> RomaDictionaryBackupExportPlan {
        RomaDictionaryBackupExportPlan(
            vocabularyBackupRecords: vocabularyWords.isEmpty ? nil : vocabularyBackupRecords(from: vocabularyWords),
            wordReplacementBackupRecords: wordReplacementRules.isEmpty ? nil : Dictionary(
                wordReplacementRules.map { ($0.originalText, $0.replacementText) },
                uniquingKeysWith: { _, last in last }
            )
        )
    }

    public static func wordReplacementBackupImportPlan(
        from backupReplacements: [String: String],
        existingOriginalTexts: [String]
    ) -> RomaWordReplacementBackupImportPlan {
        var existingOriginalTexts = existingOriginalTexts
        var rulesToInsert = [RomaWordReplacementRule]()
        var skippedInvalidReplacementCount = 0

        for (original, replacement) in backupReplacements {
            let plan = wordReplacementInsertPlan(
                original: original,
                replacement: replacement,
                existingOriginalTexts: existingOriginalTexts
            )

            if plan.errorMessage != nil {
                continue
            }

            guard plan.shouldInsert else {
                skippedInvalidReplacementCount += 1
                continue
            }

            rulesToInsert.append(
                RomaWordReplacementRule(
                    originalText: plan.originalText,
                    replacementText: plan.replacementText
                )
            )
            existingOriginalTexts.append(plan.originalText)
        }

        return RomaWordReplacementBackupImportPlan(
            rulesToInsert: rulesToInsert,
            skippedInvalidReplacementCount: skippedInvalidReplacementCount
        )
    }

    public static func wordReplacementInsertPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> RomaWordReplacementInsertPlan {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTokens = tokens(from: trimmedOriginal)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalTokens.isEmpty, !trimmedReplacement.isEmpty else {
            return RomaWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: nil
            )
        }

        let existingTokens = Set(existingOriginalTexts.flatMap { tokens(from: $0).map { $0.lowercased() } })

        for token in originalTokens where existingTokens.contains(token.lowercased()) {
            return RomaWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: "'\(token)' already exists in word replacements"
            )
        }

        return RomaWordReplacementInsertPlan(
            originalText: trimmedOriginal,
            replacementText: trimmedReplacement,
            errorMessage: nil
        )
    }

    public static func wordReplacementSubmissionPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> RomaWordReplacementSubmissionPlan {
        let plan = wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )

        if let errorMessage = plan.errorMessage {
            return RomaWordReplacementSubmissionPlan(
                ruleToInsert: nil,
                originalDraftAfterSubmit: original,
                replacementDraftAfterSubmit: replacement,
                alertPresentation: .wordReplacement(message: errorMessage)
            )
        }

        guard plan.shouldInsert else {
            return RomaWordReplacementSubmissionPlan(
                ruleToInsert: nil,
                originalDraftAfterSubmit: original,
                replacementDraftAfterSubmit: replacement,
                alertPresentation: nil
            )
        }

        return RomaWordReplacementSubmissionPlan(
            ruleToInsert: RomaWordReplacementRule(
                originalText: plan.originalText,
                replacementText: plan.replacementText
            ),
            originalDraftAfterSubmit: "",
            replacementDraftAfterSubmit: "",
            alertPresentation: nil
        )
    }

    public static func canSaveWordReplacementDraft(
        original: String,
        replacement: String
    ) -> Bool {
        wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: []
        ).shouldInsert
    }

    public static func tokens(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
