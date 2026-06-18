import Foundation

public struct VoiceInkWordReplacementRule: Codable, Equatable, Sendable {
    public let originalText: String
    public let replacementText: String

    public init(originalText: String, replacementText: String) {
        self.originalText = originalText
        self.replacementText = replacementText
    }
}

public enum VoiceInkWordReplacementEngine {
    public static func apply(_ rules: [VoiceInkWordReplacementRule], to text: String) -> String {
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
        let variants = rule.originalText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for original in variants {
            if usesWordBoundaries(for: original) {
                let escaped = NSRegularExpression.escapedPattern(for: original)
                let pattern = "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: rule.replacementText
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

    private static func usesWordBoundaries(for text: String) -> Bool {
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,
            0x30A0...0x30FF,
            0x4E00...0x9FFF,
            0xAC00...0xD7AF,
            0x0E00...0x0E7F,
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts where range.contains(scalar.value) {
                return false
            }
        }

        return true
    }
}
