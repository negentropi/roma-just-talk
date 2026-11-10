// PROTOTYPE (proto/ime-stream-text) — throwaway, not production.
// Shows Roma's running guess in a floating overlay instead of typing it, then hides once the
// release paste lands. `defaults write com.negentropi.RomaJustTalk prototypeOverlayStream bubble|ghost`
//   bubble: small dark caption just under the caret line.
//   ghost:  grey text drawn over the field starting at the caret, sized like the field's text.
import AppKit
import ApplicationServices

@MainActor
final class OverlayStreamPrototype {
    static let shared = OverlayStreamPrototype()
    static var style: String? {
        let value = UserDefaults.standard.string(forKey: "prototypeOverlayStream") ?? ""
        return ["bubble", "ghost"].contains(value) ? value : nil
    }

    private var panel: NSPanel?
    private let label = NSTextField(wrappingLabelWithString: "")
    private var anchor: (caret: CGRect, field: CGRect)?
    private var hideTimer: Timer?

    func show(_ text: String) {
        guard let style = Self.style else { return }
        if anchor == nil { anchor = Self.caretAndField() }
        guard let anchor else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let lineHeight = max(anchor.caret.height, 14)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        if style == "ghost" {
            label.font = .systemFont(ofSize: (lineHeight / 1.45).rounded())
            label.textColor = NSColor.secondaryLabelColor
            panel.backgroundColor = .clear
            label.stringValue = text
            let width = max(anchor.field.maxX - anchor.caret.minX - 8, 200)
            label.preferredMaxLayoutWidth = width
            let size = label.fittingSize
            // AX is top-left origin; Cocoa is bottom-left.
            let top = screenHeight - anchor.caret.minY
            panel.setFrame(NSRect(x: anchor.caret.minX, y: top - size.height, width: width, height: size.height), display: true)
        } else {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textColor = .white
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.82)
            // Only the newest words, so the bubble stays two lines at most.
            let words = text.split(separator: " ")
            label.stringValue = (words.count > 22 ? "… " : "") + words.suffix(22).joined(separator: " ")
            let width: CGFloat = 420
            label.preferredMaxLayoutWidth = width - 20
            let size = label.fittingSize
            let top = screenHeight - anchor.caret.maxY - 6
            panel.setFrame(NSRect(x: anchor.caret.minX - 10, y: top - size.height - 12, width: width, height: size.height + 12), display: true)
        }
        label.frame = NSRect(x: style == "ghost" ? 0 : 10, y: style == "ghost" ? 0 : 6,
                             width: panel.frame.width - (style == "ghost" ? 0 : 20), height: panel.frame.height - (style == "ghost" ? 0 : 12))
        panel.orderFrontRegardless()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            MainActor.assumeIsolated { OverlayStreamPrototype.shared.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
        anchor = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 8
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        panel.contentView?.addSubview(label)
        return panel
    }

    /// Caret rect and field rect in AX (top-left) screen coordinates.
    private static func caretAndField() -> (CGRect, CGRect)? {
        func value<T>(_ element: AXUIElement, _ name: String, as: T.Type) -> T? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
            return raw as? T
        }
        func rect(_ raw: AnyObject?) -> CGRect? {
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            return AXValueGetValue(raw as! AXValue, .cgRect, &rect) ? rect : nil
        }
        guard let element = value(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute, as: AXUIElement.self) else { return nil }
        var field = CGRect.zero
        if let positionRaw = value(element, kAXPositionAttribute, as: AnyObject.self), let sizeRaw = value(element, kAXSizeAttribute, as: AnyObject.self) {
            var point = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(positionRaw as! AXValue, .cgPoint, &point)
            AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
            field = CGRect(origin: point, size: size)
        }
        var caret = CGRect(x: field.minX + 4, y: field.minY + 4, width: 1, height: 20)
        if let selectionRaw = value(element, kAXSelectedTextRangeAttribute, as: AnyObject.self) {
            var range = CFRange()
            AXValueGetValue(selectionRaw as! AXValue, .cfRange, &range)
            // Bounds of the character before the caret; its right edge is the caret.
            var query = CFRange(location: max(range.location - 1, 0), length: range.location > 0 ? 1 : 0)
            if let queryValue = AXValueCreate(.cfRange, &query) {
                var raw: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, queryValue, &raw) == .success,
                   let bounds = rect(raw), bounds.height > 0 {
                    caret = CGRect(x: range.location > 0 ? bounds.maxX : bounds.minX, y: bounds.minY, width: 1, height: bounds.height)
                }
            }
        }
        return (caret, field)
    }
}
