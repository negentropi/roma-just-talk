import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    private struct ReplacementRule {
        let originalText: String
        let replacementText: String
    }

    private var cachedRules: [ReplacementRule]?

    func warmCache(using context: ModelContext) {
        _ = replacementRules(using: context)
    }

    func invalidateCache() {
        cachedRules = nil
    }

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let replacements = replacementRules(using: context)
        guard !replacements.isEmpty else {
            return text
        }

        var modifiedText = text

        for replacement in replacements {
            apply(replacement, to: &modifiedText)
        }

        return modifiedText
    }

    private func replacementRules(using context: ModelContext) -> [ReplacementRule] {
        if let cachedRules {
            return cachedRules
        }

        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        let rules = (try? context.fetch(descriptor))?.map {
            ReplacementRule(originalText: $0.originalText, replacementText: $0.replacementText)
        } ?? []
        let sortedRules = rules.sorted {
            $0.originalText.count > $1.originalText.count
        }

        cachedRules = sortedRules
        return sortedRules
    }

    private func apply(_ replacement: ReplacementRule, to modifiedText: inout String) {
        let originalGroup = replacement.originalText
        let replacementText = replacement.replacementText

        let variants = originalGroup
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for original in variants {
            let usesBoundaries = usesWordBoundaries(for: original)

            if usesBoundaries {
                // Lookarounds instead of \b so punctuation acts as a word boundary
                let escaped = NSRegularExpression.escapedPattern(for: original)
                let pattern = "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: replacementText
                    )
                }
            } else {
                // Fallback substring replace for non-spaced scripts
                modifiedText = modifiedText.replacingOccurrences(of: original, with: replacementText, options: .caseInsensitive)
            }
        }
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul Syllables
            0x0E00...0x0E7F, // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
