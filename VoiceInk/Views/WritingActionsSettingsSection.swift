import SwiftUI
import VoiceInkCore

struct WritingActionsSettingsSection: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    // isConfigured reads AIService; observing it refreshes the status when the provider or key changes.
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @State private var preferences = VoiceInkWritingActionPreferences.load()
    @State private var saveFailure: String?
    @State private var isAddingTarget = false

    var body: some View {
        Group {
            Section {
                providerStatus
                ForEach(VoiceInkWritingActionKind.allCases) { kind in
                    LabeledContent {
                        ShortcutRecorder(action: Self.shortcutAction(for: kind)) {
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    } label: {
                        Text(kind.title)
                        Text(summary(for: kind))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("writingActions.shortcut.\(kind.rawValue)")
                }
            } header: {
                Text("Writing Actions")
            } footer: {
                Text("Press a shortcut to start recording, then press the same shortcut again to finish. Each recording keeps the action and translation target it started with, so a new target applies from the next recording. History keeps the transcript and the result. If a request fails, nothing is inserted and your text stays as it was. Writing actions never expand snippets.")
                    .settingsDescription()
            }

            Section {
                if preferences.targetLanguages.isEmpty {
                    Text("Add a language to translate into.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(preferences.targetLanguages.enumerated()), id: \.element) { index, code in
                    targetRow(code: code, index: index)
                }
                HStack {
                    Button("Add Language…", systemImage: "plus") { isAddingTarget = true }
                        .disabled(availableTargets.isEmpty)
                        .accessibilityIdentifier("writingActions.target.add")
                        .popover(isPresented: $isAddingTarget, arrowEdge: .bottom) {
                            TargetLanguageSearchList(options: availableTargets, onSelect: add)
                        }
                    Spacer()
                }
                if let saveFailure {
                    Label(saveFailure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("writingActions.error")
                }
            } header: {
                Text("Translation Target")
            } footer: {
                Text("Translate dictation writes in the checked language, whatever language you speak and whatever transcription language is set. Keep the languages you switch between here.")
                    .settingsDescription()
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .writingFeaturesDidChange)) { _ in reload() }
    }

    @ViewBuilder
    private var providerStatus: some View {
        if enhancementService.isConfigured {
            Label {
                Text("Uses the AI provider above, even when Enhancement is off.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .accessibilityIdentifier("writingActions.providerStatus")
        } else {
            Label {
                Text("Set up an AI provider above first. Writing actions need one even when Enhancement is off.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .accessibilityIdentifier("writingActions.providerStatus")
        }
    }

    private func targetRow(code: String, index: Int) -> some View {
        let name = Self.name(for: code)
        let isSelected = code == preferences.selectedTargetLanguage
        let count = preferences.targetLanguages.count

        return HStack(spacing: 10) {
            Button {
                select(code)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Text(name)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected {
                        Text("Current target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityHint(isSelected ? "" : "Translate into \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("writingActions.target.\(code).select")

            Button {
                move(code, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move up")
            .accessibilityLabel("Move \(name) up")
            .accessibilityIdentifier("writingActions.target.\(code).moveUp")

            Button {
                move(code, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == count - 1)
            .help("Move down")
            .accessibilityLabel("Move \(name) down")
            .accessibilityIdentifier("writingActions.target.\(code).moveDown")

            Button {
                remove(code)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(count <= 1)
            .help(count <= 1 ? "Keep at least one target language." : "Remove \(name)")
            .accessibilityLabel("Remove \(name)")
            .accessibilityIdentifier("writingActions.target.\(code).remove")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("writingActions.target.\(code)")
    }

    private var availableTargets: [VoiceInkLanguageOption] {
        let chosen = Set(preferences.targetLanguages)
        return VoiceInkWritingActionPreferences.targetLanguageOptions.filter { !chosen.contains($0.code) }
    }

    private func summary(for kind: VoiceInkWritingActionKind) -> String {
        switch kind {
        case .translate:
            let target = Self.name(for: preferences.selectedTargetLanguage)
            return preferences.selectedTargetLanguage.isEmpty
                ? "Add a translation target below first."
                : "Speak in any language. The \(target) translation is inserted."
        case .rewriteSelection:
            return "Select text in any app, then say how to change it. The result replaces the selection."
        case .draft:
            return "Describe what to write. The finished draft is inserted where you're typing."
        }
    }

    private static func shortcutAction(for kind: VoiceInkWritingActionKind) -> ShortcutAction {
        switch kind {
        case .translate: .translateRecording
        case .rewriteSelection: .rewriteSelectionRecording
        case .draft: .draftRecording
        }
    }

    private static func name(for code: String) -> String {
        VoiceInkWritingActionPreferences.targetLanguageName(for: code) ?? code
    }

    private func reload() {
        preferences = VoiceInkWritingActionPreferences.load()
    }

    /// Each change applies to the stored preferences, so edits from another window are kept.
    private func update(_ change: (inout VoiceInkWritingActionPreferences) -> Void) {
        var next = VoiceInkWritingActionPreferences.load()
        change(&next)
        do {
            try next.save()
            preferences = VoiceInkWritingActionPreferences.load()
            saveFailure = nil
            NotificationCenter.default.post(name: .writingFeaturesDidChange, object: nil)
        } catch {
            preferences = VoiceInkWritingActionPreferences.load()
            saveFailure = "Your change wasn't saved. \(error.localizedDescription)"
        }
    }

    private func select(_ code: String) {
        update { draft in
            guard draft.targetLanguages.contains(code) else { return }
            draft.selectedTargetLanguage = code
        }
    }

    private func add(_ code: String) {
        isAddingTarget = false
        update { draft in
            guard !draft.targetLanguages.contains(code) else { return }
            draft.targetLanguages.append(code)
        }
    }

    private func move(_ code: String, by offset: Int) {
        update { draft in
            guard let index = draft.targetLanguages.firstIndex(of: code),
                  draft.targetLanguages.indices.contains(index + offset) else { return }
            draft.targetLanguages.swapAt(index, index + offset)
        }
    }

    private func remove(_ code: String) {
        update { draft in
            guard draft.targetLanguages.count > 1,
                  let index = draft.targetLanguages.firstIndex(of: code) else { return }
            draft.targetLanguages.remove(at: index)
            if draft.selectedTargetLanguage == code {
                draft.selectedTargetLanguage = draft.targetLanguages[min(index, draft.targetLanguages.count - 1)]
            }
        }
    }
}

private struct TargetLanguageSearchList: View {
    let options: [VoiceInkLanguageOption]
    let onSelect: (String) -> Void
    @State private var query = ""

    private var matches: [VoiceInkLanguageOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return options }
        return options.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.code.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search languages", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("writingActions.target.search")

            List(matches) { option in
                Button {
                    onSelect(option.code)
                } label: {
                    Text(option.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("writingActions.target.option.\(option.code)")
            }
            .listStyle(.inset)
            .overlay {
                if matches.isEmpty {
                    Text("No matching languages")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 280, height: 340)
    }
}
