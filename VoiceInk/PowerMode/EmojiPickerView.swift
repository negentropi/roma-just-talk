import SwiftUI
import VoiceInkCore

struct EmojiPickerView: View {
    @StateObject private var emojiManager = EmojiManager.shared
    @Binding var selectedEmoji: String
    @Binding var isPresented: Bool
    @State private var newEmojiText: String = ""
    @State private var isAddingCustomEmoji: Bool = false
    @FocusState private var isEmojiTextFieldFocused: Bool
    @State private var inputFeedbackMessage: String = ""
    @State private var showingEmojiInUseAlert = false
    @State private var emojiForAlert: String? = nil
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(emojiManager.allEmojis, id: \.self) { emoji in
                        EmojiButton(
                            emoji: emoji,
                            isSelected: selectedEmoji == emoji,
                            isCustom: emojiManager.isCustomEmoji(emoji),
                            removeAction: {
                                attemptToRemoveCustomEmoji(emoji)
                            }
                        ) {
                            selectedEmoji = emoji
                            inputFeedbackMessage = ""
                            isPresented = false
                        }
                    }

                    AddEmojiButton {
                        isAddingCustomEmoji.toggle()
                        newEmojiText = ""
                        inputFeedbackMessage = ""
                        if isAddingCustomEmoji {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isEmojiTextFieldFocused = true
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            if isAddingCustomEmoji {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(VoiceInkPowerModeEmojiInputPresentation.customEmojiFieldPlaceholder, text: $newEmojiText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 70)
                            .focused($isEmojiTextFieldFocused)
                            .onChange(of: newEmojiText) { _, newValue in
                                inputFeedbackMessage = ""
                                let cleaned = VoiceInkPowerModeEmojiCatalog.firstValidEmojiCharacter(in: newValue)
                                if newEmojiText != cleaned {
                                    newEmojiText = cleaned
                                }
                                if !newEmojiText.isEmpty && emojiManager.allEmojis.contains(newEmojiText) {
                                    inputFeedbackMessage = VoiceInkPowerModeEmojiInputPresentation.duplicateMessage
                                } else if !newEmojiText.isEmpty && !VoiceInkPowerModeEmojiCatalog.isValidEmoji(newEmojiText) {
                                    inputFeedbackMessage = VoiceInkPowerModeEmojiInputPresentation.invalidPreviewMessage
                                } else {
                                    inputFeedbackMessage = ""
                                }
                            }
                            .onSubmit(attemptAddCustomEmoji)

                        Button(VoiceInkPowerModeEmojiInputPresentation.addButtonTitle) {
                            attemptAddCustomEmoji()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!emojiManager.canAddCustomEmoji(newEmojiText))

                        Button(VoiceInkPowerModeEmojiInputPresentation.cancelButtonTitle) {
                            isAddingCustomEmoji = false
                            newEmojiText = ""
                            inputFeedbackMessage = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    if !inputFeedbackMessage.isEmpty {
                        Text(inputFeedbackMessage)
                            .font(.caption)
                            .foregroundColor(VoiceInkPowerModeEmojiInputPresentation.isErrorMessage(inputFeedbackMessage) ? .red : .secondary)
                            .transition(.opacity)
                    }
                    Text(VoiceInkPowerModeEmojiInputPresentation.tipText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.horizontal)
                .padding(.bottom, 5)
            }
        }
        .padding()
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 320, minHeight: 150, idealHeight: 280, maxHeight: 350)
        .alert(
            VoiceInkPowerModeEmojiInputPresentation.inUseAlertTitle,
            isPresented: $showingEmojiInUseAlert,
            presenting: emojiForAlert
        ) { emojiStr in
            let presentation = VoiceInkPowerModeEmojiInputPresentation.inUseAlert(emoji: emojiStr)
            Button(presentation.buttonTitle, role: .cancel) { }
        } message: { emojiStr in
            Text(VoiceInkPowerModeEmojiInputPresentation.inUseAlert(emoji: emojiStr).message)
        }
    }

    private func attemptAddCustomEmoji() {
        let trimmedEmoji = newEmojiText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch emojiManager.addCustomEmoji(trimmedEmoji) {
        case .added(let emoji, _):
            selectedEmoji = emoji
            inputFeedbackMessage = ""
            isAddingCustomEmoji = false
            newEmojiText = ""
        case .empty:
            inputFeedbackMessage = VoiceInkPowerModeEmojiInputPresentation.emptySubmitMessage
        case .invalid:
            inputFeedbackMessage = VoiceInkPowerModeEmojiInputPresentation.invalidSubmitMessage
        case .duplicate:
            inputFeedbackMessage = VoiceInkPowerModeEmojiInputPresentation.duplicateMessage
        }
    }

    private func attemptToRemoveCustomEmoji(_ emojiToRemove: String) {
        guard emojiManager.isCustomEmoji(emojiToRemove) else { return }

        if PowerModeManager.shared.configurations.containsPowerModeEmoji(emojiToRemove) {
            emojiForAlert = emojiToRemove
            showingEmojiInUseAlert = true
        } else {
            if emojiManager.removeCustomEmoji(emojiToRemove) {
                if selectedEmoji == emojiToRemove {
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let isCustom: Bool
    let removeAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: selectAction) {
                Text(emoji)
                    .font(.largeTitle)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)

            if isCustom {
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.red)
                        .font(.caption2)
                        .background(Circle().fill(Color.white.opacity(0.8)))
                }
                .buttonStyle(.borderless)
                .offset(x: 6, y: -6)
            }
        }
    }
}

private struct AddEmojiButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(VoiceInkPowerModeEmojiInputPresentation.addEmojiAccessibilityLabel, systemImage: "plus.circle.fill")
                .font(.title2)
                .labelStyle(.iconOnly)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(VoiceInkPowerModeEmojiInputPresentation.addCustomEmojiHelpText)
    }
}

#if DEBUG
struct EmojiPickerView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiPickerView(
            selectedEmoji: .constant("😀"),
            isPresented: .constant(true)
        )
        .environmentObject(EmojiManager.shared)
    }
}
#endif
