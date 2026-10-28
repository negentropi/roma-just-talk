import SwiftUI

/// Presents a settings page as a native window-modal sheet with fixed width.
/// The height follows the presenting page, capped at `preferredHeight`. Sheet content
/// should scroll internally (the callers use `Form`).
/// Presentation, modality and accessibility come from SwiftUI's standard `.sheet`.
/// Escape and the content's own close buttons clear the binding.
struct SettingsSheet<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let width: CGFloat
    @ViewBuilder let sheetContent: (Item) -> SheetContent

    @State private var presenterHeight: CGFloat = 0

    private static var preferredHeight: CGFloat { 560 }
    private static var minimumHeight: CGFloat { 320 }
    private static var verticalInset: CGFloat { 40 }

    private var sheetHeight: CGFloat {
        guard presenterHeight > 0 else { return Self.preferredHeight }
        return min(Self.preferredHeight, max(Self.minimumHeight, presenterHeight - Self.verticalInset))
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presenterHeight = $0 }
            .sheet(item: $item) { presented in
                sheetContent(presented)
                    .frame(width: width, height: sheetHeight)
                    .background(Color(NSColor.windowBackgroundColor))
                    .onExitCommand { item = nil }
            }
    }
}

/// Single-value item that maps a `Bool` presentation onto `SettingsSheet`.
private struct SettingsSheetPresented: Identifiable {
    let id = 0
}

extension View {
    func settingsSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        width: CGFloat = 400,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(SettingsSheet(item: item, width: width, sheetContent: content))
    }

    func settingsSheet<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 400,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let item = Binding<SettingsSheetPresented?>(
            get: { isPresented.wrappedValue ? SettingsSheetPresented() : nil },
            set: { if $0 == nil { isPresented.wrappedValue = false } }
        )
        return settingsSheet(item: item, width: width) { _ in content() }
    }
}
