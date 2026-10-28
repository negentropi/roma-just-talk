import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct SpokenSnippetsView: View {
    @State private var snippets: [VoiceInkSpokenSnippet] = VoiceInkSpokenSnippets.load()
    @State private var query = ""
    @State private var editorTarget: SpokenSnippetEditorTarget?
    @State private var importSession: SpokenSnippetImportSession?
    @State private var pendingDeletion: VoiceInkSpokenSnippet?
    @State private var failureMessage: String?

    private var isLibraryFull: Bool {
        snippets.count >= VoiceInkSpokenSnippets.maximumSnippetCount
    }

    private var visibleSnippets: [VoiceInkSpokenSnippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return snippets }
        return snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(needle)
                || $0.content.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            explanation
            toolbar
            if snippets.isEmpty {
                emptyState
            } else {
                library
                footer
            }
        }
        .padding()
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .writingFeaturesDidChange)) { _ in reload() }
        .sheet(item: $editorTarget) { target in
            SpokenSnippetEditorSheet(target: target, library: snippets, onSave: save)
        }
        .sheet(item: $importSession) { session in
            SpokenSnippetImportSheet(session: session, library: snippets) { policy in
                try importRows(from: session.csv, policy: policy)
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete “\($0.trigger)”?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { snippet in
            Button("Delete Snippet", role: .destructive) { delete(snippet) }
                .accessibilityIdentifier("snippets.delete.confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("snippets.delete.cancel")
        } message: { _ in
            Text("You can't undo this. Export a CSV first if you want a copy.")
        }
        .alert(
            "Snippets Not Updated",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private var explanation: some View {
        GroupBox {
            Label {
                Text("Say a trigger while dictating to insert its saved text exactly, line breaks included. Snippets never go through AI. When a dictation contains a trigger, the words around it are also inserted as transcribed, without AI enhancement, word replacements, or formatting. Translate, edit, and draft shortcuts never expand snippets.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !snippets.isEmpty {
                TextField("Search snippets", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("snippets.search")
            }

            Spacer()

            Button("Import CSV…", systemImage: "square.and.arrow.down", action: chooseImportFile)
                .help("Import snippets from a CSV file with trigger and content columns.")
                .accessibilityIdentifier("snippets.import")

            Button("Export CSV…", systemImage: "square.and.arrow.up", action: exportLibrary)
                .disabled(snippets.isEmpty)
                .help("Save every snippet to a CSV file.")
                .accessibilityIdentifier("snippets.export")

            Button("New Snippet", systemImage: "plus") {
                editorTarget = .new()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLibraryFull)
            .help(isLibraryFull ? "The library holds up to 1,000 snippets." : "Add a snippet.")
            .accessibilityIdentifier("snippets.new")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Snippets Yet", systemImage: "text.quote")
        } description: {
            Text("Add a snippet for text you type often, like an address or a sign-off, or import a CSV.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityIdentifier("snippets.empty")
    }

    private var library: some View {
        let rows = visibleSnippets
        return Group {
            if rows.isEmpty {
                Text("No snippets match “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { snippet in
                            SpokenSnippetRow(
                                snippet: snippet,
                                onToggle: { setEnabled($0, for: snippet) },
                                onEdit: { editorTarget = .edit(snippet) },
                                onDelete: { pendingDeletion = snippet }
                            )
                            if snippet.id != rows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .accessibilityIdentifier("snippets.list")
    }

    private var footer: some View {
        HStack {
            Text("CSV columns are trigger, content, and an optional enabled column set to true or false.")
            Spacer()
            Text("\(snippets.count) of 1,000")
                .monospacedDigit()
                .accessibilityIdentifier("snippets.count")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func reload() {
        snippets = VoiceInkSpokenSnippets.load()
    }

    /// Every write starts from the stored library, so changes made in another window are never lost.
    private func mutate(_ change: (inout [VoiceInkSpokenSnippet]) throws -> Void) throws {
        var library = VoiceInkSpokenSnippets.load()
        try change(&library)
        try VoiceInkSpokenSnippets.save(library)
        snippets = VoiceInkSpokenSnippets.load()
        NotificationCenter.default.post(name: .writingFeaturesDidChange, object: nil)
    }

    private func save(_ snippet: VoiceInkSpokenSnippet, replacing expected: VoiceInkSpokenSnippet?) throws {
        try mutate { library in
            let index = library.firstIndex { $0.id == snippet.id }
            guard index.map({ library[$0] }) == expected else { throw SpokenSnippetEditConflict() }
            if let index {
                library[index] = snippet
            } else {
                library.append(snippet)
            }
        }
    }

    private func importRows(from csv: String, policy: VoiceInkSpokenSnippetConflictPolicy) throws {
        try mutate { library in
            let preview = VoiceInkSpokenSnippets.previewImport(csv, existing: library)
            library = try VoiceInkSpokenSnippets.merged(preview, with: library, policy: policy)
        }
    }

    private func setEnabled(_ enabled: Bool, for snippet: VoiceInkSpokenSnippet) {
        do {
            try mutate { library in
                guard let index = library.firstIndex(where: { $0.id == snippet.id }) else { return }
                library[index].enabled = enabled
            }
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    private func delete(_ snippet: VoiceInkSpokenSnippet) {
        do {
            try mutate { library in
                guard let index = library.firstIndex(where: { $0.id == snippet.id }) else { return }
                guard library[index] == snippet else { throw SpokenSnippetEditConflict() }
                library.remove(at: index)
            }
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a UTF-8 CSV file with trigger and content columns."
        panel.prompt = "Preview Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            importSession = try SpokenSnippetImportSession(url: url)
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Snippets.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(VoiceInkSpokenSnippets.csvString(for: snippets).utf8).write(to: url, options: .atomic)
        } catch {
            failureMessage = "The CSV couldn't be saved. \(error.localizedDescription)"
        }
    }
}

private struct SpokenSnippetRow: View {
    let snippet: VoiceInkSpokenSnippet
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Enabled", isOn: Binding(get: { snippet.enabled }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Use “\(snippet.trigger)”")
                .help(snippet.enabled ? "Turn off to stop inserting this snippet." : "Turn on to insert this snippet.")
                .accessibilityIdentifier("snippets.row.toggle")

            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.trigger)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(snippet.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .opacity(snippet.enabled ? 1 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onEdit)
            .accessibilityElement(children: .combine)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit snippet")
            .accessibilityLabel("Edit “\(snippet.trigger)”")
            .accessibilityIdentifier("snippets.row.edit")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete snippet")
            .accessibilityLabel("Delete “\(snippet.trigger)”")
            .accessibilityIdentifier("snippets.row.delete")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button(snippet.enabled ? "Turn Off" : "Turn On") { onToggle(!snippet.enabled) }
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snippets.row.\(snippet.trigger)")
    }
}

struct SpokenSnippetEditConflict: LocalizedError {
    var errorDescription: String? {
        "This snippet changed in another window. Review the latest version, then try again."
    }
}

struct SpokenSnippetImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let csv: String

    private enum FileProblem: LocalizedError {
        case tooLarge
        case notUTF8

        var errorDescription: String? {
            switch self {
            case .tooLarge: "Choose a CSV file of 3 MB or less."
            case .notUTF8: "Save the CSV as UTF-8 text, then import it again."
            }
        }
    }

    init(url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= VoiceInkSpokenSnippets.maximumCSVBytes else { throw FileProblem.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= VoiceInkSpokenSnippets.maximumCSVBytes else { throw FileProblem.tooLarge }
        guard let csv = String(data: data, encoding: .utf8) else { throw FileProblem.notUTF8 }

        fileName = url.lastPathComponent
        self.csv = csv
    }
}
