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

    private var markedLength = 0

    static func deliver(_ update: @escaping (RomaStreamController) -> Void) {
        if let current { update(current); return }
        pending = (update, ProcessInfo.processInfo.systemUptime + 1.0)
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
        if markedLength > 0 { trace("deactivate: clearing guess of \(markedLength)"); clearGuess(sender as? IMKTextInput) }
        if RomaStreamController.current === self { RomaStreamController.current = nil }
        trace("deactivate")
        super.deactivateServer(sender)
    }

    /// Every key goes to the app untouched; this input method only draws Roma's live guess.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool { false }

    /// The app ends composition on its own (click, Esc): our guess is not the user's text.
    override func commitComposition(_ sender: Any!) {
        trace("commitComposition (app asked), marked=\(markedLength)")
        if markedLength > 0 { clearGuess(sender as? IMKTextInput) }
    }

    func showGuess(_ text: String) {
        guard let client = client() else { trace("partial: no client"); return }
        client.setMarkedText(NSAttributedString(string: text, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]),
                             selectionRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        markedLength = (text as NSString).length
        trace("marked \(markedLength) to \(client.bundleIdentifier() ?? "?")")
    }

    func commit(_ text: String) -> String {
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

/// "token\ntext" → (token, text)
func split(_ object: Any?) -> (String, String) {
    let parts = (object as? String ?? "").split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
}

let bundle = Bundle.main
let connection = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
let server = IMKServer(name: connection, bundleIdentifier: bundle.bundleIdentifier!)
trace("server up \(server != nil)")
let center = DistributedNotificationCenter.default()
center.addObserver(forName: .init("com.negentropi.RomaStream.partial"), object: nil, queue: .main) { note in
    let text = note.object as? String ?? ""
    MainActor.assumeIsolated { RomaStreamController.deliver { $0.showGuess(text) } }
}
center.addObserver(forName: .init("com.negentropi.RomaStream.commit"), object: nil, queue: .main) { note in
    let (token, text) = split(note.object)
    MainActor.assumeIsolated { RomaStreamController.deliver { reply(token, $0.commit(text)) } }
}
center.addObserver(forName: .init("com.negentropi.RomaStream.clear"), object: nil, queue: .main) { note in
    let (token, _) = split(note.object)
    MainActor.assumeIsolated {
        if let current = RomaStreamController.current { reply(token, current.clear()) } else { RomaStreamController.pending = nil; reply(token, "nofield") }
    }
}
NSApplication.shared.run()
