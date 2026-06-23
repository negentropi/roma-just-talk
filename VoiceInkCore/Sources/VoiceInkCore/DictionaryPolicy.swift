import Foundation

public protocol VoiceInkDictionaryDraftRuntimeSubmission {
    associatedtype Plan
    associatedtype DraftState

    var plan: Plan { get }
    var draftStateAfterSubmit: DraftState { get }
    var alertPresentation: VoiceInkDictionaryAlertPresentation? { get }
}

public extension VoiceInkDictionaryDraftRuntimeSubmission {
    @discardableResult
    func applyRuntimeState(
        applyPlan: (Plan) -> Void,
        setDraftState: (DraftState) -> Void,
        setAlertPresentation: (VoiceInkDictionaryAlertPresentation?) -> Void
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
        setAlertPresentation: (VoiceInkDictionaryAlertPresentation?) -> Void
    ) -> Self {
        setDraftState(draftStateAfterSubmit)
        setAlertPresentation(alertPresentation)
        return self
    }
}

public struct VoiceInkVocabularySubmissionPlan: Equatable, Sendable {
    public let wordsToInsert: [String]
    public let draftAfterSubmit: String
    public let alertPresentation: VoiceInkDictionaryAlertPresentation?

    public var shouldInsert: Bool {
        !wordsToInsert.isEmpty
    }

    public var shouldComplete: Bool {
        alertPresentation == nil && draftAfterSubmit.isEmpty
    }

    public init(
        wordsToInsert: [String],
        draftAfterSubmit: String,
        alertPresentation: VoiceInkDictionaryAlertPresentation?
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
        return VoiceInkPreferenceList.changedElements(from: existingWords, to: updatedWords)
    }
}

public struct VoiceInkVocabularyDraftSubmission: Equatable, Sendable, VoiceInkDictionaryDraftRuntimeSubmission {
    public let submittedDraft: String
    public let plan: VoiceInkVocabularySubmissionPlan
    public let draftStateAfterSubmit: VoiceInkVocabularyDraftState

    public init(
        submittedDraft: String,
        plan: VoiceInkVocabularySubmissionPlan,
        draftStateAfterSubmit: VoiceInkVocabularyDraftState
    ) {
        self.submittedDraft = submittedDraft
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: VoiceInkDictionaryAlertPresentation? {
        plan.alertPresentation
    }
}

public struct VoiceInkVocabularyDraftState: Equatable, Sendable {
    public var draft: String

    public init(draft: String = "") {
        self.draft = draft
    }

    public var canSubmit: Bool {
        VoiceInkDictionaryPolicy.hasVocabularyDraft(draft)
    }

    public func submitting(existingWords: [String]) -> VoiceInkVocabularyDraftSubmission {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: draft,
            existingWords: existingWords
        )
        return VoiceInkVocabularyDraftSubmission(
            submittedDraft: draft,
            plan: plan,
            draftStateAfterSubmit: VoiceInkVocabularyDraftState(draft: plan.draftAfterSubmit)
        )
    }
}

public struct VoiceInkWordReplacementInsertPlan: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String
    public let errorMessage: String?

    public var shouldInsert: Bool {
        errorMessage == nil && !VoiceInkDictionaryPolicy.tokens(from: originalText).isEmpty && !replacementText.isEmpty
    }
}

public struct VoiceInkWordReplacementSubmissionPlan: Equatable, Sendable {
    public let ruleToInsert: VoiceInkWordReplacementRule?
    public let originalDraftAfterSubmit: String
    public let replacementDraftAfterSubmit: String
    public let alertPresentation: VoiceInkDictionaryAlertPresentation?

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
        ruleToInsert: VoiceInkWordReplacementRule?,
        originalDraftAfterSubmit: String,
        replacementDraftAfterSubmit: String,
        alertPresentation: VoiceInkDictionaryAlertPresentation?
    ) {
        self.ruleToInsert = ruleToInsert
        self.originalDraftAfterSubmit = originalDraftAfterSubmit
        self.replacementDraftAfterSubmit = replacementDraftAfterSubmit
        self.alertPresentation = alertPresentation
    }

    public func applying(to existingRules: [VoiceInkWordReplacementRule]) -> [VoiceInkWordReplacementRule] {
        guard alertPresentation == nil, let ruleToInsert else { return existingRules }
        return existingRules + [ruleToInsert]
    }

    public func updatedRulesIfChanged(
        from existingRules: [VoiceInkWordReplacementRule]
    ) -> [VoiceInkWordReplacementRule]? {
        let updatedRules = applying(to: existingRules)
        return VoiceInkPreferenceList.changedElements(from: existingRules, to: updatedRules)
    }
}

