import AppKit
import ApplicationServices
import SwiftUI
import Combine

struct CursorAvatarPlacement {
    static func frame(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let right = anchor.maxX + 12
        let left = anchor.minX - size.width - 12
        let x = right + size.width <= screen.maxX ? right : left
        let y = anchor.maxY - 14
        return CGRect(x: min(max(x, screen.minX), screen.maxX - size.width),
                      y: min(max(y, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func caretToAppKit(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
final class CursorAvatarController {
    private var panel: NSPanel?
    private var timer: Timer?
    private var preferences: AnyCancellable?
    private var feedback: CaptureFeedback = .hidden
    private let presentation = CursorAvatarPresentation()
    private var readyDismissal: Task<Void, Never>?

    func update(_ feedback: CaptureFeedback, level: Double = 0) {
        presentation.level = level
        if self.feedback.isFailure, feedback == .hidden || feedback == .ready { return }
        if feedback != self.feedback {
            readyDismissal?.cancel()
            self.feedback = feedback
            if feedback == .ready {
                readyDismissal = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.hide()
                }
            }
        }
        guard feedback != .hidden else { hide(); return }
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: CursorAvatarLiveView(presentation: presentation))
            self.panel = panel
            preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
                Task { @MainActor in self?.render() }
            }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.position() }
            }
        }
        render()
        position()
        panel?.orderFrontRegardless()
    }

    func updateLevel(_ level: Double) {
        if panel != nil { presentation.level = level }
    }

    func hide() {
        feedback = .hidden
        readyDismissal?.cancel()
        readyDismissal = nil
        timer?.invalidate()
        timer = nil
        preferences = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func render() {
        guard feedback != .hidden else { return }
        let style = CursorAvatarStyle(rawValue: UserDefaults.standard.string(forKey: CursorAvatarStyle.defaultsKey) ?? "") ?? .cartoon
        presentation.style = style
        presentation.feedback = feedback
        panel?.setContentSize(CGSize(width: 180, height: style == .none ? 76 : 180))
    }

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let anchor = caretAnchor() ?? CGRect(origin: mouse, size: CGSize(width: 1, height: 1))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main else { return }
        panel.setFrame(CursorAvatarPlacement.frame(anchor: anchor, size: panel.frame.size, screen: screen.visibleFrame), display: true)
    }

    private func caretAnchor() -> CGRect? {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return nil }
        var focused: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect),
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.height > 0, rect.width >= 0, rect.width < 200 else { return nil }
        let converted = CursorAvatarPlacement.caretToAppKit(rect, primaryTop: primary.frame.maxY)
        guard NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: converted.midX, y: converted.midY)) }) else { return nil }
        return converted
    }
}
