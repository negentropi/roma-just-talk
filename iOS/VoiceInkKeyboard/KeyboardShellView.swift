import KeyboardKit
import SwiftUI
import UIKit

final class VoiceInkKeyboardShellState: ObservableObject {
    enum Surface: Equatable {
        case keyboard
        case clipboard
    }

    @Published var surface: Surface = .keyboard {
        didSet {
            onSurfaceChange?(surface)
        }
    }
    @Published var clipboardQuery = ""
    @Published var clipboardFilter: VoiceInkKeyboardClipboardFilter = .all

    var onSurfaceChange: ((Surface) -> Void)?
    var onSubmitSearch: (() -> Void)?

    func showKeyboard() {
        clipboardQuery = ""
        clipboardFilter = .all
        surface = .keyboard
    }

    func toggleClipboard() {
        if surface == .clipboard {
            showKeyboard()
        } else {
            surface = .clipboard
        }
    }

    func appendToClipboardQuery(_ text: String) {
        clipboardQuery.append(text)
    }

    func deleteLastClipboardQueryCharacter() {
        guard !clipboardQuery.isEmpty else { return }
        clipboardQuery.removeLast()
    }
}

final class VoiceInkKeyboardClipboardModel: ObservableObject {
    @Published private(set) var items: [VoiceInkKeyboardClipboardItem] = []
    @Published private(set) var message: String?

    private let store: VoiceInkKeyboardClipboardStore?
    private var imageCache: [UUID: UIImage] = [:]

    init(store: VoiceInkKeyboardClipboardStore?) {
        self.store = store
        reload()
    }

