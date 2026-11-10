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
    /// Every live controller, one per client connection; Roma's notifications go to the frontmost app's.
    static let all = NSHashTable<RomaStreamController>.weakObjects()
    static var active: RomaStreamController? {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let candidates = all.allObjects
        let match = candidates.last { $0.client()?.bundleIdentifier() == front }
        trace("route front=\(front ?? "?") controllers=\(candidates.map { $0.client()?.bundleIdentifier() ?? "nil" }) match=\(match != nil)")
        return match ?? candidates.last
    }
    private var markedLength = 0

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        RomaStreamController.all.add(self)
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
        trace("marked \(markedLength) to \(client.bundleIdentifier() ?? "?") markedRange=\(client.markedRange())")
    }

    func commit(_ text: String) {
        guard let client = client() else { trace("commit: no client"); return }
        if text.isEmpty {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        markedLength = 0
        trace("commit \((text as NSString).length) to \(client.bundleIdentifier() ?? "?")")
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
