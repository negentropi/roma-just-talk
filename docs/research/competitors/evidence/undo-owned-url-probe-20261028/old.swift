import Foundation
import Darwin
func scopedURL(_ raw: Any?, resource: URL) -> String {
        let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
        guard let url else { return "<unavailable>" }
        return url.isFileURL && url.standardizedFileURL == resource.standardizedFileURL
            ? url.absoluteString : "<unrelated URL redacted>"
    }

let resource = URL(fileURLWithPath: CommandLine.arguments[2])
let alias = URL(string: resource.absoluteString.replacingOccurrences(of: "file:///var/", with: "file:///private/var/"))!
let foreign = resource.deletingLastPathComponent().appendingPathComponent("foreign.txt")
let inputs: [(String, Any?, String)] = [
    ("exact-resource", resource, resource.absoluteString),
    ("actual-AX-private-var-alias", alias.absoluteString, resource.absoluteString),
    ("foreign-file", foreign, "<unrelated URL redacted>"),
    ("nonfile", "https://example.invalid/owned.txt", "<unrelated URL redacted>"),
    ("unavailable", nil, "<unavailable>")
]
let results = inputs.map { name, raw, expected in
    let observed = scopedURL(raw, resource: resource)
    return ["name": name, "expected": expected, "observed": observed, "passed": observed == expected] as [String: Any]
}
let payload: [String: Any] = ["mode": CommandLine.arguments[1], "platform": "macOS Foundation", "actualAXURL": alias.absoluteString, "resourceURL": resource.absoluteString, "typedOwnedIdentityMatches": alias.standardizedFileURL == resource.standardizedFileURL, "cases": results, "failed": results.filter { $0["passed"] as? Bool != true }.count, "scope": "Exact scopedURL body with raw AX getter replaced by supplied observed URL; real Foundation URL implementation. No app or AX operation."]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
