import SwiftUI
import SwiftData
import VoiceInkCore

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    /// Entry plus the validated record rendered when Edit was chosen; frozen while the sheet is open.
    @State private var editTarget: WordReplacementEditTarget?
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    @State private var sortMode: VoiceInkWordReplacementSortMode = .defaultMode
    @State private var wordReplacementDraftState = VoiceInkWordReplacementDraftState()
    @State private var addIssue: WordReplacementIssue?
    @State private var rowIssues: [UUID: WordReplacementIssue] = [:]
    @State private var showInfoPopover = false
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.macOS
    private let listPresentation = VoiceInkWordReplacementListPresentation.macOS

    init() {
        _sortMode = State(initialValue: VoiceInkDictionaryListSortPreference.wordReplacementSortMode())
    }

    private func toggleSort(for column: VoiceInkWordReplacementSortColumn) {
        sortMode = sortMode.toggled(for: column)
        VoiceInkDictionaryListSortPreference.saveWordReplacementSortMode(sortMode)
    }

    var body: some View {
        let storedRows = Dictionary(
            wordReplacements.map { ($0.persistentModelID, StoredRow(entry: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        // Sort keys come only from validated records. Unsupported rows are never dropped: they
        // follow the sorted rows in date-added order, without using their raw text as a key.
        let validReplacements = wordReplacements.filter { storedRows[$0.persistentModelID]?.record != nil }
        let unsupportedReplacements = wordReplacements
            .filter { storedRows[$0.persistentModelID]?.record == nil }
            .sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) }
        let sortedReplacements = VoiceInkDictionaryListSortPolicy.sortedWordReplacements(
            validReplacements,
            mode: sortMode,
            originalText: { storedRows[$0.persistentModelID]?.record?.originalText ?? "" },
            replacementText: { storedRows[$0.persistentModelID]?.record?.replacementText ?? "" }
        ) + unsupportedReplacements
        let unsupportedCount = unsupportedReplacements.count
        let shouldShowAddButton = wordReplacementDraftState.hasDraft

        VStack(alignment: .leading, spacing: 20) {
            if let helpText = dictionaryPresentation.wordReplacementHelpText {
                GroupBox {
                    Label {
                        Text(helpText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Button(action: { showInfoPopover.toggle() }) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showInfoPopover) {
                            WordReplacementInfoPopover()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(dictionaryPresentation.originalTextPlaceholder, text: $wordReplacementDraftState.original)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("dictionary.replacement.add.original")

                Image(systemName: dictionaryPresentation.wordReplacementArrowSystemImageName)
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                TextField(dictionaryPresentation.replacementTextPlaceholder, text: $wordReplacementDraftState.replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addReplacement() }
                    .accessibilityIdentifier("dictionary.replacement.add.replacement")

                if shouldShowAddButton {
                    Button(action: addReplacement) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!wordReplacementDraftState.canSubmit)
                    .help(dictionaryPresentation.addReplacementButtonHelp ?? "")
                    .accessibilityIdentifier("dictionary.replacement.add")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if let addIssue {
                WordReplacementIssueView(issue: addIssue, identifier: "dictionary.replacement.add.error")
            }

            if unsupportedCount > 0 {
                Label {
                    Text(Self.unsupportedNotice(count: unsupportedCount))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                .font(.system(size: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dictionary.replacements.unsupportedNotice")
            }

            if !wordReplacements.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        // Matches the row's enable-switch column.
                        Color.clear
                            .frame(width: ReplacementRow.switchColumnWidth, height: 1)
                            .accessibilityHidden(true)

                        Button(action: { toggleSort(for: .original) }) {
                            HStack(spacing: 4) {
                                Text(listPresentation.originalColumnTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode.activeColumn == .original {
                                    Image(systemName: sortMode.indicatorSystemImageName)
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(listPresentation.sortOriginalHelpText)

                        Image(systemName: dictionaryPresentation.wordReplacementArrowSystemImageName)
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                            .frame(width: 10)

                        Button(action: { toggleSort(for: .replacement) }) {
                            HStack(spacing: 4) {
                                Text(listPresentation.replacementColumnTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode.activeColumn == .replacement {
                                    Image(systemName: sortMode.indicatorSystemImageName)
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(listPresentation.sortReplacementHelpText)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedReplacements) { replacement in
                                let stored = storedRows[replacement.persistentModelID] ?? StoredRow(entry: replacement)
                                ReplacementRow(
                                    entry: replacement,
                                    record: stored.record,
                                    storedIssue: stored.issue,
                                    diagnostics: stored.diagnostics,
                                    issue: rowIssues[replacement.id],
                                    editButtonHelp: listPresentation.editButtonHelp,
                                    removeButtonHelp: listPresentation.removeButtonHelp,
                                    onSetEnabled: { setEnabled(replacement, isEnabled: $0) },
                                    onDelete: { removeReplacement(replacement) },
                                    onEdit: {
                                        // Captures the record this row rendered; Save checks it is still current.
                                        guard let record = stored.record else { return }
                                        editTarget = WordReplacementEditTarget(entry: replacement, expectedRecord: record)
                                    }
                                )

                                if replacement.id != sortedReplacements.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .sheet(item: $editTarget) { target in
            EditReplacementSheet(target: target, modelContext: modelContext)
        }
        .onChange(of: wordReplacementDraftState) { _, _ in addIssue = nil }
        .alert(item: $alertPresentation) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }

    private static func unsupportedNotice(count: Int) -> String {
        let subject = count == 1 ? "1 entry has" : "\(count) entries have"
        return "\(subject) data this version can’t use. Turn it off or delete it; until it’s deleted, adding, editing and approving replacements can fail."
    }

    /// The model's throwing getter decides support; unsupported rows are shown, never skipped.
    /// Valid rows use only the record; literal rows keep their legacy columns deliberately empty.
    private struct StoredRow {
        let record: VoiceInkWordReplacementRecord?
        let issue: String?
        /// Raw columns, only for unsupported rows and only as labeled diagnostics.
        let diagnostics: WordReplacementStoredDiagnostics?

        init(entry: WordReplacement) {
            do {
                record = try entry.record
                issue = nil
                diagnostics = nil
            } catch {
                record = nil
                issue = WordReplacementIssue(error).message
                diagnostics = WordReplacementStoredDiagnostics(entry: entry)
            }
        }
    }

    /// Manual entries use the comma-alternatives contract; the draft clears only after an actual insert.
    private func addReplacement() {
        guard wordReplacementDraftState.canSubmit else { return }
        do {
            _ = try DictionaryService.addWordReplacement(
                originalText: wordReplacementDraftState.original,
                replacementText: wordReplacementDraftState.replacement,
                context: modelContext
            )
            wordReplacementDraftState = VoiceInkWordReplacementDraftState()
            addIssue = nil
        } catch {
            addIssue = WordReplacementIssue(error)
        }
    }

    private func setEnabled(_ replacement: WordReplacement, isEnabled: Bool) {
        let id = replacement.id
        do {
            try DictionaryService.setWordReplacementEnabled(replacement, isEnabled: isEnabled, context: modelContext)
            rowIssues[id] = nil
        } catch {
            rowIssues[id] = WordReplacementIssue(error)
        }
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        let id = replacement.id
        if let alert = DictionaryService.removeWordReplacement(replacement, context: modelContext) {
            alertPresentation = alert
        } else {
            rowIssues[id] = nil
        }
    }
}

struct WordReplacementInfoPopover: View {
    private let infoPresentation = VoiceInkWordReplacementInfoPresentation.macOS

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(infoPresentation.title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(infoPresentation.multipleOriginalsHelpText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(infoPresentation.multipleOriginalsExampleText)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            Text(infoPresentation.examplesTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach(infoPresentation.examples, id: \.originalText) { example in
                    WordReplacementInfoExampleRow(
                        example: example,
                        originalLabel: infoPresentation.originalLabel,
                        replacementLabel: infoPresentation.replacementLabel
                    )
                }
            }
        }
        .padding()
        .frame(width: 380)
    }
}

private struct WordReplacementInfoExampleRow: View {
    let example: VoiceInkWordReplacementExamplePresentation
    let originalLabel: String
    let replacementLabel: String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(originalLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(example.originalText)
                    .font(.callout)
            }

            Image(systemName: VoiceInkDictionarySettingsPresentation.macOS.wordReplacementArrowSystemImageName)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(replacementLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(example.replacementText)
                    .font(.callout)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
    }
}

struct ReplacementRow: View {
    let entry: WordReplacement
    /// The validated record; nil when the stored entry is unsupported.
    let record: VoiceInkWordReplacementRecord?
    /// Non-nil when the stored entry can't be read as a supported record.
    let storedIssue: String?
    let diagnostics: WordReplacementStoredDiagnostics?
    let issue: WordReplacementIssue?
    let editButtonHelp: String
    let removeButtonHelp: String
    let onSetEnabled: (Bool) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    static let switchColumnWidth: CGFloat = 28

    private var identifier: String { "dictionary.replacement.\(entry.id.uuidString)" }
    private var isUnsupported: Bool { storedIssue != nil }

    private var toggleHelp: String {
        if isUnsupported && !entry.isEnabled { return "Unsupported entries can’t be turned on." }
        return entry.isEnabled ? "Turn off this replacement" : "Turn on this replacement"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Turning off is always allowed; turning on an unsupported entry is not.
                Toggle("Use replacement", isOn: Binding(get: { entry.isEnabled }, set: onSetEnabled))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .frame(width: Self.switchColumnWidth)
                    .disabled(isUnsupported && !entry.isEnabled)
                    .help(toggleHelp)
                    .accessibilityIdentifier("\(identifier).enabled")

                pairText(record?.originalText, placeholder: "Unreadable entry")

                Image(systemName: VoiceInkDictionarySettingsPresentation.macOS.wordReplacementArrowSystemImageName)
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                ZStack(alignment: .trailing) {
                    pairText(record?.replacementText, placeholder: "Not shown")
                        .padding(.trailing, 50)

                    HStack(spacing: 6) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(isEditHovered && !isUnsupported ? .accentColor : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isUnsupported)
                        .help(isUnsupported ? "Unsupported entries can’t be edited. Turn it off or delete it." : editButtonHelp)
                        .accessibilityLabel("Edit")
                        .accessibilityIdentifier("\(identifier).edit")
                        .onHover { hover in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditHovered = hover
                            }
                        }

                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(isDeleteHovered ? .red : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .help(removeButtonHelp)
                        .accessibilityLabel("Delete")
                        .accessibilityIdentifier("\(identifier).delete")
                        .onHover { hover in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDeleteHovered = hover
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            metadata

            if let issue {
                WordReplacementIssueView(issue: issue, identifier: "\(identifier).error")
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// Exactly one text element per side. Unsupported rows show a marker, never raw columns.
    @ViewBuilder
    private func pairText(_ value: String?, placeholder: String) -> some View {
        if let value {
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(entry.isEnabled ? Color.primary : Color.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(placeholder)
                .font(.system(size: 13).italic())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Kind, support and provenance only; never repeats the source/output pair text.
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            metadataLine
            if let diagnostics {
                WordReplacementRawDiagnosticsView(diagnostics: diagnostics, identifier: "\(identifier).diagnostics")
            }
        }
        // Align with the pair text, past the switch column and its spacing.
        .padding(.leading, Self.switchColumnWidth + 8)
    }

    private var metadataLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let kind = record?.matchingKind {
                badge(kind.dictionaryReviewTitle, tint: .secondary)
                    .help(kind.dictionaryReviewHelp)
                    .accessibilityIdentifier("\(identifier).kind")
            }
            if let storedIssue {
                badge("Unsupported", tint: .red)
                    .accessibilityIdentifier("\(identifier).unsupported")
                Text(verbatim: storedIssue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).unsupportedReason")
            }
            if let provenance = record?.provenance {
                WordReplacementSourceStatus(provenance: provenance, identifier: "\(identifier).provenance")
            }
            if !entry.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(identifier).offState")
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(verbatim: title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.5))
    }
}
