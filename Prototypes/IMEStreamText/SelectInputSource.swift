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
print("enable:", TISEnableInputSource(source))
print("select:", TISSelectInputSource(source))
Thread.sleep(forTimeInterval: 1)
let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let currentID = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(current, kTISPropertyInputSourceID)).takeUnretainedValue()
print("current:", currentID)
exit(currentID as String == id ? 0 : 1)
