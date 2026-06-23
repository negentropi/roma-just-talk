import SwiftUI
import SwiftData
import VoiceInkCore

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var editingReplacement: WordReplacement? = nil
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    @State private var sortMode: VoiceInkWordReplacementSortMode = .defaultMode
    @State private var wordReplacementDraftState = VoiceInkWordReplacementDraftState()
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
        let sortedReplacements = VoiceInkDictionaryListSortPolicy.sortedWordReplacements(
            wordReplacements,
            mode: sortMode,
            originalText: { $0.originalText },
            replacementText: { $0.replacementText }
        )
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

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                TextField(dictionaryPresentation.replacementTextPlaceholder, text: $wordReplacementDraftState.replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addReplacement() }

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
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !wordReplacements.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
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

                        Image(systemName: "arrow.right")
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
                                ReplacementRow(
                                    original: replacement.originalText,
                                    replacement: replacement.replacementText,
                                    editButtonHelp: listPresentation.editButtonHelp,
                                    removeButtonHelp: listPresentation.removeButtonHelp,
                                    onDelete: { removeReplacement(replacement) },
                                    onEdit: { editingReplacement = replacement }
                                )

                                if replacement.id != sortedReplacements.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .sheet(item: $editingReplacement) { replacement in
            EditReplacementSheet(replacement: replacement, modelContext: modelContext)
        }
        .alert(item: $alertPresentation) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }

    private func addReplacement() {
        let submission = wordReplacementDraftState.submitting(
            existingRules: wordReplacements.map(\.voiceInkRule)
        )
        DictionaryService.applyWordReplacementSubmission(
            submission,
            context: modelContext
        )
        .applyRuntimeState(
            setDraftState: { wordReplacementDraftState = $0 },
            setAlertPresentation: { alertPresentation = $0 }
        )
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)

        do {
            try modelContext.save()
            WordReplacementService.shared.invalidateCache()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertPresentation = .wordReplacement(
                message: VoiceInkDictionaryAlertPresentation.failedToRemoveWordReplacement(
                    localizedDescription: error.localizedDescription
                )
            )
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

            Image(systemName: "arrow.right")
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
    let original: String
    let replacement: String
    let editButtonHelp: String
    let removeButtonHelp: String
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(original)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            ZStack(alignment: .trailing) {
                Text(replacement)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(isEditHovered ? .accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help(editButtonHelp)
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
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleteHovered = hover
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
