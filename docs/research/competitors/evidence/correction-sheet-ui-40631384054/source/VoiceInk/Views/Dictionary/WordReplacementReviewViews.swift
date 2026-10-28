import AppKit
import Combine
import SwiftUI
import SwiftData
import VoiceInkCore

// Shared presentation for word replacement library state. Matching, conflict detection,
// persistence and revision checks stay in DictionaryService / HistoryCorrectionApprovalService.

/// A visible, typed word replacement failure. Conflicts and stale revisions keep complete records for review.
struct WordReplacementIssue: Equatable {
    struct Revision: Equatable {
        let expected: VoiceInkWordReplacementRecord
        let current: VoiceInkWordReplacementRecord
    }

    let message: String
    let conflicts: [VoiceInkWordReplacementLibraryConflict]
    let revision: Revision?

    init(
        message: String,
        conflicts: [VoiceInkWordReplacementLibraryConflict] = [],
        revision: Revision? = nil
    ) {
        self.message = message
        self.conflicts = conflicts
        self.revision = revision
    }

    init(_ error: Error) {
        if let conflict = error as? DictionaryService.LibraryConflictError {
            self.init(message: conflict.localizedDescription, conflicts: conflict.conflicts)
        } else if let stale = error as? DictionaryService.LibraryRevisionError {
            self.init(
                message: stale.localizedDescription,
                revision: Revision(expected: stale.expected, current: stale.current)
            )
        } else if let record = error as? VoiceInkWordReplacementRecordError {
            switch record {
            case .blankOriginalText: self.init(message: "The text to replace is blank.")
            case .blankReplacementText: self.init(message: "The replacement text is blank.")
            case .invalidDate: self.init(message: "The entry’s date added is invalid.")
            }
        } else {
            self.init(message: error.localizedDescription)
        }
    }
}

extension VoiceInkWordReplacementMatchingKind {
    var dictionaryReviewTitle: String {
        switch self {
        case .literal: "Literal phrase"
        case .legacyCommaAlternatives: "Comma alternatives"
        }
    }

    /// Literal entries are one phrase (commas kept); future matching ignores letter case.
    var dictionaryReviewHelp: String {
        switch self {
        case .literal: "One phrase, including commas. Matching ignores letter case."
        case .legacyCommaAlternatives: "Commas separate alternative words or phrases."
        }
    }
}

extension VoiceInkWordReplacementProvenance {
    /// History's "Original" variant is processed text before AI enhancement, never raw recognition.
    var dictionaryReviewTitle: String {
        "From History · \(HistoryTextVariant(sourceVariant).title)"
    }
}

/// Message plus, for library conflicts, every incoming/existing record pair, and for a stale
/// edit, the record as opened beside the record now saved.
struct WordReplacementIssueView: View {
    let issue: WordReplacementIssue
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: issue.message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(identifier).message")

            if !issue.conflicts.isEmpty {
                WordReplacementConflictReview(conflicts: issue.conflicts, identifier: "\(identifier).conflicts")
            }

