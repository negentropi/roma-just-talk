import AppKit
import SwiftUI
import VoiceInkCore

struct SpokenSnippetEditorTarget: Identifiable {
    let id: UUID
    let original: VoiceInkSpokenSnippet?

    static func new() -> Self { Self(id: UUID(), original: nil) }
    static func edit(_ snippet: VoiceInkSpokenSnippet) -> Self { Self(id: snippet.id, original: snippet) }
}

struct SpokenSnippetEditorSheet: View {
    let target: SpokenSnippetEditorTarget
    let library: [VoiceInkSpokenSnippet]
    /// Saves the draft only if the stored snippet still matches `replacing`; nil means it must not exist yet.
    let onSave: (_ snippet: VoiceInkSpokenSnippet, _ replacing: VoiceInkSpokenSnippet?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var base: VoiceInkSpokenSnippet?
    @State private var trigger: String
    @State private var content: String
    @State private var enabled: Bool
    @State private var hasAttemptedSave = false
    @State private var hasSaved = false
    @State private var saveError: String?
    @State private var isConfirmingDiscard = false

    init(
        target: SpokenSnippetEditorTarget,
        library: [VoiceInkSpokenSnippet],
        onSave: @escaping (_ snippet: VoiceInkSpokenSnippet, _ replacing: VoiceInkSpokenSnippet?) throws -> Void
    ) {
        self.target = target
        self.library = library
        self.onSave = onSave
        _base = State(initialValue: target.original)
        _trigger = State(initialValue: target.original?.trigger ?? "")
        _content = State(initialValue: target.original?.content ?? "")
        _enabled = State(initialValue: target.original?.enabled ?? true)
    }

    private enum Conflict {
        case changed(VoiceInkSpokenSnippet)
        case deleted
    }

    private var stored: VoiceInkSpokenSnippet? {
        library.first { $0.id == target.id }
    }

    private var conflict: Conflict? {
        guard !hasSaved, stored != base else { return nil }
        return stored.map(Conflict.changed) ?? .deleted
    }

    private var candidate: VoiceInkSpokenSnippet {
        VoiceInkSpokenSnippet(id: target.id, trigger: trigger, content: content, enabled: enabled)
    }

    private var isDirty: Bool {
        candidate != (base ?? VoiceInkSpokenSnippet(id: target.id, trigger: "", content: ""))
    }

    private var visibleIssue: VoiceInkSpokenSnippetValidationIssue? {
        guard let issue = VoiceInkSpokenSnippets.validate(candidate, among: library) else { return nil }
        switch issue {
        case .emptyTrigger, .emptyContent:
            return hasAttemptedSave ? issue : nil
        default:
            return issue
        }
    }

    private func message(for field: Field) -> String? {
        guard let visibleIssue, Field(visibleIssue) == field else { return nil }
        return visibleIssue.localizedDescription
    }

    private var footerMessage: String? {
        message(for: .library) ?? saveError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(target.original == nil ? "New Snippet" : "Edit Snippet")
                .font(.title3.weight(.semibold))
                .padding([.horizontal, .top], 20)

            if let conflict {
                conflictBanner(conflict)
                    .padding([.horizontal, .top], 20)
            }

            Form {
                Section {
                    TextField("Trigger", text: $trigger, prompt: Text("my address"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("snippets.editor.trigger")
                    fieldStatus(
                        message: message(for: .trigger),
                        count: VoiceInkSpokenSnippets.normalizedTrigger(trigger).count,
                        limit: VoiceInkSpokenSnippets.maximumTriggerCharacters,
                        identifier: "snippets.editor.triggerError"
                    )
                } footer: {
                    Text("Say this phrase while dictating. Letter case and extra spaces don't matter.")
                        .settingsDescription()
                }

                Section {
                    LiteralTextEditor(
                        text: $content,
                        accessibilityLabel: "Inserted text",
                        accessibilityIdentifier: "snippets.editor.content"
                    )
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                    fieldStatus(
                        message: message(for: .content),
                        count: content.count,
                        limit: VoiceInkSpokenSnippets.maximumContentCharacters,
                        identifier: "snippets.editor.contentError"
                    )
                } header: {
                    Text("Inserted Text")
                } footer: {
                    Text("Inserted exactly as written, including line breaks and spaces.")
                        .settingsDescription()
                }

                Section {
                    Toggle("Use this snippet", isOn: $enabled)
                        .accessibilityIdentifier("snippets.editor.enabled")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack(spacing: 12) {
                if let footerMessage {
                    Label(footerMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .accessibilityIdentifier("snippets.editor.error")
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("snippets.editor.cancel")
                Button(target.original == nil ? "Add Snippet" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(conflict != nil)
                    .accessibilityIdentifier("snippets.editor.save")
            }
            .padding(16)
        }
        .frame(width: 540, height: 600)
        .interactiveDismissDisabled(isDirty)
        .onChange(of: candidate) { _, _ in saveError = nil }
        .onChange(of: stored) { _, latest in
            if let latest, base != nil, !isDirty { adopt(latest) }
        }
        .confirmationDialog("Discard changes to this snippet?", isPresented: $isConfirmingDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func fieldStatus(message: String?, count: Int, limit: Int, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let message {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(identifier)
            }
            Spacer()
            Text("\(count)/\(limit)")
                .monospacedDigit()
                .foregroundStyle(count > limit ? Color.red : Color.secondary)
                .accessibilityLabel("\(count) of \(limit) characters")
        }
        .font(.caption)
    }

    private func conflictBanner(_ conflict: Conflict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                switch conflict {
                case .changed(let latest):
                    Text("This snippet was changed in another window. Your edits are kept until you choose.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Use Latest Version") { adopt(latest) }
                            .accessibilityIdentifier("snippets.editor.conflict.useLatest")
                        Button("Keep My Edits") { base = latest }
                            .help("Saving will replace the other window's version.")
                            .accessibilityIdentifier("snippets.editor.conflict.keepMine")
                    }
                case .deleted:
                    Text("This snippet was deleted in another window. Your edits are kept until you choose.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Close Without Saving") { dismiss() }
                            .accessibilityIdentifier("snippets.editor.conflict.close")
                        Button("Keep My Edits") { base = nil }
                            .help("Saving will add this snippet back.")
                            .accessibilityIdentifier("snippets.editor.conflict.keepMine")
                    }
                }
            }
            .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snippets.editor.conflict")
    }

    private func adopt(_ latest: VoiceInkSpokenSnippet) {
        base = latest
        trigger = latest.trigger
        content = latest.content
        enabled = latest.enabled
    }

    private func cancel() {
        if isDirty {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        hasAttemptedSave = true
        saveError = nil
        guard conflict == nil, VoiceInkSpokenSnippets.validate(candidate, among: library) == nil else { return }
        do {
            try onSave(candidate, base)
            hasSaved = true
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private enum Field {
        case trigger, content, library

        init(_ issue: VoiceInkSpokenSnippetValidationIssue) {
            switch issue {
            case .emptyTrigger, .triggerTooLong, .duplicateTrigger: self = .trigger
            case .emptyContent, .contentTooLong: self = .content
            case .duplicateIdentifier, .tooManySnippets: self = .library
            }
        }
    }
}

/// The CSV rows compared with the library as it is now, so the preview and the
/// merge always see the same conflicts.
private struct SpokenSnippetImportReview {
    struct Row: Identifiable {
        let id: Int
        let snippet: VoiceInkSpokenSnippet
        let current: VoiceInkSpokenSnippet?
        let repeatsEarlierRow: Bool

        var isConflict: Bool { current != nil || repeatsEarlierRow }
    }

    let preview: VoiceInkSpokenSnippetImportPreview
    let rows: [Row]

    init(csv: String, library: [VoiceInkSpokenSnippet]) {
        preview = VoiceInkSpokenSnippets.previewImport(csv, existing: library)
        let current = Dictionary(library.map { (Self.key($0.trigger), $0) }) { first, _ in first }
        var seen = Set<String>()
        rows = preview.snippets.enumerated().map { offset, snippet in
            let key = Self.key(snippet.trigger)
            return Row(
                id: offset,
                snippet: snippet,
                current: current[key],
                repeatsEarlierRow: !seen.insert(key).inserted
            )
        }
    }

    private static func key(_ trigger: String) -> String {
        VoiceInkSpokenSnippets.normalizedTrigger(trigger)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct SpokenSnippetImportSheet: View {
    let session: SpokenSnippetImportSession
    let library: [VoiceInkSpokenSnippet]
    let onImport: (VoiceInkSpokenSnippetConflictPolicy) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var review: SpokenSnippetImportReview
    @State private var policy: VoiceInkSpokenSnippetConflictPolicy?
    @State private var importError: String?

    init(
        session: SpokenSnippetImportSession,
        library: [VoiceInkSpokenSnippet],
        onImport: @escaping (VoiceInkSpokenSnippetConflictPolicy) throws -> Void
    ) {
        self.session = session
        self.library = library
        self.onImport = onImport
        _review = State(initialValue: SpokenSnippetImportReview(csv: session.csv, library: library))
    }

    private var preview: VoiceInkSpokenSnippetImportPreview { review.preview }
    private var hasConflicts: Bool { !preview.duplicateTriggers.isEmpty }
    private var canConfirm: Bool { preview.canImport && (!hasConflicts || policy != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Snippets")
                    .font(.title3.weight(.semibold))
                Text(session.fileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            summary

            if !preview.rowIssues.isEmpty {
                rowIssues
            }

            if review.rows.isEmpty {
                Spacer(minLength: 0)
            } else {
                rowsPreview
            }

            if preview.canImport && hasConflicts {
                conflicts
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .help(importError)
                    .accessibilityIdentifier("snippets.import.error")
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("snippets.import.cancel")
                Button("Import", action: performImport)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("snippets.import.confirm")
            }
        }
        .padding(20)
        .frame(width: 640, height: 620)
        .onChange(of: policy) { _, _ in importError = nil }
        .onChange(of: library) { _, latest in
            review = SpokenSnippetImportReview(csv: session.csv, library: latest)
        }
        .accessibilityIdentifier("snippets.import.sheet")
    }

    @ViewBuilder
    private var summary: some View {
        if preview.canImport {
            Label {
                Text("^[\(preview.snippets.count) snippet](inflect: true) ready to import.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .accessibilityIdentifier("snippets.import.summary")
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This file can't be imported yet.")
                    Text("Nothing has changed. Fix these rows in the CSV, then import it again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
            .accessibilityIdentifier("snippets.import.summary")
        }
    }

    private var rowIssues: some View {
        GroupBox {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(preview.rowIssues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Row \(issue.row)")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .frame(minWidth: 56, alignment: .leading)
                            Text(issue.message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .frame(maxHeight: review.rows.isEmpty ? 260 : 110)
        }
        .accessibilityIdentifier("snippets.import.issues")
    }

    private var rowsPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preview.canImport ? "Rows in this file" : "Rows without problems")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(review.rows) { row in
                        SpokenSnippetImportRowView(row: row, outcome: outcome(for: row))
                            .padding(.horizontal, 8)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            }
            Text("Expand a row to see its full text exactly as it will be saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("snippets.import.rows")
    }

    private func outcome(for row: SpokenSnippetImportReview.Row) -> SpokenSnippetImportRowView.Outcome {
        guard row.isConflict else { return .add }
        switch policy {
        case nil: return .undecided
        case .keepExisting: return .skip
        case .replaceExisting: return .replace
        case .reject: return .block
        }
    }

    private var conflicts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("^[\(preview.duplicateTriggers.count) trigger](inflect: true) already in your library or repeated in this file. Expand a marked row to compare its current and imported text.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("snippets.import.duplicates")

            Picker("When a trigger is already in use", selection: $policy) {
                Text("Keep the existing snippet").tag(Optional(VoiceInkSpokenSnippetConflictPolicy.keepExisting))
                Text("Replace it with the imported row").tag(Optional(VoiceInkSpokenSnippetConflictPolicy.replaceExisting))
                Text("Import nothing").tag(Optional(VoiceInkSpokenSnippetConflictPolicy.reject))
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("snippets.import.policy")

            Text("Repeated rows in the file follow the same choice, in row order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func performImport() {
        importError = nil
        do {
            try onImport(policy ?? .reject)
            dismiss()
        } catch {
            importError = "\(error.localizedDescription) Nothing was imported."
        }
    }
}

private struct SpokenSnippetImportRowView: View {
    enum Outcome {
        case add, undecided, skip, replace, block
    }

    let row: SpokenSnippetImportReview.Row
    let outcome: Outcome
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let current = row.current {
                    literalText("In your library", current)
                    literalText("In this file", row.snippet)
                } else {
                    literalText(nil, row.snippet)
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.snippet.trigger)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(row.snippet.content)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.snippet.enabled ? "On" : "Off")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(row.snippet.enabled ? "Enabled" : "Turned off")
                badge
            }
            .font(.callout)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("snippets.import.row.\(row.id)")
    }

    private var badge: some View {
        let (title, color): (String, Color) = switch outcome {
        case .add: ("New", .green)
        case .undecided: (row.current != nil ? "Trigger in use" : "Repeated in file", .orange)
        case .skip: ("Skipped", .secondary)
        case .replace: (row.current != nil ? "Replaces current" : "Replaces earlier row", .blue)
        case .block: ("Conflict", .red)
        }
        return Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
            .fixedSize()
    }

    private func literalText(_ title: String?, _ snippet: VoiceInkSpokenSnippet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text("\(title) · \(snippet.enabled ? "On" : "Off")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: snippet.content)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
        .accessibilityElement(children: .combine)
    }
}

/// NSTextView with every automatic substitution off, so typed quotes, dashes and
/// line breaks are stored exactly as entered.
struct LiteralTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String

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
        textView.smartInsertDeleteEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
