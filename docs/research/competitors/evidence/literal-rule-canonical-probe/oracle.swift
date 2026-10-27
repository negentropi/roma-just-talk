
func run(_ json: String, _ input: String) throws -> String {
    let rules = try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: Data(json.utf8))
    return VoiceInkWordReplacementEngine.apply(rules, to: input)
}
let canonical = try run(#"[{"originalText":"é東京","replacementText":"R","matchingKind":"literal"}]"#, "e\u{301}東京 É東京 e\u{301}東京")
let longest = try run(#"[{"originalText":"é東京","replacementText":"SHORT","matchingKind":"literal"},{"originalText":"e\u0301東京é","replacementText":"LONG","matchingKind":"literal"}]"#, "e\u{301}東京e\u{301}東京")
let repeated = try run(#"[{"originalText":"ああ","replacementText":"X","matchingKind":"literal"},{"originalText":"あああ","replacementText":"Y","matchingKind":"literal"}]"#, "あああああ")
let exact = try run(#"[{"originalText":"é東京","replacementText":"tail e\u0301 👩🏽‍💻","matchingKind":"literal"},{"originalText":"source","replacementText":"👩🏽‍💻"},{"originalText":"tail","replacementText":"X"}]"#, "source e\u{301}東京 tail É東京 e\u{301}東京")
let expected = "👩🏽‍💻 tail e\u{301} 👩🏽‍💻 X tail e\u{301} 👩🏽‍💻 tail e\u{301} 👩🏽‍💻"
let observed: [String: Bool] = ["canonical": canonical == "R R R", "canonicalLongest": longest == "LONG東京", "repeatOverlapControl": repeated == "YX", "exactUTF8": Array(exact.utf8) == Array(expected.utf8), "exactUTF16": Array(exact.utf16) == Array(expected.utf16)]
print(String(decoding: try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), as: UTF8.self))
