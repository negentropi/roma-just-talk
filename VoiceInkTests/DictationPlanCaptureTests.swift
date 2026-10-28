import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictationPlanCaptureTests {
        @Test @MainActor func customAndNoneKeepLegacyOwnershipWithoutProviderPreparation() async throws {
            let fixture = try DictationCaptureFixture()
            defer { fixture.restore() }
            fixture.context.insert(WordReplacement(originalText: "original", replacementText: "captured"))
            try fixture.context.save()
            fixture.defaults.set(Data("invalid snippets".utf8), forKey: VoiceInkSpokenSnippets.userDefaultsKey)
            let service = fixture.service()
            let before = fixture.preferenceSnapshot()
            for profile in [VoiceInkDictationProfile.custom, .none] {
                let plan = DictationPostprocessingPlan.capture(profile: profile, using: fixture.context, enhancementService: service)
                #expect(plan.profile == profile)
                #expect(plan.clarityStyle == nil)
                let output = try await plan.process(recognitionText: "Um, original", using: nil)
                if profile == .custom {
                    #expect(output == nil)
                } else {
                    #expect(output?.literalOutput == "Um, original")
                    #expect(output?.fallbackReason == nil)
                }
            }
            let light = DictationPostprocessingPlan.capture(profile: .light, using: fixture.context, enhancementService: service)
            guard case .light(let captured) = light else { Issue.record("Expected Light plan."); return }
            #expect(try captured.libraries.replacementRules.get() == [
                VoiceInkWordReplacementRule(originalText: "original", replacementText: "captured")
            ])
            #expect(service.snapshotCalls == 0)
            #expect(fixture.preferenceSnapshot() == before)
        }

        @Test @MainActor func lightRequiresAPersistedLanguageRatherThanRegisteredEnglish() async throws {
            let fixture = try DictationCaptureFixture()
            defer { fixture.restore() }
            let languageKey = VoiceInkUserDefaultsKey.selectedTranscriptionLanguage
            fixture.defaults.removeObject(forKey: languageKey)
            #expect(AppDefaults.registeredDefaults[languageKey] as? String == "en")
            #expect(fixture.defaults.volatileDomain(forName: UserDefaults.registrationDomain)[languageKey] as? String == "en")
            #expect(fixture.defaults.string(forKey: languageKey) == "en")
            let raw = "Um, keep this."
            for choice: Any? in [nil, 42, "auto", "pt-BR", "en-US"] {
                if let choice { fixture.defaults.set(choice, forKey: languageKey) }
                else { fixture.defaults.removeObject(forKey: languageKey) }
                let plan = DictationPostprocessingPlan.capture(profile: .light, using: fixture.context, enhancementService: nil)
                guard case .light(let captured) = plan else { Issue.record("Expected Light plan."); return }
                let expectedLanguage = choice as? String
                #expect(captured.storedLanguage == expectedLanguage)
                #expect(plan.profile == .light)
                #expect(plan.clarityStyle == nil)
                let processed = try await plan.process(recognitionText: raw, using: nil)
                let output = try #require(processed)
                #expect(output.literalOutput == (expectedLanguage == "en-US" ? "keep this." : raw))
                #expect(output.fallbackReason == nil)
            }
        }

        @Test @MainActor func factoryFreezesEnabledLibrariesLanguageAndLeavesPreferencesUntouched() async throws {
            let fixture = try DictationCaptureFixture()
            defer { fixture.restore() }
            let row = WordReplacement(originalText: "Roma", replacementText: "First")
            fixture.context.insert(row)
            fixture.context.insert(WordReplacement(originalText: "disabled", replacementText: "WRONG", isEnabled: false))
            try fixture.context.save()
            try VoiceInkSpokenSnippets.save([
                .init(trigger: "signature", content: "Original e\u{301} snippet"),
                .init(trigger: "disabled snippet", content: "WRONG", enabled: false)
            ])
            fixture.defaults.set("en-US", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            VoiceInkClarityStyle.formal.save()
            let before = fixture.preferenceSnapshot()
            let captured = DictationPostprocessingPlan.capture(profile: .light, using: fixture.context, enhancementService: nil)
            #expect(fixture.preferenceSnapshot() == before)
            row.replacementText = "Later"
            try fixture.context.save()
            try VoiceInkSpokenSnippets.save([.init(trigger: "signature", content: "Later snippet")])
            fixture.defaults.set("auto", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            let next = DictationPostprocessingPlan.capture(profile: .light, using: fixture.context, enhancementService: nil)
            let processedFirst = try await captured.process(recognitionText: "Um, Roma", using: nil)
            let processedLater = try await next.process(recognitionText: "Um, Roma", using: nil)
            let first = try #require(processedFirst)
            let later = try #require(processedLater)
            #expect(first.literalOutput == "First")
            #expect(later.literalOutput == "Um, Later")
            let processedOldSnippet = try await captured.process(recognitionText: "signature", using: nil)
            let oldSnippet = try #require(processedOldSnippet)
            #expect(oldSnippet.literalOutput.utf8.elementsEqual("Original e\u{301} snippet".utf8))
            let processedNewSnippet = try await next.process(recognitionText: "signature", using: nil)
            let newSnippet = try #require(processedNewSnippet)
            #expect(newSnippet.literalOutput == "Later snippet")
            let processedDisabled = try await captured.process(recognitionText: "disabled", using: nil)
            let disabled = try #require(processedDisabled)
            #expect(disabled.literalOutput == "disabled")
            let processedDisabledSnippet = try await captured.process(recognitionText: "disabled snippet", using: nil)
            let disabledSnippet = try #require(processedDisabledSnippet)
            #expect(disabledSnippet.literalOutput == "disabled snippet")
        }

        @Test @MainActor func clarityFactoryCapturesStyleAndConfigurationBeforeLaterEdits() async throws {
            let fixture = try DictationCaptureFixture()
            defer { fixture.restore() }
            let service = fixture.service()
            VoiceInkClarityStyle.formal.save()
            let before = fixture.preferenceSnapshot()
            let captured = DictationPostprocessingPlan.capture(profile: .clarity, using: fixture.context, enhancementService: service)
            #expect(fixture.preferenceSnapshot() == before)
            #expect(service.snapshotCalls == 1)
            #expect(captured.profile == .clarity)
            #expect(captured.clarityStyle == .formal)
            VoiceInkClarityStyle.casual.save()
            fixture.defaults.set(20, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            let next = DictationPostprocessingPlan.capture(profile: .clarity, using: fixture.context, enhancementService: service)
            _ = try await captured.process(recognitionText: "First", using: service)
            _ = try await next.process(recognitionText: "Second", using: service)
            #expect(service.requests.map(\.style) == [.formal, .casual])
            #expect(service.snapshots.map(\.timeoutSeconds) == [10, 20])
        }

        @Test @MainActor func requestCallbackRunsOnlyAtARealClarityRequest() async throws {
            let fixture = try DictationCaptureFixture()
            defer { fixture.restore() }
            let service = fixture.service()
            try VoiceInkSpokenSnippets.save([.init(trigger: "signature", content: "Saved content")])
            var callbacks = 0
            for profile in VoiceInkDictationProfile.allCases {
                let plan = DictationPostprocessingPlan.capture(profile: profile, using: fixture.context, enhancementService: service)
                _ = try await plan.process(recognitionText: "signature", using: service, willRequestClarity: { callbacks += 1 })
            }
            for profile in [VoiceInkDictationProfile.custom, .none, .light] {
                let plan = DictationPostprocessingPlan.capture(profile: profile, using: fixture.context, enhancementService: service)
                _ = try await plan.process(recognitionText: "ordinary", using: service, willRequestClarity: { callbacks += 1 })
            }
            let clarity = DictationPostprocessingPlan.capture(profile: .clarity, using: fixture.context, enhancementService: service)
            _ = try await clarity.process(recognitionText: " \r\n ", using: service, willRequestClarity: { callbacks += 1 })
            let missing = DictationPostprocessingPlan.capture(profile: .clarity, using: fixture.context, enhancementService: nil)
            _ = try await missing.process(recognitionText: "ordinary", using: service, willRequestClarity: { callbacks += 1 })
            let invalid = DictationPostprocessingPlan.clarity(.init(
                libraries: .init(snippets: [], replacementRules: .failure(.replacementLibrary("fixture"))),
                style: .formal, provider: .success(try service.providerSnapshot())
            ))
            _ = try await invalid.process(recognitionText: "ordinary", using: service, willRequestClarity: { callbacks += 1 })
            await #expect(throws: CancellationError.self) {
                try await clarity.process(recognitionText: "ordinary", using: service, shouldCancel: { true },
                                          willRequestClarity: { callbacks += 1 })
            }
            #expect(callbacks == 0)
            #expect(service.requests.isEmpty)
            var canceledByCallback = false
            var cancellationCallbacks = 0
            await #expect(throws: CancellationError.self) {
                try await clarity.process(
                    recognitionText: "ordinary", using: service, shouldCancel: { canceledByCallback },
                    willRequestClarity: { cancellationCallbacks += 1; canceledByCallback = true }
                )
            }
            #expect(cancellationCallbacks == 1)
            #expect(service.requests.isEmpty)
            _ = try await clarity.process(recognitionText: "ordinary", using: service, willRequestClarity: { callbacks += 1 })
            #expect(callbacks == 1)
            #expect(service.requests.count == 1)
        }
    }
}

