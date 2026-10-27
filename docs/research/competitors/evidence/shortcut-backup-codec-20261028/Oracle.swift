import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
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

@main struct Probe {
 static func main() throws {
  var failed = [String]()
  var executed = 0
  func check(_ condition: Bool, _ name: String) {
   executed += 1
   if condition { print("PASS " + name) }
   else { failed.append(name); print("FAIL " + name) }
  }
  func decode(_ object: [String: Any]) throws -> Shortcut {
   try JSONDecoder().decode(ShortcutBackup.self, from: JSONSerialization.data(withJSONObject: object)).shortcut
  }
  for (index, object) in ShortcutBackupDecodeFixtures.invalidModernWithLegacy.enumerated() {
   do { _ = try decode(object); check(false, "invalid-modern-" + String(index)) }
   catch { check(true, "invalid-modern-" + String(index)) }
  }
  let legacy = try decode(ShortcutBackupDecodeFixtures.legacy)
  check(legacy.kind == .key && legacy.keyCode == 16 && legacy.modifierFlags == .command, "legacy-carbon-control")
  for (index, value) in ShortcutBackupDecodeFixtures.validModern.enumerated() {
   let decoded = try decode(value.0)
   check(decoded.kind == value.1 && decoded.keyCode == value.2 && decoded.modifierFlags == value.3, "valid-modern-" + String(index))
  }
  for (index, object) in ShortcutBackupDecodeFixtures.invalidLegacy.enumerated() {
   do { _ = try decode(object); check(false, "invalid-legacy-" + String(index)) }
   catch { check(true, "invalid-legacy-" + String(index)) }
  }
  print("Executed " + String(executed) + "; failures " + String(failed.count))
  exit(failed.isEmpty ? 0 : 1)
 }
}
