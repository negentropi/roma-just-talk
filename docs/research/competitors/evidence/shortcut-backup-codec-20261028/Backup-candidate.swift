import AppKit
import Carbon.HIToolbox
import Foundation

struct LegacyKeyboardShortcut: Codable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

struct ShortcutBackup: Codable {
    let shortcut: Shortcut

    private enum CodingKeys: String, CodingKey { case kind }

    init(_ shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Only missing kind denotes a legacy Carbon backup; explicit modern data must validate.
        if values.contains(.kind) {
            self.shortcut = try Shortcut(from: decoder)
            return
        }

        let legacyShortcut = try LegacyKeyboardShortcut(from: decoder)
        self.shortcut = Shortcut.fromLegacyShortcut(legacyShortcut)
    }

    func encode(to encoder: Encoder) throws {
        try shortcut.encode(to: encoder)
    }
}