public struct VoiceInkWordReplacementDraftSubmission: Equatable, Sendable, VoiceInkDictionaryDraftRuntimeSubmission {
    public let submittedOriginal: String
    public let submittedReplacement: String
    public let plan: VoiceInkWordReplacementSubmissionPlan
    public let draftStateAfterSubmit: VoiceInkWordReplacementDraftState

    public init(
        submittedOriginal: String,
        submittedReplacement: String,
        plan: VoiceInkWordReplacementSubmissionPlan,
        draftStateAfterSubmit: VoiceInkWordReplacementDraftState
    ) {
        self.submittedOriginal = submittedOriginal
        self.submittedReplacement = submittedReplacement
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: VoiceInkDictionaryAlertPresentation? {
        plan.alertPresentation
    }
}

public struct VoiceInkWordReplacementDraftState: Equatable, Sendable {
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
        VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
            original: original,
            replacement: replacement
        )
    }

    public func submitting(existingOriginalTexts: [String]) -> VoiceInkWordReplacementDraftSubmission {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )
        return VoiceInkWordReplacementDraftSubmission(
            submittedOriginal: original,
            submittedReplacement: replacement,
            plan: plan,
            draftStateAfterSubmit: VoiceInkWordReplacementDraftState(
                original: plan.originalDraftAfterSubmit,
                replacement: plan.replacementDraftAfterSubmit
            )
        )
    }

    public func submitting(existingRules: [VoiceInkWordReplacementRule]) -> VoiceInkWordReplacementDraftSubmission {
        submitting(existingOriginalTexts: existingRules.map(\.originalText))
    }
}

public struct VoiceInkWordReplacementEditSubmission: Equatable, Sendable {
    public let submittedOriginal: String
    public let submittedReplacement: String
    public let plan: VoiceInkWordReplacementInsertPlan
    public let alertPresentation: VoiceInkDictionaryAlertPresentation?

    public init(
        submittedOriginal: String,
        submittedReplacement: String,
        plan: VoiceInkWordReplacementInsertPlan,
        alertPresentation: VoiceInkDictionaryAlertPresentation?
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

public struct VoiceInkWordReplacementEditState: Equatable, Sendable {
    public var original: String
    public var replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }

    public var canSave: Bool {
        VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
            original: original,
            replacement: replacement
        )
    }

    public func submitting(existingOriginalTexts: [String]) -> VoiceInkWordReplacementEditSubmission {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )
        return VoiceInkWordReplacementEditSubmission(
            submittedOriginal: original,
            submittedReplacement: replacement,
            plan: plan,
            alertPresentation: plan.errorMessage.map(VoiceInkDictionaryAlertPresentation.wordReplacement)
        )
    }

    public func submitting(existingRules: [VoiceInkWordReplacementRule]) -> VoiceInkWordReplacementEditSubmission {
        submitting(existingOriginalTexts: existingRules.map(\.originalText))
    }
}

public struct VoiceInkWordReplacementBackupImportPlan: Equatable, Sendable {
    public let rulesToInsert: [VoiceInkWordReplacementRule]
    public let skippedInvalidReplacementCount: Int

    public init(
        rulesToInsert: [VoiceInkWordReplacementRule],
        skippedInvalidReplacementCount: Int
    ) {
        self.rulesToInsert = rulesToInsert
        self.skippedInvalidReplacementCount = skippedInvalidReplacementCount
    }
}