    func captureCurrentPasteboard(hasFullAccess: Bool) {
        guard hasFullAccess else {
            message = VoiceInkKeyboardClipboardStoreError.unavailableSharedContainer.localizedDescription
            return
        }
        guard let store else {
            message = VoiceInkKeyboardClipboardStoreError.unavailableSharedContainer.localizedDescription
            return
        }
        guard let payload = Self.payload(from: .general) else {
            reload()
            if items.isEmpty {
                message = "Copy text, a link, or an image, then open History again."
            }
            return
        }

        do {
            try store.record(payload)
            message = nil
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func filteredItems(
        matching query: String,
        filter: VoiceInkKeyboardClipboardFilter
    ) -> [VoiceInkKeyboardClipboardItem] {
        VoiceInkKeyboardClipboardSearch.items(items, matching: query, filter: filter)
    }

    func image(for item: VoiceInkKeyboardClipboardItem) -> UIImage? {
        if let cached = imageCache[item.id] { return cached }
        guard let store,
              let data = try? store.imageData(for: item),
              let image = UIImage(data: data) else {
            return nil
        }
        imageCache[item.id] = image
        return image
    }

    func togglePinned(_ item: VoiceInkKeyboardClipboardItem) {
        do {
            try store?.togglePinned(id: item.id)
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func markUsed(_ item: VoiceInkKeyboardClipboardItem) {
        do {
            try store?.markUsed(id: item.id)
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func remove(_ item: VoiceInkKeyboardClipboardItem) {
        do {
            try store?.remove(id: item.id)
            imageCache[item.id] = nil
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func removeAllUnpinned() {
        do {
            try store?.removeAllUnpinned()
            imageCache.removeAll()
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func reportImageCopied() {
        message = "Image copied. Swipe back, then use the app's Paste command."
    }

    private func reload() {
        guard let store else {
            items = []
            return
        }

        do {
            items = try store.items()
            imageCache = imageCache.filter { id, _ in
                items.contains(where: { $0.id == id })
            }
        } catch {
            items = []
            message = error.localizedDescription
        }
    }
}

private extension VoiceInkKeyboardClipboardModel {
    static func payload(from pasteboard: UIPasteboard) -> VoiceInkKeyboardClipboardPayload? {
        if pasteboard.hasImages,
           let image = pasteboard.image,
           let data = imageData(for: image) {
            return VoiceInkKeyboardClipboardPayload(
                imageData: data,
                searchableText: pasteboard.string
            )
        }

        if let url = pasteboard.url,
           let payload = VoiceInkKeyboardClipboardPayload(
               text: url.absoluteString,
               kind: .link
           ) {
            return payload
        }

        guard let text = pasteboard.string else { return nil }
        let kind: VoiceInkKeyboardClipboardItemKind = isWebLink(text) ? .link : .text
        return VoiceInkKeyboardClipboardPayload(text: text, kind: kind)
    }

    static func imageData(for image: UIImage) -> Data? {
        if let pngData = image.pngData(),
           pngData.count <= VoiceInkKeyboardClipboardStore.maximumImageByteCount {
            return pngData
        }
        return image.jpegData(compressionQuality: 0.82)
    }

    static func isWebLink(_ text: String) -> Bool {
        guard let components = URLComponents(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return false
        }
        return ["http", "https"].contains(components.scheme?.lowercased())
            && components.host != nil
    }
}

final class VoiceInkKeyboardActionHandler: KeyboardActionHandler {
    private let standardHandler: KeyboardActionHandler
    private let keyboardContext: KeyboardContext
    private let shellState: VoiceInkKeyboardShellState

    init(
        standardHandler: KeyboardActionHandler,
        keyboardContext: KeyboardContext,
        shellState: VoiceInkKeyboardShellState
    ) {
        self.standardHandler = standardHandler
        self.keyboardContext = keyboardContext
        self.shellState = shellState
    }

    func canHandle(
        _ gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) -> Bool {
        standardHandler.canHandle(gesture, on: action)
    }

    func handle(_ action: KeyboardAction) {
        standardHandler.handle(action)
    }

    func handle(
        _ gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) {
        guard shellState.surface == .clipboard else {
            standardHandler.handle(gesture, on: action)
            return
        }

        switch (gesture, action) {
        case (.release, .character(let character)):
            triggerFeedback(for: gesture, on: action)
            shellState.appendToClipboardQuery(character)
            if keyboardContext.keyboardCase != .capsLocked {
                keyboardContext.keyboardCase = .lowercased
            }
        case (.release, .space):
            triggerFeedback(for: gesture, on: action)
            shellState.appendToClipboardQuery(" ")
        case (.release, .text(let text)):
            triggerFeedback(for: gesture, on: action)
            shellState.appendToClipboardQuery(text)
        case (.release, .urlDomain):
            triggerFeedback(for: gesture, on: action)
            shellState.appendToClipboardQuery(".")
        case (.press, .backspace), (.repeatPress, .backspace):
            triggerFeedback(for: gesture, on: action)
            shellState.deleteLastClipboardQueryCharacter()
        case (.release, .primary):
            triggerFeedback(for: gesture, on: action)
            shellState.onSubmitSearch?()
        case (.press, .keyboardType(.emojis)):
            shellState.showKeyboard()
            standardHandler.handle(gesture, on: action)
        case (_, .keyboardType), (_, .shift), (_, .capsLock), (_, .nextKeyboard), (_, .nextLocale), (_, .dismissKeyboard):
            standardHandler.handle(gesture, on: action)
        case (.press, .tab):
            triggerFeedback(for: gesture, on: action)
        default:
            break
        }
    }

    func handle(_ suggestion: Autocomplete.Suggestion) {
        standardHandler.handle(suggestion)
    }

    func handleDrag(
        on action: KeyboardAction,
        from startLocation: CGPoint,
        to currentLocation: CGPoint
    ) {
        standardHandler.handleDrag(
            on: action,
            from: startLocation,
            to: currentLocation
        )
    }

    func triggerFeedback(
        for gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) {
        standardHandler.triggerFeedback(for: gesture, on: action)
    }

    func triggerAudioFeedback(_ feedback: Feedback.Audio) {
        standardHandler.triggerAudioFeedback(feedback)
    }

    func triggerHapticFeedback(_ feedback: Feedback.Haptic) {
        standardHandler.triggerHapticFeedback(feedback)
    }
}

struct VoiceInkKeyboardShellView: View {
    let services: Keyboard.Services
    let state: Keyboard.State
    @ObservedObject var shellState: VoiceInkKeyboardShellState
    @ObservedObject var clipboardModel: VoiceInkKeyboardClipboardModel
    let onOpenClipboard: () -> Void
    let onActivateClipboardItem: (VoiceInkKeyboardClipboardItem) -> Void

    @EnvironmentObject private var keyboardContext: KeyboardContext

    var body: some View {
        KeyboardView(
            layout: keyboardLayout,
            state: state,
            services: services,
            buttonContent: { $0.view },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { _ in
                VoiceInkEmojiKeyboardView(
                    actionHandler: services.actionHandler,
                    keyboardContext: keyboardContext,
                    height: CGFloat(keyboardLayout.totalHeight)
                )
            },
            toolbar: { _ in
                VoiceInkKeyboardToolbarView(
                    shellState: shellState,
                    clipboardModel: clipboardModel,
                    clipboardFilter: $shellState.clipboardFilter,
                    onToggleClipboard: toggleClipboard,
                    onActivateItem: onActivateClipboardItem
                )
            }
        )
        .animation(.easeInOut(duration: 0.18), value: shellState.surface)
    }
}

private extension VoiceInkKeyboardShellView {
    var keyboardLayout: KeyboardLayout {
        var layout = KeyboardLayout.standard(for: keyboardContext)
        switch keyboardContext.keyboardType {
        case .emojis, .emojiSearch, .images, .numberPad, .custom:
            return layout
        case .alphabetic, .email, .numeric, .symbolic, .url, .webSearch:
            break
        }

        guard let bottomRowIndex = layout.itemRows.indices.last else { return layout }
        let bottomRow = layout.itemRows[bottomRowIndex]

        if !bottomRow.contains(where: { $0.action == .tab }) {
            let tabItem = layout.createIdealItem(
                for: .tab,
                width: .percentage(0.10)
            )
            layout.itemRows.insert(tabItem, before: .space, inRow: bottomRowIndex)
        }

        let emojiAction = KeyboardAction.keyboardType(.emojis)
        if !bottomRow.contains(where: { $0.action == emojiAction }) {
            let emojiItem = layout.createIdealItem(
                for: emojiAction,
                width: .percentage(0.10)
            )
            layout.itemRows.insert(emojiItem, after: .space, inRow: bottomRowIndex)
        }

        return layout
    }

    func toggleClipboard() {
        if shellState.surface == .keyboard {
            onOpenClipboard()
        }
        shellState.toggleClipboard()
    }
}

private struct VoiceInkKeyboardToolbarView: View {
    @ObservedObject var shellState: VoiceInkKeyboardShellState
    @ObservedObject var clipboardModel: VoiceInkKeyboardClipboardModel
    @Binding var clipboardFilter: VoiceInkKeyboardClipboardFilter
    let onToggleClipboard: () -> Void
    let onActivateItem: (VoiceInkKeyboardClipboardItem) -> Void

    var body: some View {
        Group {
            if shellState.surface == .clipboard {
                VoiceInkClipboardHistoryPanel(
                    shellState: shellState,
                    model: clipboardModel,
                    filter: $clipboardFilter,
                    onActivateItem: onActivateItem,
                    onClose: onToggleClipboard
                )
            } else {
                HStack {
                    Spacer()
                    Button(action: onToggleClipboard) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clipboard History")
                    .accessibilityIdentifier("voiceink.keyboard.clipboardHistory")
                }
                .padding(.horizontal, 6)
                .frame(height: 44)
                .voiceInkHorizontalSwipe(onToggleClipboard)
            }
        }
    }
}

private struct VoiceInkClipboardHistoryPanel: View {
    @ObservedObject var shellState: VoiceInkKeyboardShellState
    @ObservedObject var model: VoiceInkKeyboardClipboardModel
    @Binding var filter: VoiceInkKeyboardClipboardFilter
    let onActivateItem: (VoiceInkKeyboardClipboardItem) -> Void
    let onClose: () -> Void

    @State private var isConfirmingClear = false

    private var filteredItems: [VoiceInkKeyboardClipboardItem] {
        model.filteredItems(matching: shellState.clipboardQuery, filter: filter)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Clipboard History")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !model.items.isEmpty {
                    Button(isConfirmingClear ? "Confirm" : "Clear") {
                        if isConfirmingClear {
                            model.removeAllUnpinned()
                            isConfirmingClear = false
                        } else {
                            isConfirmingClear = true
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                }
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Keyboard")
            }
            .padding(.leading, 38)
            .voiceInkHorizontalSwipe(onClose)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(
                    shellState.clipboardQuery.isEmpty
                        ? "Type below to search"
                        : shellState.clipboardQuery
                )
                .font(.system(size: 13))
                .foregroundStyle(shellState.clipboardQuery.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                Spacer()
                if !shellState.clipboardQuery.isEmpty {
                    Button {
                        shellState.clipboardQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier("voiceink.keyboard.clipboardSearch")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(VoiceInkKeyboardClipboardFilter.allCases, id: \.self) { item in
                        Button(item.title) {
                            filter = item
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            filter == item ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: Capsule()
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            if let message = model.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else if filteredItems.isEmpty {
                Text(shellState.clipboardQuery.isEmpty ? "No saved clips yet." : "No matching clips.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            VoiceInkClipboardItemCard(
                                item: item,
                                image: model.image(for: item),
                                onActivate: { onActivateItem(item) },
                                onTogglePinned: { model.togglePinned(item) },
                                onDelete: { model.remove(item) }
                            )
                        }
                    }
                }
                .frame(height: 66)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .frame(height: 176)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("voiceink.keyboard.clipboardPanel")
    }
}

private extension View {
    func voiceInkHorizontalSwipe(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalDistance = abs(value.translation.width)
                        let verticalDistance = abs(value.translation.height)
                        guard horizontalDistance > 44,
                              horizontalDistance > verticalDistance * 1.2 else {
                            return
                        }
                        action()
                    }
            )
    }
}

private struct VoiceInkClipboardItemCard: View {
    let item: VoiceInkKeyboardClipboardItem
    let image: UIImage?
    let onActivate: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onActivate) {
                HStack(spacing: 7) {
                    preview
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.summary)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(item.lastUsedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Button(action: onTogglePinned) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(width: 190, height: 62)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("voiceink.keyboard.clipboardItem.\(item.id.uuidString)")
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: item.kind == .link ? "link" : "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct VoiceInkEmojiKeyboardView: View {
    let actionHandler: KeyboardActionHandler
    let keyboardContext: KeyboardContext
    let height: CGFloat

    @State private var category: EmojiCategory = .smileysAndPeople

    private let columns = [GridItem](
        repeating: GridItem(.flexible(), spacing: 2),
        count: 8
    )

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button("ABC") {
                    keyboardContext.keyboardType = .alphabetic
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                Spacer()
                Text(category.voiceInkTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(category.emojis) { emoji in
                        Button {
                            actionHandler.handle(.release, on: .emoji(emoji))
                        } label: {
                            Text(emoji.char)
                                .font(.system(size: 27))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 5)
            }

            HStack(spacing: 0) {
                ForEach(EmojiCategory.standardCategories, id: \.id) { item in
                    Button {
                        category = item
                    } label: {
                        item.symbolIcon
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(category == item ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 220))
        .background(Color(uiColor: .systemGray5))
        .accessibilityIdentifier("voiceink.keyboard.emojiPanel")
    }
}

private extension EmojiCategory {
    var voiceInkTitle: String {
        switch self {
        case .smileysAndPeople: "Smileys & People"
        case .animalsAndNature: "Animals & Nature"
        case .foodAndDrink: "Food & Drink"
        case .activity: "Activity"
        case .travelAndPlaces: "Travel & Places"
        case .objects: "Objects"
        case .symbols: "Symbols"
        case .flags: "Flags"
        case .favorites: "Favorites"
        case .recent, .frequent: "Recent"
        case .custom(_, let name, _, _): name
        }
    }
}
