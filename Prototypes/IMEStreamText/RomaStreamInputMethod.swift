// PROTOTYPE — throwaway. See README.md.
import Cocoa
import InputMethodKit

let logPath = NSHomeDirectory() + "/roma-stream-ime.log"
let log: FileHandle = {
    if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
    return FileHandle(forWritingAtPath: logPath) ?? FileHandle.standardError
}()
func trace(_ message: String) {
    let line = "\(ProcessInfo.processInfo.systemUptime) \(message)\n"
    log.seekToEndOfFile(); log.write(line.data(using: .utf8)!)
}

@objc(RomaStreamController)
final class RomaStreamController: IMKInputController {
    /// The controller of the field focused right now; nil while focus is between fields.
    static weak var current: RomaStreamController?
    /// An update that arrived while no field was focused (focus flickers at Shift release).
    /// Expires quickly so a late field never receives it.
    static var pending: (update: (RomaStreamController) -> Void, expires: TimeInterval)?
    /// The field this hold's guess was shown in; the final text only ever goes there.
    static weak var guessOwner: RomaStreamController?
    static var guessShown = false
    /// The user clicked, typed, or moved focus while a guess was showing: this hold shows and
    /// inserts nothing more. Chrome keeps one connection for the whole page, so a click arrives as
    /// commitComposition rather than as a deactivate.
    static var interrupted = false
    /// Text was selected when the first guess arrived: a guess would replace it before the user
    /// has said anything final, so this hold shows nothing and Roma pastes on release instead.
    static var declined = false
    /// The hold these messages belong to; a message from another hold is ignored.
    static var hold = ""

    static func reset() { guessShown = false; guessOwner = nil; interrupted = false; declined = false }

    private var markedLength = 0

    static func deliver(until expires: TimeInterval = ProcessInfo.processInfo.systemUptime + 1.0,
                        _ update: @escaping (RomaStreamController) -> Void) {
        if let current { update(current); return }
        pending = (update, expires)
        trace("pending: no focused field")
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        RomaStreamController.current = self
        trace("activate \((sender as? IMKTextInput)?.bundleIdentifier() ?? "?")")
        if let pending = RomaStreamController.pending {
            RomaStreamController.pending = nil
            if ProcessInfo.processInfo.systemUptime <= pending.expires { trace("flush pending"); pending.update(self) }
            else { trace("drop expired pending") }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        // Focus left this field mid-hold: take the unfinished guess with it.
        if markedLength > 0 {
            trace("deactivate: clearing guess of \(markedLength)")
            clearGuess(sender as? IMKTextInput)
            RomaStreamController.interrupted = true
        }
        if RomaStreamController.current === self { RomaStreamController.current = nil }
        trace("deactivate")
        super.deactivateServer(sender)
    }

    /// Keys go to the app untouched. While this field shows a guess, Escape is swallowed (Chrome would
    /// type it as a character; Roma's own double-Escape cancel does not depend on this), and any other
    /// key is the user typing over the guess: it goes away, the key goes through, and this hold
    /// inserts nothing more.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, markedLength > 0 else { return false }
        if event.keyCode == 53 { return true }
        trace("typing over the guess: stopping this hold")
        clearGuess(sender as? IMKTextInput)
        RomaStreamController.interrupted = true
        return false
    }

    /// The app ends composition on its own (click, Esc): our guess is not the user's text.
    override func commitComposition(_ sender: Any!) {
        trace("commitComposition (app asked), marked=\(markedLength)")
        if markedLength > 0 {
            clearGuess(sender as? IMKTextInput)
            RomaStreamController.interrupted = true
        }
    }

