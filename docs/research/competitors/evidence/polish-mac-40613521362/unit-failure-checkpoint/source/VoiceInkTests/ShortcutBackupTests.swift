import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

extension VoiceInkTests {
    struct ShortcutBackupTests {
        @Test func explicitModernKindRejectsMalformedDataEvenWithLegacyKeys() throws {
            for object in ShortcutBackupDecodeFixtures.invalidModernWithLegacy {
                let data = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(ShortcutBackup.self, from: data)
                }
            }
        }

        @Test func missingKindRetainsLegacyCarbonAndValidModernUsesItsOwnValues() throws {
            let legacy = try decode(ShortcutBackupDecodeFixtures.legacy)
            #expect(legacy.kind == .key)
            #expect(legacy.keyCode == 16)
            #expect(legacy.modifierFlags == .command)
            for (object, kind, keyCode, flags) in ShortcutBackupDecodeFixtures.validModern {
                let modern = try decode(object)
                #expect(modern.kind == kind)
                #expect(modern.keyCode == keyCode)
                #expect(modern.modifierFlags == flags)
                let reopened = try JSONDecoder().decode(ShortcutBackup.self, from: JSONEncoder().encode(ShortcutBackup(modern)))
                #expect(reopened.shortcut == modern)
            }
        }

        @Test func missingKindStillRequiresAValidLegacyCarbonPayload() throws {
            for object in ShortcutBackupDecodeFixtures.invalidLegacy {
                let data = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(ShortcutBackup.self, from: data)
                }
            }
        }

        private func decode(_ object: [String: Any]) throws -> Shortcut {
            try JSONDecoder().decode(ShortcutBackup.self, from: JSONSerialization.data(withJSONObject: object)).shortcut
        }
    }
}

// Shared verbatim with the actual-source decoder probe; no substitute Shortcut implementation.
private enum ShortcutBackupDecodeFixtures {
    static let legacy: [String: Any] = ["carbonKeyCode": 16, "carbonModifiers": Int(cmdKey)]

    static let invalidModernWithLegacy: [[String: Any]] = [
        ["kind": "future", "keyCode": 16, "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue],
        ["kind": NSNull(), "keyCode": 16, "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue],
        ["kind": 7, "keyCode": 16, "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue],
        ["kind": "key", "keyCode": "wrong", "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue],
        ["kind": "key", "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue],
        ["kind": "modifierOnly", "keyCode": 61, "modifierFlagsRawValue": NSNull()]
    ].map { $0.merging(legacy) { modern, _ in modern } }

    static let validModern: [([String: Any], Shortcut.Kind, UInt16, NSEvent.ModifierFlags)] = [
        (["kind": "key", "keyCode": 16, "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue], .key, 16, .command),
        (["kind": "modifierOnly", "keyCode": 61, "modifierFlagsRawValue": NSEvent.ModifierFlags.option.rawValue], .modifierOnly, 61, .option),
        (["kind": "key", "keyCode": 0, "modifierFlagsRawValue": NSEvent.ModifierFlags.shift.rawValue,
          "carbonKeyCode": 16, "carbonModifiers": Int(cmdKey)], .key, 0, .shift)
    ]

    static let invalidLegacy: [[String: Any]] = [
        [:], ["carbonKeyCode": "wrong", "carbonModifiers": Int(cmdKey)], ["carbonKeyCode": 16],
        ["keyCode": 16, "modifierFlagsRawValue": NSEvent.ModifierFlags.command.rawValue]
    ]
}
