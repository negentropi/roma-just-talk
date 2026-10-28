import SwiftUI
import SwiftData
import VoiceInkCore

/// One History text variant, captured through the approval service when Save Correction was chosen.
struct SaveCorrectionTarget: Identifiable {
    let id = UUID()
    let source: HistoryCorrectionApprovalService.Source

    /// `displayedText` must be the exact text on screen, so a stale view never captures a newer revision.
    @MainActor
    static func capture(
        transcriptionID: UUID,
        variant: HistoryTextVariant,
        displayedText: String,
        using context: ModelContext
    ) throws -> SaveCorrectionTarget {
        SaveCorrectionTarget(source: try HistoryCorrectionApprovalService.capture(
            transcriptionID: transcriptionID,
            variant: variant.correctionSourceVariant,
            expectedText: displayedText,
            using: context
        ))
    }
}

/// Entry point shown with a visible History variant. Identifiers avoid the
/// `history.variant.` and `history.copy.` prefixes used by tabs and copy buttons.
struct SaveCorrectionButton: View {
    let variant: HistoryTextVariant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Save Correction…", systemImage: "text.badge.checkmark")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Choose a phrase in this \(variant.title) text and save how it should be written. Nothing is saved until you approve.")
        .accessibilityIdentifier("history.correction.save.\(variant.rawValue)")
    }
}

struct SaveCorrectionCaptureError: View {
    let variant: HistoryTextVariant
    let message: String

    var body: some View {
        Label {
            Text(verbatim: message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.red)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.correction.captureError.\(variant.rawValue)")
    }
}

/// Explicit approval of one literal phrase from captured History text. Nothing persists until
/// Approve, which the service revalidates against the current transcript and library.
struct SaveCorrectionSheet: View {
    let target: SaveCorrectionTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var phrase = ""
    @State private var output = ""
    @State private var occurrences: [NSRange] = []
    @State private var occurrenceError: String?
    @State private var selectedRange: NSRange?
    @State private var preview: HistoryCorrectionApprovalService.Preview?
    @State private var previewInputs: PreviewInputs?
    @State private var issue: WordReplacementIssue?
    @State private var outcome: Outcome?
    /// Bumped by every phrase/output setter call and every match choice. `String ==` folds
    /// canonically equivalent spellings, so equality alone can't tell that a draft changed.
    @State private var draftRevision = 0

    private struct PreviewInputs {
        let revision: Int
        let phrase: String
        let range: NSRange
        let output: String
    }

    private enum EnabledCheck {
        case on, off, notFound
        case failed(String)
    }

    private enum Outcome {
        case inserted(id: UUID, isEnabled: Bool)
        case alreadyExists(id: UUID, state: EnabledCheck)
    }

