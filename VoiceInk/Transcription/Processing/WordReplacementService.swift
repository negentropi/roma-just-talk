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
        return VoiceInkWordReplacementEngine.apply(replacements, to: text)
    }

    private func replacementRules(using context: ModelContext) -> [VoiceInkWordReplacementRule] {
        if let cachedRules {
            return cachedRules
        }

        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        let rules = (try? context.fetch(descriptor))?.map(\.voiceInkRule) ?? []

        cachedRules = rules
        return rules
    }
}
