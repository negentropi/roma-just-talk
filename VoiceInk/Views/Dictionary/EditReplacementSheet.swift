import SwiftUI
import SwiftData
import VoiceInkCore

/// One edit presentation: the entry plus the complete validated record captured when Edit was
/// chosen. Held in `@State` by both the list and the sheet, so it never advances while open.
struct WordReplacementEditTarget: Identifiable {
    let id = UUID()
    let entry: WordReplacement
    let expectedRecord: VoiceInkWordReplacementRecord
}

// Edit existing word replacement entry. DictionaryService preserves its ID, date added,
// enabled state, matching kind and provenance; this sheet edits only the pair text, and the
// save is rejected if the stored entry changed after the sheet opened.
struct EditReplacementSheet: View {
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    /// Frozen for this presentation; SwiftUI keeps the first value if the view is re-initialized.
    @State private var target: WordReplacementEditTarget
    @State private var original: String
    @State private var replacementText: String
    @State private var issue: WordReplacementIssue?
    /// Set once the service reports the entry changed or was removed; only Close remains.
    @State private var isStale = false
    private let editPresentation = VoiceInkWordReplacementEditPresentation.macOS

    // MARK: – Initialiser
    init(target: WordReplacementEditTarget, modelContext: ModelContext) {
        self.modelContext = modelContext
        _target = State(initialValue: target)
        // Drafts start from the validated record, never the raw legacy columns.
        _original = State(initialValue: target.expectedRecord.originalText)
        _replacementText = State(initialValue: target.expectedRecord.replacementText)
    }

    private var record: VoiceInkWordReplacementRecord { target.expectedRecord }
    private var kind: VoiceInkWordReplacementMatchingKind { record.matchingKind }

    /// Literal input is never trimmed here; DictionaryService validates and stores it exactly.
    private var canSave: Bool {
        guard !isStale else { return false }
        switch kind {
        case .literal:
            return !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .legacyCommaAlternatives:
            return VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
                original: original,
                replacement: replacementText
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(Divider().opacity(0.5), alignment: .bottom)
            formContent
        }
        .frame(width: 480, height: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dictionary.replacement.edit")
    }

    // MARK: – Subviews
    private var header: some View {
        HStack {
            Button(isStale ? "Close" : editPresentation.cancelButtonTitle, role: .cancel) { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("dictionary.replacement.edit.cancel")

            Spacer()

            Text(editPresentation.title)
                .font(.headline)

            Spacer()

            Button(editPresentation.saveButtonTitle) { saveChanges() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("dictionary.replacement.edit.save")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(CardBackground(isSelected: false))
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                descriptionSection
                metadataSection
                inputSection
                if let issue {
                    WordReplacementIssueView(issue: issue, identifier: "dictionary.replacement.edit.error")
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private var descriptionSection: some View {
        Text(kind == .literal
            ? "Update the phrase that should be replaced. It is one phrase, including commas, spaces and line breaks. Matching ignores letter case."
            : editPresentation.descriptionText)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    /// Shows the record as opened; the service keeps every one of these values on save.
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            metadataRow("Kind", value: kind.dictionaryReviewTitle, id: "kind")
                .help(kind.dictionaryReviewHelp)
            metadataRow("State", value: record.isEnabled ? "On" : "Off", id: "enabled")
            metadataRow(
                "Added",
                value: record.dateAdded.formatted(date: .abbreviated, time: .standard),
                id: "dateAdded"
            )
            metadataRow("ID", value: record.id.uuidString, id: "id")
            if let provenance = record.provenance {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Source")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    WordReplacementSourceStatus(
                        provenance: provenance,
                        identifier: "dictionary.replacement.edit.provenance"
                    )
                }
                .font(.caption)
            }
            Text("Turn this entry on or off from the Dictionary list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func metadataRow(_ label: String, value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(verbatim: value)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dictionary.replacement.edit.\(id)")
    }

    @ViewBuilder
    private var inputSection: some View {
        switch kind {
        case .literal: literalInputSection
        case .legacyCommaAlternatives: legacyInputSection
        }
    }

    private var literalInputSection: some View {
        VStack(spacing: 16) {
            fieldGroup(title: editPresentation.originalFieldTitle, footer: "One phrase, including commas. Matching ignores letter case.") {
                literalEditor(text: originalBinding, label: "Original text", id: "dictionary.replacement.edit.original")
                    .frame(height: 70)
            }
            fieldGroup(title: editPresentation.replacementFieldTitle, footer: "Saved exactly as typed, including commas, spaces and symbols.") {
                literalEditor(text: replacementBinding, label: "Replacement text", id: "dictionary.replacement.edit.replacement")
                    .frame(height: 100)
            }
        }
    }

    private var legacyInputSection: some View {
        VStack(spacing: 16) {
            fieldGroup(title: editPresentation.originalFieldTitle, footer: nil) {
                TextField(editPresentation.originalPlaceholder, text: originalBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isStale)
                    .accessibilityIdentifier("dictionary.replacement.edit.original")
            }
            fieldGroup(title: editPresentation.replacementFieldTitle, footer: nil) {
                TextEditor(text: replacementBinding)
                    .font(.body)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .disabled(isStale)
                    .accessibilityIdentifier("dictionary.replacement.edit.replacement")
            }
        }
    }

    private func fieldGroup<Content: View>(
        title: String,
        footer: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Text(editPresentation.requiredText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func literalEditor(text: Binding<String>, label: String, id: String) -> some View {
        ExactLiteralTextEditor(
            text: text,
            accessibilityLabel: label,
            accessibilityIdentifier: id,
            isEditable: !isStale
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }

    // MARK: – State

    /// Setters, not `onChange(of: String)`, so a normalization-only edit still clears a past error.
    /// A stale-revision error stays until the sheet is closed.
    private var originalBinding: Binding<String> {
        Binding(get: { original }, set: { newValue in
            original = newValue
            if !isStale { issue = nil }
        })
    }

    private var replacementBinding: Binding<String> {
        Binding(get: { replacementText }, set: { newValue in
            replacementText = newValue
            if !isStale { issue = nil }
        })
    }

    // MARK: – Actions
    private func saveChanges() {
        guard canSave else { return }
        let entry = target.entry
        // A removed entry has no current record to compare; never touch its storage.
        guard !entry.isDeleted, entry.modelContext != nil else {
            isStale = true
            issue = WordReplacementIssue(message: "This replacement was deleted while it was open. Nothing was saved.")
            return
        }
        do {
            // Always the record captured at open, never one reread at Save.
            try DictionaryService.updateWordReplacement(
                entry,
                expectedRecord: target.expectedRecord,
                originalText: original,
                replacementText: replacementText,
                context: modelContext
            )
            dismiss()
        } catch let revision as DictionaryService.LibraryRevisionError {
            isStale = true
            issue = WordReplacementIssue(revision)
        } catch let stored as WordReplacement.StoredValueError {
            // The stored entry became unreadable while open; it can't be compared or edited.
            isStale = true
            issue = WordReplacementIssue(message: "\(stored.localizedDescription) Nothing was saved. Close this editor and review the entry in the Dictionary list.")
        } catch {
            issue = WordReplacementIssue(error)
        }
    }
}