            if let revision = issue.revision {
                WordReplacementRevisionReview(revision: revision, identifier: "\(identifier).revision")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Read-only review of a stale edit. Nothing was saved; the editor must be closed and reopened.
struct WordReplacementRevisionReview: View {
    let revision: WordReplacementIssue.Revision
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing was saved. Close this editor and open the entry again to edit its current values.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            WordReplacementRecordSummary(
                title: "When you opened it",
                record: revision.expected,
                identifier: "\(identifier).expected"
            )
            WordReplacementRecordSummary(
                title: "Saved now",
                record: revision.current,
                identifier: "\(identifier).current"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Read-only review of library conflicts. It offers no overwrite or merge action.
struct WordReplacementConflictReview: View {
    let conflicts: [VoiceInkWordReplacementLibraryConflict]
    let identifier: String
    var guidance = "Nothing was saved and no entry was changed. Change this replacement, or edit or delete the saved entry in Dictionary."
    var incomingTitle = "Proposed"
    var existingTitle = "Already saved"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).guidance")

            // Offsets identify conflicts: one incoming record can conflict with several saved ones.
            ForEach(Array(conflicts.enumerated()), id: \.offset) { index, conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Conflict \(index + 1) of \(conflicts.count): \(reasonText(conflict.reason))")
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("\(identifier).\(index).reason")

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            summaries(for: conflict, index: index)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            summaries(for: conflict, index: index)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(identifier).\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func summaries(for conflict: VoiceInkWordReplacementLibraryConflict, index: Int) -> some View {
        WordReplacementRecordSummary(
            title: incomingTitle,
            record: conflict.incoming,
            identifier: "\(identifier).\(index).incoming"
        )
        WordReplacementRecordSummary(
            title: existingTitle,
            record: conflict.existing,
            identifier: "\(identifier).\(index).existing"
        )
    }

    private func reasonText(_ reason: VoiceInkWordReplacementLibraryConflict.Reason) -> String {
        switch reason {
        case .identity: "same entry ID with different contents"
        case .source: "the phrase overlaps a saved entry"
        }
    }
}

/// Every field of one complete record, with source/output shown verbatim.
struct WordReplacementRecordSummary: View {
    let title: String
    let record: VoiceInkWordReplacementRecord
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            exactText(label: "Replace", value: record.originalText, id: "original")
            exactText(label: "With", value: record.replacementText, id: "replacement")

            metadata(label: "Kind", value: record.matchingKind.dictionaryReviewTitle, id: "kind")
                .help(record.matchingKind.dictionaryReviewHelp)
            metadata(label: "State", value: record.isEnabled ? "On" : "Off", id: "enabled")
            metadata(
                label: "Added",
                value: record.dateAdded.formatted(date: .abbreviated, time: .standard),
                id: "dateAdded"
            )
            .help(record.dateAdded.ISO8601Format())
            metadata(label: "ID", value: record.id.uuidString, id: "id", monospaced: true)
            if let provenance = record.provenance {
                metadata(label: "Source", value: provenance.dictionaryReviewTitle, id: "provenance")
                metadata(
                    label: "Transcript",
                    value: provenance.sourceTranscriptionID.uuidString,
                    id: "sourceTranscription",
                    monospaced: true
                )
            } else {
                metadata(label: "Source", value: "Added manually", id: "provenance")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func exactText(label: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Monospaced and boxed so leading/trailing spaces and line breaks stay visible.
            Text(verbatim: value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
                .accessibilityIdentifier("\(identifier).\(id)")
        }
    }

    private func metadata(label: String, value: String, id: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(verbatim: value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(identifier).\(id)")
    }
}

/// Approved-correction source status. Only a successful check returning false means deleted;
/// a failed check is shown as unknown.
struct WordReplacementSourceStatus: View {
    let provenance: VoiceInkWordReplacementProvenance
    let identifier: String

    @Environment(\.modelContext) private var modelContext
    @State private var availability: Availability = .checking

    private enum Availability: Equatable {
        case checking
        case available
        case missing
        case unknown(String)
    }

    /// The Core provenance type is not Hashable; this presentation key is.
    private struct Key: Hashable {
        let origin: VoiceInkWordReplacementApprovalOrigin
        let transcriptionID: UUID
        let variant: VoiceInkWordReplacementSourceVariant
    }

    private var key: Key {
        Key(
            origin: provenance.origin,
            transcriptionID: provenance.sourceTranscriptionID,
            variant: provenance.sourceVariant
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(verbatim: statusText)
        }
        .font(.caption)
        .foregroundStyle(availability == .available || availability == .checking ? Color.secondary : Color.orange)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(accessibilityState)
        // Runs on every appearance and whenever the provenance changes.
        .task(id: key) { refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: .transcriptionDeleted).receive(on: DispatchQueue.main)
        ) { _ in refresh() }
    }

    private var statusText: String {
        switch availability {
        case .checking, .available: provenance.dictionaryReviewTitle
        case .missing: "\(provenance.dictionaryReviewTitle) · source deleted"
        case .unknown: "\(provenance.dictionaryReviewTitle) · source status unknown"
        }
    }

    private var systemImage: String {
        switch availability {
        case .checking, .available: "clock.arrow.circlepath"
        case .missing: "trash.slash"
        case .unknown: "questionmark.circle"
        }
    }

    private var accessibilityState: String {
        switch availability {
        case .checking: "checking"
        case .available: "source available"
        case .missing: "source deleted"
        case .unknown: "source status unknown"
        }
    }

    private var helpText: String {
        let transcript = "Transcript \(provenance.sourceTranscriptionID.uuidString)"
        switch availability {
        case .checking, .available:
            return "Approved from History. \(transcript)."
        case .missing:
            return "Approved from History. \(transcript) was deleted; the saved pair is kept."
        case .unknown(let message):
            return "Couldn’t check the source transcript: \(message)"
        }
    }

    private func refresh() {
        do {
            availability = try HistoryCorrectionApprovalService.sourceExists(for: provenance, using: modelContext)
                ? .available : .missing
        } catch {
            availability = .unknown(error.localizedDescription)
        }
    }
}

// MARK: - Unsupported stored rows

/// Raw stored columns of a row the throwing `record` getter rejected. Diagnostics only:
/// never used for valid-row display, sorting, search or edit values.
struct WordReplacementStoredDiagnostics: Equatable {
    let matchingKind: String?
    let originalText: String
    let replacementText: String
    let literalOriginalText: String?
    let literalReplacementText: String?
    let approvalOrigin: String?
    let sourceTranscriptionID: UUID?
    let sourceVariant: String?

    init(entry: WordReplacement) {
        matchingKind = entry.matchingKindRawValue
        originalText = entry.originalText
        replacementText = entry.replacementText
        literalOriginalText = entry.literalOriginalText
        literalReplacementText = entry.literalReplacementText
        approvalOrigin = entry.approvalOriginRawValue
        sourceTranscriptionID = entry.sourceTranscriptionID
        sourceVariant = entry.sourceVariantRawValue
    }
}

/// Collapsed by default, so raw text is not rendered until the user asks for it.
struct WordReplacementRawDiagnosticsView: View {
    let diagnostics: WordReplacementStoredDiagnostics
    let identifier: String

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exactly as stored. RJT doesn’t use these values while the entry is unsupported.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                field("matchingKind", diagnostics.matchingKind)
                field("originalText (legacy)", diagnostics.originalText)
                field("replacementText (legacy)", diagnostics.replacementText)
                field("literalOriginalText", diagnostics.literalOriginalText)
                field("literalReplacementText", diagnostics.literalReplacementText)
                field("approvalOrigin", diagnostics.approvalOrigin)
                field("sourceTranscriptionID", diagnostics.sourceTranscriptionID?.uuidString)
                field("sourceVariant", diagnostics.sourceVariant)
            }
            .padding(.top, 4)
        } label: {
            Text("Raw stored data (diagnostics)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func field(_ name: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: name)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)
            if let value, !value.isEmpty {
                Text(verbatim: value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
            } else {
                // Markers are styled apart from stored text so they can't be mistaken for it.
                Text(value == nil ? "not set" : "empty")
                    .font(.caption2.italic())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(identifier).\(name.split(separator: " ").first.map(String.init) ?? name)")
    }
}

// MARK: - Exact literal input

/// Plain NSTextView for literal phrase/output input. Every automatic substitution and text
/// check is off. Unlike `String ==`, which treats canonically equivalent spellings (NFC/NFD) as
/// equal, programmatic updates compare UTF-8 and UTF-16 code units.
struct ExactLiteralTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.smartInsertDeleteEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        guard !Self.sameCodeUnits(textView.string, text) else { return }
        textView.string = text
    }

    static func sameCodeUnits(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        /// Always forwards the view's string, so the binding setter sees every edit,
        /// including one that only changes Unicode normalization.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Settings import conflicts

/// Native, close-only review of library conflicts that stopped a settings import.
@MainActor
enum WordReplacementImportConflictAlert {
    static let identifier = "settings.import.wordReplacementConflicts"
    static let message = "Import stopped. Nothing was imported. Review the conflicting replacements. No rule was overwritten."

    static func run(title: String, conflicts: [VoiceInkWordReplacementLibraryConflict]) {
        let size = NSSize(width: 620, height: 420)
        let content = ScrollView {
            WordReplacementConflictReview(
                conflicts: conflicts,
                identifier: "\(identifier).content",
                guidance: "\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s"). Change the backup file, or edit or delete the saved entry in Dictionary, then import again.",
                incomingTitle: "In backup file",
                existingTitle: "Already saved"
            )
            .padding(12)
        }
        .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.setAccessibilityIdentifier("\(identifier).scroll")

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.accessoryView = hostingView
        let close = alert.addButton(withTitle: "Close")
        close.setAccessibilityIdentifier("\(identifier).close")
        alert.window.setAccessibilityIdentifier(identifier)
        alert.runModal()
    }
}