    func showGuess(_ text: String) {
        guard !RomaStreamController.interrupted, !RomaStreamController.declined else { return }
        guard let client = client() else { trace("partial: no client"); return }
        if !RomaStreamController.guessShown, client.selectedRange().length > 0 {
            RomaStreamController.declined = true
            trace("partial: text selected, showing nothing this hold")
            return
        }
        client.setMarkedText(NSAttributedString(string: text, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]),
                             selectionRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        markedLength = (text as NSString).length
        RomaStreamController.guessOwner = self
        if !RomaStreamController.guessShown {
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.negentropi.RomaStream.shown"), object: RomaStreamController.hold, userInfo: nil, deliverImmediately: true)
        }
        RomaStreamController.guessShown = true
        trace("marked \(markedLength) to \(client.bundleIdentifier() ?? "?")")
    }

    func commit(_ text: String) -> String {
        defer { RomaStreamController.reset() }
        // The user clicked, typed, or moved focus after the guess appeared: never insert anywhere.
        if RomaStreamController.interrupted || (RomaStreamController.guessShown && RomaStreamController.guessOwner !== self) {
            trace("commit refused: interrupted"); return "moved"
        }
        guard let client = client() else { return "nofield" }
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        markedLength = 0
        trace("commit \((text as NSString).length) to \(client.bundleIdentifier() ?? "?")")
        return "committed"
    }

    func clear() -> String {
        guard markedLength > 0 else { return "nothing" }
        clearGuess(client())
        return "cleared"
    }

    private func clearGuess(_ client: IMKTextInput?) {
        client?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        markedLength = 0
    }
}

func reply(_ token: String, _ result: String) {
    DistributedNotificationCenter.default().postNotificationName(
        .init("com.negentropi.RomaStream.ack"), object: token + "\n" + result, userInfo: nil, deliverImmediately: true)
}

/// Newline-joined fields; only the last may contain a newline. Missing fields are empty.
func fields(_ object: Any?, _ count: Int) -> [String] {
    let parts = (object as? String ?? "").split(separator: "\n", maxSplits: count - 1, omittingEmptySubsequences: false).map(String.init)
    return parts + Array(repeating: "", count: max(0, count - parts.count))
}

let bundle = Bundle.main
let connection = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
let server = IMKServer(name: connection, bundleIdentifier: bundle.bundleIdentifier!)
trace("server up \(server != nil)")
let center = DistributedNotificationCenter.default()
center.addObserver(forName: .init("com.negentropi.RomaStream.partial"), object: nil, queue: .main) { note in
    let message = fields(note.object, 2) // hold, text
    MainActor.assumeIsolated {
        if message[0] != RomaStreamController.hold {
            // A new hold; holds never overlap, since Roma records one at a time.
            RomaStreamController.hold = message[0]
            RomaStreamController.reset()
        }
        RomaStreamController.deliver { $0.showGuess(message[1]) }
    }
}
center.addObserver(forName: .init("com.negentropi.RomaStream.commit"), object: nil, queue: .main) { note in
    let message = fields(note.object, 4) // token, hold, deadline, text
    let deadline = TimeInterval(message[2]) ?? 0
    MainActor.assumeIsolated {
        guard message[1] == RomaStreamController.hold else { reply(message[0], "stale"); return }
        RomaStreamController.deliver(until: deadline) { controller in
            // Past the deadline Roma may already be pasting: never insert the text a second time.
            guard ProcessInfo.processInfo.systemUptime <= deadline else { trace("commit refused: late"); reply(message[0], "late"); return }
            reply(message[0], controller.commit(message[3]))
        }
    }
}
center.addObserver(forName: .init("com.negentropi.RomaStream.clear"), object: nil, queue: .main) { note in
    let message = fields(note.object, 2) // token (may be empty), hold
    let token = message[0]
    MainActor.assumeIsolated {
        guard message[1] == RomaStreamController.hold else {
            trace("clear: other hold, ignored")
            if !token.isEmpty { reply(token, "stale") }
            return
        }
        RomaStreamController.reset()
        RomaStreamController.pending = nil
        let result = RomaStreamController.current?.clear() ?? "nofield"
        trace("clear: \(result)")
        if !token.isEmpty { reply(token, result) }
    }
}
NSApplication.shared.run()