public struct VoiceInkDictionaryBackupImportPlan: Equatable, Sendable {
    public let hasVocabularyBackupRecords: Bool
    public let hasWordReplacementBackupRecords: Bool
    public let vocabularyWordsToInsert: [String]
    public let wordReplacementRulesToInsert: [VoiceInkWordReplacementRule]
    public let skippedInvalidReplacementCount: Int

    public var insertedVocabularyWordCount: Int {
        vocabularyWordsToInsert.count
    }

    public var insertedWordReplacementCount: Int {
        wordReplacementRulesToInsert.count
    }

    public var shouldSave: Bool {
        insertedVocabularyWordCount > 0 || insertedWordReplacementCount > 0
    }

    public var shouldInvalidateWordReplacementCache: Bool {
        insertedWordReplacementCount > 0
    }

    public init(
        hasVocabularyBackupRecords: Bool,
        hasWordReplacementBackupRecords: Bool,
        vocabularyWordsToInsert: [String],
        wordReplacementRulesToInsert: [VoiceInkWordReplacementRule],
        skippedInvalidReplacementCount: Int
    ) {
        self.hasVocabularyBackupRecords = hasVocabularyBackupRecords
        self.hasWordReplacementBackupRecords = hasWordReplacementBackupRecords
        self.vocabularyWordsToInsert = vocabularyWordsToInsert
        self.wordReplacementRulesToInsert = wordReplacementRulesToInsert
        self.skippedInvalidReplacementCount = skippedInvalidReplacementCount
    }
}

public struct VoiceInkDictionaryBackupExportPlan: Equatable, Sendable {
    public let vocabularyBackupRecords: [VoiceInkVocabularyWordBackup]?
    public let wordReplacementBackupRecords: [String: String]?

    public init(
        vocabularyBackupRecords: [VoiceInkVocabularyWordBackup]?,
        wordReplacementBackupRecords: [String: String]?
    ) {
        self.vocabularyBackupRecords = vocabularyBackupRecords
        self.wordReplacementBackupRecords = wordReplacementBackupRecords
    }
}

public struct VoiceInkVocabularyWordBackup: Codable, Equatable, Sendable {
    public let word: String

    public init(word: String) {
        self.word = word
    }
}

public struct VoiceInkDictionaryAlertPresentation: Equatable, Identifiable, Sendable {
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

