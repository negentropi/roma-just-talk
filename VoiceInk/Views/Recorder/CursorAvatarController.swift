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

    static func caretBounds(at location: Int, characterCount: Int?, read: (CFRange) -> CGRect?,
                            emptyElementTop: () -> CGFloat? = { nil },
                            precedingLineBreak: () -> Bool = { false },
                            previousLineStart: () -> CGRect? = { nil }) -> CGRect? {
        guard location >= 0 else { return nil }
        let reported = read(CFRange(location: location, length: 0))
        // Sonoma TextEdit returns success with a zero-height insertion rectangle.
        // Read actual glyph geometry rather than moving the companion to the mouse.
        guard var caret = reported, caret.height > 0 else {
            if characterCount.map({ location < $0 }) ?? true,
               let next = read(CFRange(location: location, length: 1)), next.height > 0 {
                let previous = location > 0 ? read(CFRange(location: location - 1, length: 1)) : nil
                let following = characterCount.map({ location + 1 < $0 }) ?? true
                    ? read(CFRange(location: location + 1, length: 1)) : nil
                let x: CGFloat?
                if let previous, let edge = sharedCharacterEdge(previous, next) {
                    x = edge
                } else if let previous, previous.height > 0, abs(previous.minY - next.minY) <= 1 {
                    x = nil
                } else if let following, let edge = sharedCharacterEdge(next, following) {
                    x = abs(edge - next.minX) <= 1 ? next.maxX : next.minX
                } else if let start = previousLineStart(), abs(start.minX - next.minX) <= 1 || abs(start.minX - next.maxX) <= 1 {
                    x = start.minX
                } else {
                    x = nil
                }
                guard let x else { return nil }
                return CGRect(x: x, y: next.minY, width: 0, height: next.height)
            }
            guard location > 0, let previous = read(CFRange(location: location - 1, length: 1)), previous.height > 0 else { return nil }
            if precedingLineBreak() {
                guard let start = previousLineStart() else { return nil }
                return CGRect(x: start.minX, y: previous.maxY, width: 0, height: previous.height)
            }
            guard location > 1, let before = read(CFRange(location: location - 2, length: 1)),
                  let edge = sharedCharacterEdge(before, previous) else { return nil }
            let x = abs(edge - previous.minX) <= 1 ? previous.maxX : previous.minX
            return CGRect(x: x, y: previous.minY, width: 0, height: previous.height)
        }
        // AppKit can report an empty range one line above the drawn insertion point.
        // Character bounds provide the actual line without shifting correct browser carets.
        if characterCount.map({ location < $0 }) ?? true,
           let next = read(CFRange(location: location, length: 1)), next.height > 0,
           abs(next.minX - caret.minX) <= 1 || abs(next.maxX - caret.minX) <= 1 ||
            (next.height > caret.height + 1 && caret.minX >= next.minX && caret.minX <= next.maxX) {
            caret.origin.y = next.minY
        } else if location > 0, let previous = read(CFRange(location: location - 1, length: 1)), previous.height > 0,
                  abs(previous.maxX - caret.minX) <= 1 || abs(previous.minX - caret.minX) <= 1 ||
                    (previous.height > caret.height + 1 && caret.minX >= previous.minX && caret.minX <= previous.maxX) {
            caret.origin.y = previous.maxY - caret.height
        } else if location == 0, let top = emptyElementTop() {
            caret.origin.y = max(caret.minY, top)
        }
        return caret
    }

    private static func sharedCharacterEdge(_ first: CGRect, _ second: CGRect) -> CGFloat? {
        guard first.height > 0, second.height > 0, abs(first.minY - second.minY) <= 1 else { return nil }
        if abs(first.maxX - second.minX) <= 1 { return second.minX }
        if abs(first.minX - second.maxX) <= 1 { return second.maxX }
        return nil
    }
}

@MainActor
final class CursorAvatarController {
    private var panel: NSPanel?
    private var timer: Timer?
    private var preferences: AnyCancellable?
    private var feedback: CaptureFeedback = .idle
    private let presentation = CursorAvatarPresentation()
    private var lastCaretCheck = Date.distantPast
    private var cachedCaret: CGRect?

