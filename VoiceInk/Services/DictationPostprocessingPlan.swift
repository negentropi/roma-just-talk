import Foundation
import SwiftData
import VoiceInkCore

/// Capture consumed settings before an operation suspends; execution uses these copied values.
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

        @MainActor
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

    struct Light {
        let libraries: Libraries
        let storedLanguage: String?
    }

    struct Clarity {
        let libraries: Libraries
        let style: VoiceInkClarityStyle
        let provider: Result<AIEnhancementProviderSnapshot, PreparationFailure>
    }

    struct Output: Sendable {
        let recognitionText: String
        let preparedText: String
        let enhancementResult: VoiceInkAIEnhancementResult?
        let fallbackReason: String?

        var literalOutput: String { enhancementResult?.text ?? preparedText }

        fileprivate static func literal(_ text: String, recognitionText: String, fallbackReason: String? = nil) -> Self {
            Self(recognitionText: recognitionText, preparedText: text, enhancementResult: nil, fallbackReason: fallbackReason)
        }
    }

    case custom
    case none
    case light(Light)
    case clarity(Clarity)

    var profile: VoiceInkDictationProfile {
        switch self {
        case .custom: .custom
        case .none: .none
        case .light: .light
        case .clarity: .clarity
        }
    }

    var clarityStyle: VoiceInkClarityStyle? {
        if case .clarity(let plan) = self { return plan.style }
        return nil
    }

    static func capture(
        profile: VoiceInkDictationProfile,
        using context: ModelContext,
        enhancementService: AIEnhancementService?
    ) -> Self {
        switch profile {
        case .custom: return .custom
        case .none: return .none
        case .light:
            return captureLight(
                snippets: VoiceInkSpokenSnippets.load(),
                storedLanguage: explicitlyStoredLanguage(),
                using: context
            )
        case .clarity:
            return captureClarity(
                snippets: VoiceInkSpokenSnippets.load(), style: VoiceInkClarityStyle.current(),
                using: context, enhancementService: enhancementService
            )
        }
    }

    private static func explicitlyStoredLanguage() -> String? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        // AppDefaults registers English; only an actual saved choice permits hesitation cleanup.
        return UserDefaults.standard.persistentDomain(forName: domain)?[
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage
        ] as? String
    }

    static func captureLight(
        snippets: [VoiceInkSpokenSnippet],
        storedLanguage: String?,
        using context: ModelContext
    ) -> Self {
        .light(Light(libraries: .capture(snippets: snippets, context: context), storedLanguage: storedLanguage))
    }

    static func captureClarity(
        snippets: [VoiceInkSpokenSnippet],
        style: VoiceInkClarityStyle,
        using context: ModelContext,
        enhancementService: AIEnhancementService?
    ) -> Self {
        let provider: Result<AIEnhancementProviderSnapshot, PreparationFailure>
        do {
            guard let enhancementService else { throw VoiceInkAIEnhancementError.notConfigured }
            provider = .success(try enhancementService.providerSnapshot())
        } catch {
            provider = .failure(.providerConfiguration(VoiceInkErrorDescription.text(for: error)))
        }
        return .clarity(Clarity(libraries: .capture(snippets: snippets, context: context), style: style, provider: provider))
    }

    /// Nil keeps Custom with its existing entry-point-specific processing and live reads.
    func process(
        recognitionText: String,
        using enhancementService: AIEnhancementService?,
        shouldCancel: () -> Bool = { false },
        willRequestClarity: () -> Void = {}
    ) async throws -> Output? {
        func checkCancellation() throws {
            if Task.isCancelled || shouldCancel() { throw CancellationError() }
        }
        try checkCancellation()
        let libraries: Libraries
        switch self {
        case .custom: return nil
        case .none: return .literal(recognitionText, recognitionText: recognitionText)
        case .light(let plan): libraries = plan.libraries
        case .clarity(let plan): libraries = plan.libraries
        }
        if recognitionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .literal(recognitionText, recognitionText: recognitionText)
        }

        // A full-utterance snippet is terminal even when unrelated preparation failed.
        if let snippet = VoiceInkSpokenSnippets.entireSnippet(for: recognitionText, using: libraries.snippets) {
            try checkCancellation()
            return .literal(snippet.content, recognitionText: recognitionText)
        }

        do {
            let rules = try libraries.replacementRules.get()
            switch self {
            case .light(let plan):
                let cleaned = VoiceInkLightCleanup.apply(text: recognitionText, storedLanguage: plan.storedLanguage)
                let prepared = VoiceInkWordReplacementEngine.apply(rules, to: cleaned)
                try checkCancellation()
                return .literal(prepared, recognitionText: recognitionText)
            case .clarity(let plan):
                let prepared = VoiceInkWordReplacementEngine.apply(rules, to: recognitionText)
                let provider = try plan.provider.get()
                guard let enhancementService else { throw VoiceInkAIEnhancementError.notConfigured }
                let request = try VoiceInkClarityRequest(transcript: prepared, style: plan.style)
                try checkCancellation()
                willRequestClarity()
                try checkCancellation()
                let enhancement = try await enhancementService.performClarity(request: request, using: provider)
                try checkCancellation()
                return Output(recognitionText: recognitionText, preparedText: prepared, enhancementResult: enhancement, fallbackReason: nil)
            case .custom, .none:
                preconditionFailure("Only Light and Clarity reach prepared-library processing.")
            }
        } catch {
            try checkCancellation()
            if error is CancellationError { throw error }
            return .literal(recognitionText, recognitionText: recognitionText, fallbackReason: VoiceInkErrorDescription.text(for: error))
        }
    }
}
