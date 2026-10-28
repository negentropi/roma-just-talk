import Foundation

// The driver inserts the unchanged production declaration and mutation body.
extension Notification.Name {
/* ACTUAL_NOTIFICATION */
}

final class SnippetMutationOwner {
    var snippets: [VoiceInkSpokenSnippet] = []
/* ACTUAL_MUTATION */
}

let defaults = UserDefaults.standard
let key = VoiceInkSpokenSnippets.userDefaultsKey
let previous = defaults.object(forKey: key)
precondition(Thread.isMainThread && previous == nil, "Use a fresh private defaults domain on the main thread")
defer {
    if let previous { defaults.set(previous, forKey: key) }
    else { defaults.removeObject(forKey: key) }
}
let added = VoiceInkSpokenSnippet(id: UUID(uuidString: "3D592B40-AD92-461D-945E-1F1276B01021")!,
    trigger: "review phrase", content: "Exact e\u{301} 🧪\nsecond line")
let existing = VoiceInkSpokenSnippet(id: UUID(uuidString: "F05B9063-763D-4B50-B197-56C7373165FC")!,
    trigger: "existing phrase", content: "Unchanged e\u{301}\nline")
let invalidData = Data(#"[{"id":"1A8B84BC-2A90-4EB3-BCB6-AB6007158682","trigger":"","content":"Existing invalid entry","enabled":true}]"#.utf8)
let validData = Data(#"[{"id":"F05B9063-763D-4B50-B197-56C7373165FC","trigger":"existing phrase","content":"Unchanged e\u0301\nline","enabled":true}]"#.utf8)
let cases: [(String, Any?)] = [
    ("malformed-json", Data("{ not JSON".utf8)),
    ("invalid-library", invalidData),
    ("wrong-storage-type", "original string storage"),
    ("missing-library", nil),
    ("valid-library", validData)
]
var results: [[String: Any]] = []
for (name, original) in cases {
    if let original { defaults.set(original, forKey: key) }
    else { defaults.removeObject(forKey: key) }
    let owner = SnippetMutationOwner()
    var threw = false
    var expectedLoadError = false
    do { try owner.mutate { $0.append(added) } }
    catch {
        threw = true
        expectedLoadError = (error as? VoiceInkSpokenSnippets.LoadError) == .unreadableLibrary
    }
    let stored = defaults.object(forKey: key)
    let preserved: Bool
    if let original = original as? Data { preserved = (stored as? Data) == original }
    else if let original = original as? String { preserved = (stored as? String) == original }
    else { preserved = stored == nil }
    let readback = VoiceInkSpokenSnippets.load()
    let containsAdded = readback.contains {
        $0.id == added.id && $0.trigger.utf8.elementsEqual(added.trigger.utf8)
            && $0.content.utf8.elementsEqual(added.content.utf8) && $0.enabled == added.enabled
    }
    let controlPassed = !threw && containsAdded && owner.snippets == readback
        && (name != "valid-library" || (readback.first?.id == existing.id
            && readback.first?.content.utf8.elementsEqual(existing.content.utf8) == true))
    let inputBytes = (original as? Data) ?? Data(((original as? String) ?? "").utf8)
    results.append(["case": name, "inputKind": original is Data ? "data" : original is String ? "string" : "missing",
        "inputBytesBase64": inputBytes.base64EncodedString(), "threw": threw, "expectedLoadError": expectedLoadError,
        "originalStoragePreserved": preserved, "containsAddedSnippet": containsAdded,
        "controlPassed": controlPassed])
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