    private var variant: HistoryTextVariant { HistoryTextVariant(target.source.variant) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                Section {
                    sourceText
                } header: {
                    Text("\(variant.title) Text")
                } footer: {
                    Text("\(variant.helpText) Captured when you chose Save Correction. Saving a correction doesn’t change this transcript or text already pasted anywhere.")
                        .settingsDescription()
                }

                Section {
                    ExactLiteralTextEditor(
                        text: phraseBinding,
                        accessibilityLabel: "Phrase to replace",
                        accessibilityIdentifier: "history.correction.phrase",
                        isEditable: outcome == nil
                    )
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                    occurrenceList
                } header: {
                    Text("Phrase to Replace")
                } footer: {
                    Text("To find it, type it exactly as shown above, including letter case, spaces and punctuation; copying it is easiest. The saved entry is one phrase, including commas. Matching ignores letter case.")
                        .settingsDescription()
                }

                Section {
                    ExactLiteralTextEditor(
                        text: outputBinding,
                        accessibilityLabel: "Replace with",
                        accessibilityIdentifier: "history.correction.output",
                        isEditable: outcome == nil
                    )
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                } header: {
                    Text("Replace With")
                } footer: {
                    Text("Saved exactly as typed, including commas, spaces and symbols.")
                        .settingsDescription()
                }

                Section {
                    previewContent
                } header: {
                    Text("Preview")
                }

                if let issue {
                    Section {
                        WordReplacementIssueView(issue: issue, identifier: "history.correction.error")
                    }
                }

                if let outcome {
                    Section {
                        outcomeView(outcome)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .frame(width: 620, height: 720)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.correction.sheet")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Save Correction")
                .font(.title3.weight(.semibold))
            Text("Choose a phrase from this History text and how it should be written. Review the exact Dictionary entry, then approve it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding([.horizontal, .top], 20)
    }

    private var sourceText: some View {
        ScrollView {
            Text(verbatim: target.source.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("history.correction.sourceText")
        }
        .frame(minHeight: 44, maxHeight: 120)
    }

    @ViewBuilder
    private var occurrenceList: some View {
        if let occurrenceError {
            Label(occurrenceError, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier("history.correction.occurrences.error")
        } else if phrase.isEmpty {
            EmptyView()
        } else if occurrences.isEmpty {
            Label("This exact phrase isn’t in the text above.", systemImage: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.correction.occurrences.none")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrenceStatus)
                    .font(.callout)
                    .foregroundStyle(selectedRange == nil ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("history.correction.occurrences.status")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(occurrences.enumerated()), id: \.offset) { index, range in
                            occurrenceRow(index: index, range: range)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("history.correction.occurrences")
        }
    }

    private var occurrenceStatus: String {
        if occurrences.count == 1 { return "1 match." }
        if selectedRange == nil { return "\(occurrences.count) matches. Choose the one you mean." }
        return "\(occurrences.count) matches."
    }

    private func occurrenceRow(index: Int, range: NSRange) -> some View {
        let isSelected = selectedRange == range
        return Button {
            selectedRange = range
            draftRevision &+= 1
            issue = nil
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    excerpt(for: range)
                        .font(.callout)
                        .lineLimit(3)
                    Text("Match \(index + 1) of \(occurrences.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(outcome != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("history.correction.occurrence.\(index)")
    }

    @ViewBuilder
    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = currentPreview {
                WordReplacementRecordSummary(
                    title: "Dictionary entry to save",
                    record: current.record,
                    identifier: "history.correction.preview.record"
                )
                planStatus(current.importPlan)
            } else if preview != nil {
                Label(
                    "The phrase, match or replacement changed. Preview again before approving.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("history.correction.preview.stale")
            } else {
                Text("Choose a match and enter the replacement, then Preview to see the exact entry before anything is saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("history.correction.preview.empty")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.correction.preview")
    }

    @ViewBuilder
    private func planStatus(_ plan: VoiceInkWordReplacementLibraryImportPlan) -> some View {
        if !plan.conflicts.isEmpty {
            Label("This conflicts with saved Dictionary entries, so it can’t be approved.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier("history.correction.preview.conflictStatus")
            WordReplacementConflictReview(conflicts: plan.conflicts, identifier: "history.correction.preview.conflicts")
        } else if !plan.duplicates.isEmpty {
            Label("An identical entry is already saved. Approving won’t add another.", systemImage: "info.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.correction.preview.duplicate")
        } else {
            Label("Nothing is saved until you choose Approve (⌘↩).", systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.correction.preview.ready")
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch outcome {
            case .inserted(let id, let isEnabled):
                Label("Saved to Dictionary.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Entry \(id.uuidString) is \(isEnabled ? "on" : "off"). Review, turn off, edit or delete it in Dictionary › Word Replacements.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .alreadyExists(let id, let state):
                Label("Already saved. No new entry was added.", systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text(verbatim: alreadyExistsDetail(id: id, state: state))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.correction.outcome")
    }

    private func alreadyExistsDetail(id: UUID, state: EnabledCheck) -> String {
        switch state {
        case .on: "Saved entry \(id.uuidString) is on."
        case .off: "Saved entry \(id.uuidString) is off. Turn it on in Dictionary › Word Replacements to use it."
        case .notFound: "Saved entry \(id.uuidString) couldn’t be found to check whether it is on."
        case .failed(let message): "Couldn’t check whether saved entry \(id.uuidString) is on: \(message)"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            if outcome != nil {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("history.correction.done")
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("history.correction.cancel")
                Button("Preview", action: makePreview)
                    // Return previews; it never approves.
                    .keyboardShortcut(currentPreview == nil ? KeyboardShortcut.defaultAction : nil)
                    .disabled(!canPreview)
                    .accessibilityIdentifier("history.correction.previewButton")
                Button("Approve", action: approve)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApprove)
                    .help("Save the previewed entry to Dictionary (⌘↩).")
                    .accessibilityIdentifier("history.correction.approve")
            }
        }
        .padding(16)
    }

    // MARK: - State

    /// Input edits go through these setters, not `onChange(of: String)`, so every edit, including a
    /// canonically equivalent Unicode change, discards the match choice and makes any preview stale.
    private var phraseBinding: Binding<String> {
        Binding(get: { phrase }, set: { newValue in
            phrase = newValue
            draftRevision &+= 1
            issue = nil
            refreshOccurrences()
        })
    }

    private var outputBinding: Binding<String> {
        Binding(get: { output }, set: { newValue in
            output = newValue
            draftRevision &+= 1
            issue = nil
        })
    }

    /// Only a preview built from exactly the current phrase, match and replacement is approvable:
    /// same draft revision, same range, and the same UTF-8/UTF-16 code units.
    private var currentPreview: HistoryCorrectionApprovalService.Preview? {
        guard let preview, let previewInputs, let selectedRange,
              previewInputs.revision == draftRevision,
              previewInputs.range == selectedRange,
              preview.range == selectedRange,
              Self.exact(previewInputs.phrase, phrase),
              Self.exact(previewInputs.output, output) else { return nil }
        return preview
    }

    private var canPreview: Bool {
        outcome == nil && selectedRange != nil && !output.isEmpty
    }

    private var canApprove: Bool {
        outcome == nil && currentPreview?.importPlan.canApply == true
    }

    private func refreshOccurrences() {
        selectedRange = nil
        occurrenceError = nil
        guard !phrase.isEmpty else {
            occurrences = []
            return
        }
        do {
            let found = try HistoryCorrectionApprovalService.occurrences(of: phrase, in: target.source)
            occurrences = found
            // A single match is unambiguous; repeated matches always need an explicit choice.
            if found.count == 1 { selectedRange = found[0] }
        } catch {
            occurrences = []
            occurrenceError = error.localizedDescription
        }
    }

    private func makePreview() {
        guard outcome == nil, let range = selectedRange else { return }
        issue = nil
        let inputs = PreviewInputs(revision: draftRevision, phrase: phrase, range: range, output: output)
        do {
            preview = try HistoryCorrectionApprovalService.preview(
                source: target.source, range: range, replacementText: output, using: modelContext
            )
            previewInputs = inputs
        } catch {
            preview = nil
            previewInputs = nil
            issue = WordReplacementIssue(error)
        }
    }

    private func approve() {
        guard outcome == nil, let current = currentPreview, current.importPlan.canApply else { return }
        issue = nil
        do {
            switch try HistoryCorrectionApprovalService.approve(current, using: modelContext) {
            case .inserted(let entry):
                outcome = .inserted(id: entry.id, isEnabled: entry.isEnabled)
            case .alreadyExists(let id):
                outcome = .alreadyExists(id: id, state: enabledState(of: id))
            }
        } catch {
            // The preview is no longer approvable; a fresh Preview rechecks transcript and library.
            preview = nil
            previewInputs = nil
            issue = WordReplacementIssue(error)
        }
    }

    private func enabledState(of id: UUID) -> EnabledCheck {
        var descriptor = FetchDescriptor<WordReplacement>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let entry = try modelContext.fetch(descriptor).first else { return .notFound }
            return entry.isEnabled ? .on : .off
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Display helpers

    /// Visual context only; service-supplied ranges are never adjusted or re-searched here.
    private func excerpt(for range: NSRange) -> Text {
        let text = target.source.text as NSString
        let radius = 32
        var start = max(0, range.location - radius)
        if start > 0, start < range.location {
            start = min(text.rangeOfComposedCharacterSequence(at: start).location, range.location)
        }
        let matchEnd = NSMaxRange(range)
        var end = min(text.length, matchEnd + radius)
        if end > matchEnd, end < text.length {
            end = max(NSMaxRange(text.rangeOfComposedCharacterSequence(at: end - 1)), matchEnd)
        }

        let before = (start > 0 ? "…" : "") + Self.visibleBreaks(
            text.substring(with: NSRange(location: start, length: range.location - start))
        )
        let match = text.substring(with: range)
        let after = Self.visibleBreaks(
            text.substring(with: NSRange(location: matchEnd, length: end - matchEnd))
        ) + (end < text.length ? "…" : "")
        let beforeText = Text(verbatim: before).foregroundColor(.secondary)
        let matchText = Text(verbatim: match).bold().underline()
        let afterText = Text(verbatim: after).foregroundColor(.secondary)
        return Text("\(beforeText)\(matchText)\(afterText)")
    }

    private static func visibleBreaks(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "⏎")
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\r", with: "⏎")
    }

    private static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
    }
}
