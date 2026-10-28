import AppKit
import Foundation

func units(_ value: String) -> [String: Any] {
    ["text": value, "utf8": Array(value.utf8), "utf16": Array(value.utf16)]
}
let name = NSPasteboard.Name("RJT.UnicodeProbe." + UUID().uuidString)
let board = NSPasteboard(name: name)
defer { board.releaseGlobally() }
let nfd = "RJT History recognized\r\nCafe\u{301} 👩🏽‍💻\u{00A0}42\r\n"
let nfc = "RJT History recognized\r\nCafé 👩🏽‍💻\u{00A0}42\r\n"
var samples: [[String: Any]] = []
for (label, input) in [("NFD", nfd), ("NFC", nfc)] {
    let bridged = input as NSString
    let returned = bridged as String
    board.clearContents()
    let written = board.setString(input, forType: .string)
    guard let output = board.string(forType: .string), let raw = board.data(forType: .string) else {
        fatalError("Unique-board roundtrip missing")
    }
    samples.append(["label": label, "input": units(input), "NSStringRoundtrip": units(returned),
                    "setStringSucceeded": written, "pasteboardOutput": units(output),
                    "pasteboardRawData": Array(raw), "rawType": NSPasteboard.PasteboardType.string.rawValue,
                    "exactUTF8": output.utf8.elementsEqual(input.utf8),
                    "exactUTF16": output.utf16.elementsEqual(input.utf16),
                    "rawEqualsInputUTF8": raw.elementsEqual(input.utf8)])
}
let receipt: [String: Any] = ["board": name.rawValue, "generalPasteboardUsed": false,
    "frontmostApplicationChanged": false, "system": ProcessInfo.processInfo.operatingSystemVersionString,
    "scope": "Local tiny named-pasteboard probe; not the CI macOS26.6.2 host or a SwiftUI view test.", "samples": samples]
let output = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
