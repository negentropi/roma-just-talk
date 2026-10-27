public enum VoiceInkWordReplacementMatchingKind: String, Codable, Sendable {
    case legacyCommaAlternatives
    case literal
}

public struct VoiceInkWordReplacementRule: Codable, Equatable, Sendable {
    public let originalText: String
    public let replacementText: String
    public let matchingKind: VoiceInkWordReplacementMatchingKind

    public init(
        originalText: String,
        replacementText: String,
        matchingKind: VoiceInkWordReplacementMatchingKind = .legacyCommaAlternatives
    ) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.matchingKind = matchingKind
    }

    private enum CodingKeys: String, CodingKey {
        case originalText, replacementText, matchingKind
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        originalText = try values.decode(String.self, forKey: .originalText)
        replacementText = try values.decode(String.self, forKey: .replacementText)
        matchingKind = values.contains(.matchingKind)
            ? try values.decode(VoiceInkWordReplacementMatchingKind.self, forKey: .matchingKind)
            : .legacyCommaAlternatives
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(originalText, forKey: .originalText)
        try values.encode(replacementText, forKey: .replacementText)
        if matchingKind != .legacyCommaAlternatives {
            try values.encode(matchingKind, forKey: .matchingKind)
        }
    }
}

public enum VoiceInkWordReplacementEngine {
    private static let nonSpacedScripts: [ClosedRange<UInt32>] = [
        0x3040...0x309F,
        0x30A0...0x30FF,
        0x4E00...0x9FFF,
        0xAC00...0xD7AF,
        0x0E00...0x0E7F,
    ]

    private static let spacedWordCharacterClass: String = {
        let nonSpacedRanges = nonSpacedScripts.map {
            "\\x{\(String($0.lowerBound, radix: 16))}-\\x{\(String($0.upperBound, radix: 16))}"
        }.joined()
        // ICU needs the outer union to keep Thai decimal digits after range subtraction.
        return #"[[[\p{L}\p{M}]-["# + nonSpacedRanges + #"]]\p{Nd}]"#
    }()

    public static func apply(_ rules: [VoiceInkWordReplacementRule], to text: String) -> String {
        guard rules.contains(where: { $0.matchingKind == .literal }) else {
            return applyLegacy(rules, to: text)
        }

        var candidates: [LiteralMatch] = []
        for (index, rule) in rules.enumerated() where rule.matchingKind == .literal {
            guard !rule.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            candidates += literalMatches(for: rule.originalText, in: text).map {
                LiteralMatch(range: $0, replacement: rule.replacementText, ruleIndex: index)
            }
        }
        candidates.sort {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            return $0.ruleIndex < $1.ruleIndex
        }
        var protected: [LiteralMatch] = []
        var end = 0
        for candidate in candidates where candidate.range.location >= end {
            protected.append(candidate)
            end = NSMaxRange(candidate.range)
        }

        let legacyRules = rules.filter { $0.matchingKind == .legacyCommaAlternatives }
        guard !protected.isEmpty else { return applyLegacy(legacyRules, to: text) }
        var modifiedText = text
        // Protected source stays present for boundary checks. Literal output is inserted only at the end.
        for rule in orderedRules(legacyRules) {
            for original in variants(for: rule) {
                let matches = legacyMatches(for: original, in: modifiedText).filter { match in
                    !protected.contains { NSIntersectionRange($0.range, match).length > 0 }
                }
                for match in matches.reversed() {
                    modifiedText = (modifiedText as NSString).replacingCharacters(in: match, with: rule.replacementText)
                    let delta = rule.replacementText.utf16.count - match.length
                    for index in protected.indices where protected[index].range.location >= NSMaxRange(match) {
                        protected[index].range.location += delta
                    }
                }
            }
        }
        for match in protected.reversed() {
            modifiedText = (modifiedText as NSString).replacingCharacters(in: match.range, with: match.replacement)
        }
        return modifiedText
    }

    private struct LiteralMatch {
        var range: NSRange
        let replacement: String
        let ruleIndex: Int
    }

    private static func matchPattern(for original: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: original)
        return usesWordBoundaries(for: original)
            ? "(?<!\(spacedWordCharacterClass))\(escaped)(?!\(spacedWordCharacterClass))"
            : escaped
    }

    private static func legacyMatches(for original: String, in text: String) -> [NSRange] {
        if usesWordBoundaries(for: original) {
            guard let regex = try? NSRegularExpression(pattern: matchPattern(for: original), options: .caseInsensitive) else {
                return []
            }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        }
        var matches: [NSRange] = []
        var start = text.startIndex
        while let range = text.range(of: original, options: .caseInsensitive, range: start..<text.endIndex) {
            matches.append(NSRange(range, in: text))
            start = range.upperBound
        }
        return matches
    }

    private static func literalMatches(for original: String, in text: String) -> [NSRange] {
        if usesWordBoundaries(for: original) {
            let pattern = "(?=(\(matchPattern(for: original))))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { $0.range(at: 1) }
        }
        var matches: [NSRange] = []
        var start = text.startIndex
        // Foundation search retains legacy canonical matching; scalar advancement keeps overlapping source spans.
        while let range = text.range(of: original, options: .caseInsensitive, range: start..<text.endIndex) {
            matches.append(NSRange(range, in: text))
            start = text.unicodeScalars.index(after: range.lowerBound)
        }
        return matches
    }

    private static func applyLegacy(_ rules: [VoiceInkWordReplacementRule], to text: String) -> String {
        guard !rules.isEmpty else {
            return text
        }

        var modifiedText = text

        for rule in orderedRules(rules) {
            apply(rule, to: &modifiedText)
        }

        return modifiedText
    }

    private static func orderedRules(_ rules: [VoiceInkWordReplacementRule]) -> [VoiceInkWordReplacementRule] {
        rules.sorted { $0.originalText.count > $1.originalText.count }
    }

    private static func apply(_ rule: VoiceInkWordReplacementRule, to modifiedText: inout String) {
        for original in variants(for: rule) {
            if usesWordBoundaries(for: original) {
                if let regex = try? NSRegularExpression(pattern: matchPattern(for: original), options: .caseInsensitive) {
                    let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacementText)
                    )
                }
            } else {
                modifiedText = modifiedText.replacingOccurrences(
                    of: original,
                    with: rule.replacementText,
                    options: .caseInsensitive
                )
            }
        }
    }

    private static func variants(for rule: VoiceInkWordReplacementRule) -> [String] {
        rule.originalText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    private static func usesWordBoundaries(for text: String) -> Bool {
        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts where range.contains(scalar.value) {
                return false
            }
        }

        return true
    }
}