@MainActor
private final class DictationCaptureFixture {
    let defaults = UserDefaults.standard
    let container: ModelContainer
    let context: ModelContext
    private let domain: String
    private let saved: [String: Any]
    private static let keys = [
        VoiceInkSpokenSnippets.userDefaultsKey, VoiceInkUserDefaultsKey.selectedTranscriptionLanguage,
        VoiceInkClarityStyle.storageKey, VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled, VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId, VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey
    ]

    init() throws {
        domain = try #require(Bundle.main.bundleIdentifier)
        let values = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in values[key].map { (key, $0) } })
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(
            "RJT-Capture-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    func service() -> DictationCaptureEnhancementSpy {
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set("/bin/cat", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(5, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        return DictationCaptureEnhancementSpy(aiService: AIService(), modelContext: context)
    }

    func preferenceSnapshot() -> NSDictionary {
        let values = defaults.persistentDomain(forName: domain) ?? [:]
        return NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in values[key].map { (key, $0) } }))
    }

    func restore() {
        for key in Self.keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
}

@MainActor
private final class DictationCaptureEnhancementSpy: AIEnhancementService {
    var snapshotCalls = 0
    var requests = [VoiceInkClarityRequest]()
    var snapshots = [AIEnhancementProviderSnapshot]()

    override func providerSnapshot() throws -> AIEnhancementProviderSnapshot {
        snapshotCalls += 1
        return try super.providerSnapshot()
    }

    override func performClarity(request: VoiceInkClarityRequest, using snapshot: AIEnhancementProviderSnapshot) async throws -> VoiceInkAIEnhancementResult {
        requests.append(request)
        snapshots.append(snapshot)
        return .init(text: "Cleaned", duration: 0.125, modelName: snapshot.modelName, promptName: nil,
                     requestSystemMessage: request.systemMessage, requestUserMessage: request.userMessage)
    }
}
