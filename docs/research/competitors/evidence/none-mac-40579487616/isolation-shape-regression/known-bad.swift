import Foundation
struct VoiceInkSpokenSnippet { let enabled: Bool }
struct VoiceInkWordReplacementRule {}
struct WordReplacement { let isEnabled: Bool; let voiceInkRule: VoiceInkWordReplacementRule }
struct FetchDescriptor<T> {}
struct ModelContext { func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] { [] } }
enum VoiceInkErrorDescription { static func text(for error: Error) -> String { error.localizedDescription } }
@MainActor
enum DictionaryService {
    static func snapshotEnabledReplacementRules(using context: ModelContext) throws -> [VoiceInkWordReplacementRule] {
        try context.fetch(FetchDescriptor<WordReplacement>())
            .filter(\.isEnabled)
            .map(\.voiceInkRule)
    }
}
@MainActor
enum DictationPostprocessingPlan {
    enum PreparationFailure: Error, LocalizedError, Equatable, Sendable {
        case replacementLibrary(String)
        case providerConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .replacementLibrary(let reason): "Could not read the replacement library: \(reason)"
            case .providerConfiguration(let reason): "Could not prepare Clarity: \(reason)"
            }
        }
    }

    struct Libraries {
        let snippets: [VoiceInkSpokenSnippet]
        let replacementRules: Result<[VoiceInkWordReplacementRule], PreparationFailure>

        fileprivate static func capture(snippets: [VoiceInkSpokenSnippet], context: ModelContext) -> Self {
            let rules: Result<[VoiceInkWordReplacementRule], PreparationFailure>
            do {
                rules = .success(try DictionaryService.snapshotEnabledReplacementRules(using: context))
            } catch {
                rules = .failure(.replacementLibrary(VoiceInkErrorDescription.text(for: error)))
            }
            return Self(snippets: snippets.filter(\.enabled), replacementRules: rules)
        }
    }

}