    public static func duplicateFillerWord(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
            id: "duplicateFillerWord-\(message)",
            title: "Duplicate Word",
            message: message
        )
    }

    public static func vocabulary(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
            id: "vocabulary-\(message)",
            title: "Vocabulary",
            message: message
        )
    }

    public static func wordReplacement(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
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

public struct VoiceInkDictionarySettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let heroDescription: String?
    public let sectionSelectorTitle: String?
    public let settingsButtonHelp: String?
    public let wordReplacementsSection: VoiceInkDictionarySettingsSectionPresentation
    public let vocabularySection: VoiceInkDictionarySettingsSectionPresentation
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

    public static let iOS = VoiceInkDictionarySettingsPresentation(
        sectionTitle: "Dictionary",
        heroDescription: nil,
        sectionSelectorTitle: nil,
        settingsButtonHelp: nil,
        wordReplacementsSection: VoiceInkDictionarySettingsSectionPresentation(
            title: "Word Replacements",
            description: "",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularySection: VoiceInkDictionarySettingsSectionPresentation(
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

    public static let macOS = VoiceInkDictionarySettingsPresentation(
        sectionTitle: "Dictionary Settings",
        heroDescription: "Enhance VoiceInk's transcription accuracy by teaching it your vocabulary",
        sectionSelectorTitle: "Select Section",
        settingsButtonHelp: "Dictionary settings",
        wordReplacementsSection: VoiceInkDictionarySettingsSectionPresentation(
            title: "Word Replacements",
            description: "Automatically replace specific words/phrases with custom formatted text ",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularySection: VoiceInkDictionarySettingsSectionPresentation(
            title: "Vocabulary",
            description: "Add words to help VoiceInk recognize them properly",
            systemImageName: "character.book.closed.fill"
        ),
        vocabularyHelpText: "Add words to help VoiceInk recognize them properly. (Requires AI enhancement)",
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

public struct VoiceInkDictionarySettingsSectionPresentation: Equatable, Sendable {
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

public enum VoiceInkDictionarySettingsSection: String, CaseIterable, Sendable {
    case wordReplacements
    case vocabulary

    public static let defaultSelection: Self = .wordReplacements

    public func presentation(
        in presentation: VoiceInkDictionarySettingsPresentation
    ) -> VoiceInkDictionarySettingsSectionPresentation {
        switch self {
        case .wordReplacements:
            return presentation.wordReplacementsSection
        case .vocabulary:
            return presentation.vocabularySection
        }
    }
}

public struct VoiceInkDictionaryQuickAddPresentation: Equatable, Sendable {
    public let vocabularyMode: VoiceInkDictionaryQuickAddModePresentation
    public let replacementMode: VoiceInkDictionaryQuickAddModePresentation
    public let vocabularyPlaceholder: String
    public let originalLabel: String
    public let originalPlaceholder: String
    public let replacementLabel: String
    public let replacementPlaceholder: String
    public let submitHintTitle: String
    public let dismissHintTitle: String

    public static let macOS = VoiceInkDictionaryQuickAddPresentation(
        vocabularyMode: VoiceInkDictionaryQuickAddModePresentation(
            title: "Vocabulary",
            systemImageName: "character.book.closed.fill"
        ),
        replacementMode: VoiceInkDictionaryQuickAddModePresentation(
            title: "Word Replacement",
            systemImageName: "arrow.2.squarepath"
        ),
        vocabularyPlaceholder: "e.g. Prakash, VoiceInk",
        originalLabel: "Replace",
        originalPlaceholder: "e.g. my email, my mail",
        replacementLabel: "With",
        replacementPlaceholder: "e.g. support@tryvoiceink.com",
        submitHintTitle: "Add",
        dismissHintTitle: "Dismiss"
    )
}

public struct VoiceInkDictionaryQuickAddModePresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }
}

public struct VoiceInkWordReplacementInfoPresentation: Equatable, Sendable {
    public let title: String
    public let multipleOriginalsHelpText: String
    public let multipleOriginalsExampleText: String
    public let examplesTitle: String
    public let originalLabel: String
    public let replacementLabel: String
    public let examples: [VoiceInkWordReplacementExamplePresentation]

    public static let macOS = VoiceInkWordReplacementInfoPresentation(
        title: "How to use Word Replacements",
        multipleOriginalsHelpText: "Separate multiple originals with commas:",
        multipleOriginalsExampleText: "Voicing, Voice ink, Voiceing",
        examplesTitle: "Examples",
        originalLabel: "Original:",
        replacementLabel: "Replacement:",
        examples: [
            VoiceInkWordReplacementExamplePresentation(
                originalText: "my website link",
                replacementText: "https://tryvoiceink.com"
            ),
            VoiceInkWordReplacementExamplePresentation(
                originalText: "Voicing, Voice ink",
                replacementText: "VoiceInk"
            )
        ]
    )
}

public struct VoiceInkWordReplacementExamplePresentation: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String

    public init(originalText: String, replacementText: String) {
        self.originalText = originalText
        self.replacementText = replacementText
    }
}

public struct VoiceInkWordReplacementEditPresentation: Equatable, Sendable {
    public let cancelButtonTitle: String
    public let title: String
    public let saveButtonTitle: String
    public let descriptionText: String
    public let originalFieldTitle: String
    public let requiredText: String
    public let originalPlaceholder: String
    public let replacementFieldTitle: String

    public static let macOS = VoiceInkWordReplacementEditPresentation(
        cancelButtonTitle: "Cancel",
        title: "Edit Word Replacement",
        saveButtonTitle: "Save",
        descriptionText: "Update the word or phrase that should be automatically replaced.",
        originalFieldTitle: "Original Text",
        requiredText: "Required",
        originalPlaceholder: "Enter word or phrase to replace (use commas for multiple)",
        replacementFieldTitle: "Replacement Text"
    )
}

public struct VoiceInkVocabularyListPresentation: Equatable, Sendable {
    public let wordsTitlePrefix: String
    public let sortHelpText: String
    public let removeButtonHelp: String

    public static let macOS = VoiceInkVocabularyListPresentation(
        wordsTitlePrefix: "Vocabulary Words",
        sortHelpText: "Sort alphabetically",
        removeButtonHelp: "Remove word"
    )

    public func wordsTitle(count: Int) -> String {
        "\(wordsTitlePrefix) (\(count))"
    }
}

public struct VoiceInkWordReplacementListPresentation: Equatable, Sendable {
    public let originalColumnTitle: String
    public let replacementColumnTitle: String
    public let sortOriginalHelpText: String
    public let sortReplacementHelpText: String
    public let editButtonHelp: String
    public let removeButtonHelp: String

    public static let macOS = VoiceInkWordReplacementListPresentation(
        originalColumnTitle: "Original",
        replacementColumnTitle: "Replacement",
        sortOriginalHelpText: "Sort by original",
        sortReplacementHelpText: "Sort by replacement",
        editButtonHelp: "Edit replacement",
        removeButtonHelp: "Remove replacement"
    )
}

public enum VoiceInkVocabularySortMode: String, CaseIterable, Sendable {
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

public enum VoiceInkWordReplacementSortColumn: Sendable {
    case original
    case replacement
}

public enum VoiceInkWordReplacementSortMode: String, CaseIterable, Sendable {
    case originalAscending = "originalAsc"
    case originalDescending = "originalDesc"
    case replacementAscending = "replacementAsc"
    case replacementDescending = "replacementDesc"

    public static let defaultMode: Self = .originalAscending

    public var activeColumn: VoiceInkWordReplacementSortColumn {
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

    public func toggled(for column: VoiceInkWordReplacementSortColumn) -> Self {
        switch column {
        case .original:
            return self == .originalAscending ? .originalDescending : .originalAscending
        case .replacement:
            return self == .replacementAscending ? .replacementDescending : .replacementAscending
        }
    }
}

public enum VoiceInkDictionaryListSortPreference {
    public static let vocabularySortModeKey = "vocabularySortMode"
    public static let wordReplacementSortModeKey = "wordReplacementSortMode"

    public static func vocabularySortMode(from defaults: UserDefaults = .standard) -> VoiceInkVocabularySortMode {
        guard let rawValue = defaults.string(forKey: vocabularySortModeKey),
              let mode = VoiceInkVocabularySortMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveVocabularySortMode(
        _ mode: VoiceInkVocabularySortMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: vocabularySortModeKey)
    }

    public static func wordReplacementSortMode(from defaults: UserDefaults = .standard) -> VoiceInkWordReplacementSortMode {
        guard let rawValue = defaults.string(forKey: wordReplacementSortModeKey),
              let mode = VoiceInkWordReplacementSortMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveWordReplacementSortMode(
        _ mode: VoiceInkWordReplacementSortMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: wordReplacementSortModeKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: vocabularySortModeKey)
        defaults.removeObject(forKey: wordReplacementSortModeKey)
    }
}

public enum VoiceInkDictionaryListSortPolicy {
    public static func sortedVocabulary<Item>(
        _ items: [Item],
        mode: VoiceInkVocabularySortMode,
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
        mode: VoiceInkVocabularySortMode,
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
        mode: VoiceInkWordReplacementSortMode,
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
        mode: VoiceInkWordReplacementSortMode,
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

public enum VoiceInkDictionaryPolicy {
    public static func hasVocabularyDraft(_ input: String) -> Bool {
        !tokens(from: input).isEmpty
    }

    public static func vocabularySubmissionPlan(
        input: String,
        existingWords: [String]
    ) -> VoiceInkVocabularySubmissionPlan {
        let words = tokens(from: input)
        guard !words.isEmpty else {
            return VoiceInkVocabularySubmissionPlan(
                wordsToInsert: [],
                draftAfterSubmit: input,
                alertPresentation: nil
            )
        }

        let existingKeys = Set(existingWords.map { $0.lowercased() })

        if words.count == 1, let word = words.first, existingKeys.contains(word.lowercased()) {
            return VoiceInkVocabularySubmissionPlan(
                wordsToInsert: [],
                draftAfterSubmit: input,
                alertPresentation: .vocabulary(message: "'\(word)' is already in the vocabulary")
            )
        }

        let wordsToInsert = vocabularyWordsToInsert(words, existingWords: existingWords)

        return VoiceInkVocabularySubmissionPlan(
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

    public static func vocabularyBackupRecords(from words: [String]) -> [VoiceInkVocabularyWordBackup] {
        words.map { VoiceInkVocabularyWordBackup(word: $0) }
    }

    public static func vocabularyWordsToInsert(
        from backupRecords: [VoiceInkVocabularyWordBackup],
        existingWords: [String]
    ) -> [String] {
        vocabularyWordsToInsert(
            backupRecords.map(\.word),
            existingWords: existingWords
        )
    }

    public static func dictionaryBackupImportPlan(
        vocabularyWords: [VoiceInkVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        existingWords: [String],
        existingOriginalTexts: [String]
    ) -> VoiceInkDictionaryBackupImportPlan {
        let wordReplacementPlan = wordReplacements.map {
            wordReplacementBackupImportPlan(
                from: $0,
                existingOriginalTexts: existingOriginalTexts
            )
        } ?? VoiceInkWordReplacementBackupImportPlan(
            rulesToInsert: [],
            skippedInvalidReplacementCount: 0
        )

        return VoiceInkDictionaryBackupImportPlan(
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
        wordReplacementRules: [VoiceInkWordReplacementRule]
    ) -> VoiceInkDictionaryBackupExportPlan {
        VoiceInkDictionaryBackupExportPlan(
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
    ) -> VoiceInkWordReplacementBackupImportPlan {
        var existingOriginalTexts = existingOriginalTexts
        var rulesToInsert = [VoiceInkWordReplacementRule]()
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
                VoiceInkWordReplacementRule(
                    originalText: plan.originalText,
                    replacementText: plan.replacementText
                )
            )
            existingOriginalTexts.append(plan.originalText)
        }

        return VoiceInkWordReplacementBackupImportPlan(
            rulesToInsert: rulesToInsert,
            skippedInvalidReplacementCount: skippedInvalidReplacementCount
        )
    }

    public static func wordReplacementInsertPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> VoiceInkWordReplacementInsertPlan {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTokens = tokens(from: trimmedOriginal)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalTokens.isEmpty, !trimmedReplacement.isEmpty else {
            return VoiceInkWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: nil
            )
        }

        let existingTokens = Set(existingOriginalTexts.flatMap { tokens(from: $0).map { $0.lowercased() } })

        for token in originalTokens where existingTokens.contains(token.lowercased()) {
            return VoiceInkWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: "'\(token)' already exists in word replacements"
            )
        }

        return VoiceInkWordReplacementInsertPlan(
            originalText: trimmedOriginal,
            replacementText: trimmedReplacement,
            errorMessage: nil
        )
    }

    public static func wordReplacementSubmissionPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> VoiceInkWordReplacementSubmissionPlan {
        let plan = wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )

        if let errorMessage = plan.errorMessage {
            return VoiceInkWordReplacementSubmissionPlan(
                ruleToInsert: nil,
                originalDraftAfterSubmit: original,
                replacementDraftAfterSubmit: replacement,
                alertPresentation: .wordReplacement(message: errorMessage)
            )
        }

        guard plan.shouldInsert else {
            return VoiceInkWordReplacementSubmissionPlan(
                ruleToInsert: nil,
                originalDraftAfterSubmit: original,
                replacementDraftAfterSubmit: replacement,
                alertPresentation: nil
            )
        }

        return VoiceInkWordReplacementSubmissionPlan(
            ruleToInsert: VoiceInkWordReplacementRule(
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
