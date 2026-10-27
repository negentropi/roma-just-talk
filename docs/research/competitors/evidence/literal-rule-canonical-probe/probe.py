from pathlib import Path
import hashlib,json,subprocess
current=Path('VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift').read_text()
old=current.replace('''        for (index, rule) in rules.enumerated() where rule.matchingKind == .literal {
            guard !rule.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            candidates += literalMatches(for: rule.originalText, in: text).map {
                LiteralMatch(range: $0, replacement: rule.replacementText, ruleIndex: index)
''','''        let fullRange = NSRange(text.startIndex..., in: text)
        for (index, rule) in rules.enumerated() where rule.matchingKind == .literal {
            guard !rule.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let pattern = "(?=(\\(matchPattern(for: rule.originalText))))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            candidates += regex.matches(in: text, range: fullRange).map {
                LiteralMatch(range: $0.range(at: 1), replacement: rule.replacementText, ruleIndex: index)
''',1)
a=old.index('    private static func literalMatches(for original: String, in text: String) -> [NSRange] {')
b=old.index('    private static func applyLegacy(',a)
old=old[:a]+old[b:]
old_sha=hashlib.sha256(old.encode()).hexdigest()
assert old_sha=='fbe661fa91ea1d3e573c764e1f03d611449329bccd7952d859be86181a6d4a66',old_sha
checks=r'''
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
'''
observations={}
for lane,source in [('known_bad',old),('candidate',current)]:
    engine=source[source.index('public enum VoiceInkWordReplacementMatchingKind:'):source.index('public struct VoiceInkWordReplacementInsertPlan:')]
    result=subprocess.run(['/usr/bin/swift','-'],input='import Foundation\n'+engine+checks,text=True,capture_output=True,timeout=2)
    assert result.returncode==0,(lane,result.stderr)
    observations[lane]={'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'observed':json.loads(result.stdout)}
assert observations['known_bad']['observed']=={'canonical':False,'canonicalLongest':False,'repeatOverlapControl':True,'exactUTF8':False,'exactUTF16':False}
assert all(observations['candidate']['observed'].values())
print(json.dumps({'oracle_sha256':hashlib.sha256(checks.encode()).hexdigest(),'lanes':observations,'scope':'Tiny actual production-engine Foundation probe; no app integration or full Core build'},sort_keys=True))
