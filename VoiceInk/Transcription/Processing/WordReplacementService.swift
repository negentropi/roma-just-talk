import Foundation
import SwiftData
import VoiceInkCore

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    private var cachedRules: [VoiceInkWordReplacementRule]?

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

        return VoiceInkWordReplacementEngine.apply(replacements, to: text)
    }

    private func replacementRules(using context: ModelContext) -> [VoiceInkWordReplacementRule] {
        if let cachedRules {
            return cachedRules
        }

        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        let rules = (try? context.fetch(descriptor))?.map {
            VoiceInkWordReplacementRule(originalText: $0.originalText, replacementText: $0.replacementText)
        } ?? []
        let sortedRules = VoiceInkWordReplacementEngine.sortedRules(rules)

        cachedRules = sortedRules
        return sortedRules
    }
}
