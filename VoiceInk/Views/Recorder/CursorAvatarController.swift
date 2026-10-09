import AppKit
import ApplicationServices
import SwiftUI
import Combine

struct CursorAvatarPlacement {
    static func frame(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        // The artwork's feet are 16 points across and 32 points below the panel top.
        let attachmentX: CGFloat = size.width > 40 && anchor.minX - 16 + size.width > screen.maxX ? size.width - 20 : 16
        let x = anchor.minX - attachmentX
        let y = anchor.maxY - (size.height - 32)
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
    private var lastCaretCheck = Date.distantPast
    private var cachedCaret: CGRect?
    private var lastMouse = CGPoint.zero
    private var lastMouseMovement = Date.distantPast

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
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
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
        cachedCaret = nil
        lastCaretCheck = .distantPast
        preferences = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func render() {
        guard feedback != .hidden else { return }
        let style = CursorAvatarStyle(rawValue: UserDefaults.standard.string(forKey: CursorAvatarStyle.defaultsKey) ?? "") ?? .cartoon
        presentation.style = style
        presentation.feedback = feedback
        panel?.setContentSize(CGSize(width: feedback.isFailure ? 224 : 40, height: feedback.isFailure ? 90 : 36))
    }

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastMouseMovement = Date()
        }
        if Date().timeIntervalSince(lastCaretCheck) >= 0.1 {
            cachedCaret = caretAnchor()
            lastCaretCheck = Date()
        }
        let anchor = Date().timeIntervalSince(lastMouseMovement) >= 0.8 ? (cachedCaret ?? CGRect(origin: mouse, size: .zero)) : CGRect(origin: mouse, size: .zero)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main else { return }
        presentation.trailingAttachment = feedback.isFailure && anchor.minX - 16 + panel.frame.width > screen.visibleFrame.maxX
        let frame = CursorAvatarPlacement.frame(anchor: anchor, size: panel.frame.size, screen: screen.visibleFrame)
        presentation.attachmentOffset = CGSize(width: anchor.minX - frame.minX - (presentation.trailingAttachment ? 204 : 16),
                                             height: frame.maxY - anchor.maxY - 32)
        panel.setFrame(frame, display: true)
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
        var selection = CFRange()
        guard CFGetTypeID(range) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(range, to: AXValue.self), .cfRange, &selection),
              selection.length == 0 else { return nil }
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
