// PROTOTYPE — throwaway. See README.md.
import Cocoa
import InputMethodKit

let log = FileHandle(forWritingAtPath: "/tmp/roma-stream-ime.log") ?? FileHandle.standardError
func trace(_ message: String) {
    let line = "\(ProcessInfo.processInfo.systemUptime) \(message)\n"
    log.seekToEndOfFile(); log.write(line.data(using: .utf8)!)
}

@objc(RomaStreamController)
final class RomaStreamController: IMKInputController {
    /// The controller of the field that last became active; Roma's notifications go to it.
    static weak var active: RomaStreamController?
    private var markedLength = 0

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        RomaStreamController.active = self
        trace("activate \((sender as? IMKTextInput)?.bundleIdentifier() ?? "?")")
    }

    override func deactivateServer(_ sender: Any!) {
        trace("deactivate")
        super.deactivateServer(sender)
    }

    /// Every key goes to the app untouched; this input method only draws Roma's live guess.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool { false }

    func showGuess(_ text: String) {
        guard let client = client() else { trace("partial: no client"); return }
        let attributes: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        client.setMarkedText(NSAttributedString(string: text, attributes: attributes),
                             selectionRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        markedLength = (text as NSString).length
        trace("marked \(markedLength): \(text)")
    }

    func commit(_ text: String) {
        guard let client = client() else { trace("commit: no client"); return }
        if text.isEmpty {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        markedLength = 0
        trace("commit: \(text)")
    }

    /// The app ends composition (click elsewhere, focus change): keep what is shown.
    override func commitComposition(_ sender: Any!) {
        trace("commitComposition (app asked)")
        super.commitComposition(sender)
    }
}

let bundle = Bundle.main
let connection = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
let server = IMKServer(name: connection, bundleIdentifier: bundle.bundleIdentifier!)
trace("server up \(server != nil)")
let center = DistributedNotificationCenter.default()
center.addObserver(forName: .init("com.negentropi.RomaStream.partial"), object: nil, queue: .main) { note in
    MainActor.assumeIsolated { RomaStreamController.active?.showGuess(note.object as? String ?? "") }
}
center.addObserver(forName: .init("com.negentropi.RomaStream.commit"), object: nil, queue: .main) { note in
    MainActor.assumeIsolated { RomaStreamController.active?.commit(note.object as? String ?? "") }
}
NSApplication.shared.run()