    func update(_ feedback: CaptureFeedback, level: Double = 0) {
        presentation.level = level
        if self.feedback.isFailure, feedback == .idle || feedback == .ready { return }
        if feedback != self.feedback {
            self.feedback = feedback
        }
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
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.position() }
            }
            // Menu tracking must not freeze the cursor attachment.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        render()
        position()
        panel?.orderFrontRegardless()
    }

    func updateLevel(_ level: Double) {
        if panel != nil { presentation.level = level }
    }

    func hide() {
        feedback = .idle
        timer?.invalidate()
        timer = nil
        cachedCaret = nil
        lastCaretCheck = .distantPast
        preferences = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func render() {
        let style = CursorAvatarStyle(rawValue: UserDefaults.standard.string(forKey: CursorAvatarStyle.defaultsKey) ?? "") ?? .cartoon
        presentation.style = style
        presentation.feedback = feedback
        panel?.setContentSize(CGSize(width: feedback.isFailure ? 224 : 40, height: feedback.isFailure ? 90 : 36))
    }

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if Date().timeIntervalSince(lastCaretCheck) >= 0.1 {
            cachedCaret = caretAnchor()
            lastCaretCheck = Date()
        }
        // Focused insertion geometry owns the companion throughout editing.
        let anchor = cachedCaret ?? CGRect(origin: mouse, size: .zero)
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
        AXUIElementSetMessagingTimeout(element, 0.01)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var selection = CFRange()
        guard CFGetTypeID(range) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(range, to: AXValue.self), .cfRange, &selection),
              selection.length == 0 else { return nil }
        var countValue: CFTypeRef?
        let countResult = AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countValue)
        let characterCount = countResult == .success ? (countValue as? NSNumber)?.intValue : nil
        let readBounds: (CFRange) -> CGRect? = { requestedRange in
            var requestedRange = requestedRange
            guard let value = AXValueCreate(.cfRange, &requestedRange) else { return nil }
            var bounds: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
                  let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect),
                  rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.height >= 0, rect.width >= 0,
                  requestedRange.length > 0 || rect.width < 200 else { return nil }
            return rect
        }
        let rect = CursorAvatarPlacement.caretBounds(at: selection.location, characterCount: characterCount, read: readBounds, emptyElementTop: {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero
            guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point), point.y.isFinite else { return nil }
            return point.y
        }, precedingLineBreak: {
            var previous = CFRange(location: selection.location - 1, length: 1)
            guard let value = AXValueCreate(.cfRange, &previous) else { return false }
            var text: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &text) == .success,
                  let text = text as? String else { return false }
            return text == "\n" || text == "\r" || text == "\u{2028}" || text == "\u{2029}"
        }, previousLineStart: {
            guard selection.location > 0 else { return nil }
            var line: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXLineForIndexParameterizedAttribute as CFString,
                                                             NSNumber(value: selection.location - 1), &line) == .success,
                  let line else { return nil }
            guard let lineNumber = line as? NSNumber else { return nil }
            // Empty lines have no directional glyph pair. Look through nearby lines
            // without guessing that every writing system starts at the left edge.
            for number in stride(from: lineNumber.intValue, through: max(0, lineNumber.intValue - 8), by: -1) {
                var range: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForLineParameterizedAttribute as CFString,
                                                                 NSNumber(value: number), &range) == .success,
                      let range, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
                var previousLine = CFRange()
                guard AXValueGetValue(unsafeBitCast(range, to: AXValue.self), .cfRange, &previousLine) else { return nil }
                if previousLine.length > 1,
                   let start = CursorAvatarPlacement.caretBounds(at: previousLine.location, characterCount: characterCount, read: readBounds) {
                    return start
                }
            }
            return nil
        })
        guard let rect else { return nil }
        let converted = CursorAvatarPlacement.caretToAppKit(rect, primaryTop: primary.frame.maxY)
        guard NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: converted.midX, y: converted.midY)) }) else { return nil }
        return converted
    }
}
