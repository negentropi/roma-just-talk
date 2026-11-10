// PROTOTYPE — throwaway. Usage: SelectInputSource PATH_TO_APP SOURCE_ID
import Carbon
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let id = CommandLine.arguments[2]
print("register:", TISRegisterInputSource(url))
func sources() -> [TISInputSource] {
    (TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}
var found = sources()
for _ in 0..<20 where found.isEmpty { Thread.sleep(forTimeInterval: 0.5); found = sources() }
guard let source = found.first else { print("not found"); exit(1) }
func property(_ key: CFString) -> String {
    guard let raw = TISGetInputSourceProperty(source, key) else { return "nil" }
    return "\(Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue())"
}
print("category:", property(kTISPropertyInputSourceCategory), "type:", property(kTISPropertyInputSourceType),
      "selectCapable:", property(kTISPropertyInputSourceIsSelectCapable), "enableCapable:", property(kTISPropertyInputSourceIsEnableCapable))
print("enable:", TISEnableInputSource(source))
for attempt in 0..<20 {
    Thread.sleep(forTimeInterval: 0.5)
    let selected = TISSelectInputSource(source)
    print("select attempt \(attempt):", selected, "enabled:", property(kTISPropertyInputSourceIsEnabled))
    if selected == noErr { break }
}
Thread.sleep(forTimeInterval: 1)
let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let currentID = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(current, kTISPropertyInputSourceID)).takeUnretainedValue()
print("current:", currentID)
exit(currentID as String == id ? 0 : 1)
