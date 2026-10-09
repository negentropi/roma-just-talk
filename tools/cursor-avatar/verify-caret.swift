import AppKit
import ApplicationServices

@main
struct VerifyCaret {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 640, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: window.contentView!.bounds)
        text.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = "Cursor attachment proof\nSecond line\n"
        window.contentView = text
        window.orderFrontRegardless()
        window.makeFirstResponder(text)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let top = NSScreen.screens.first!.frame.maxY
        for location in [0, 6, 23, 24, 35, (text.string as NSString).length] {
            let read: (CFRange) -> CGRect? = { range in
                guard range.location + range.length <= (text.string as NSString).length else { return nil }
                let native = text.accessibilityFrame(for: NSRange(location: range.location, length: range.length))
                return CGRect(x: native.minX, y: top - native.maxY, width: native.width, height: native.height)
            }
            #if RAW_CARET_BASELINE
            let bounds = read(CFRange(location: location, length: 0))!
            #else
            let bounds = CursorAvatarPlacement.caretBounds(at: location, read: read)!
            #endif
            let actual = text.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
            let frame = CursorAvatarPlacement.frame(anchor: CursorAvatarPlacement.caretToAppKit(bounds, primaryTop: top), size: CGSize(width: 40, height: 36), screen: NSScreen.screens.first!.visibleFrame)
            assert(abs(frame.minX + 16 - actual.minX) < 1 && abs(frame.maxY - 32 - actual.maxY) < 1, "native character feet must touch the drawn insertion caret at \(location): bounds \(bounds), panel \(frame), actual \(actual)")
        }
        #if !RAW_CARET_BASELINE
        let browser = CGRect(x: 400, y: 300, width: 1, height: 16)
        let browserBounds = CursorAvatarPlacement.caretBounds(at: 4) { range in
            range.length == 0 ? browser : CGRect(x: 400, y: 300, width: 8, height: 16)
        }
        assert(browserBounds == browser, "correct browser caret coordinates must remain unchanged")
        text.string = ""
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let empty = CursorAvatarPlacement.caretBounds(at: 0, read: { range in
            guard range.length == 0 else { return nil }
            let native = text.accessibilityFrame(for: NSRange(location: 0, length: 0))
            return CGRect(x: native.minX, y: top - native.maxY, width: native.width, height: native.height)
        }, emptyElementTop: { top - text.accessibilityFrame().maxY })!
        let emptyActual = text.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        assert(abs(CursorAvatarPlacement.caretToAppKit(empty, primaryTop: top).maxY - emptyActual.maxY) < 1, "empty text area keeps the character on its first insertion caret")
        #endif
        print("PASS native text-view caret attachment at beginning, middle, newline, next line and document end; unchanged browser caret")
    }
}
