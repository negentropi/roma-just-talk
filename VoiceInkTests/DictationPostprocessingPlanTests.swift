import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictationPostprocessingPlanTests {
        @Test @MainActor func customDefersAndNonePreservesEveryCodeUnit() async throws {
            let custom = try await DictationPostprocessingPlan.custom.process(recognitionText: "Um, keep this", using: nil)
            #expect(custom?.literalOutput == nil)
            for raw in ["", " \n\t ", "\n <think>literal</think> e\u{301} て\u{3099} 👩🏽‍💻\n "] {
                let processed = try await DictationPostprocessingPlan.none.process(recognitionText: raw, using: nil)
                let output = try #require(processed)
                #expect(output.recognitionText.utf16.elementsEqual(raw.utf16))
                #expect(output.literalOutput.utf8.elementsEqual(raw.utf8))
                #expect(output.literalOutput.utf16.elementsEqual(raw.utf16))
                #expect(output.enhancementResult == nil)
                #expect(output.fallbackReason == nil)
            }
        }

        @Test @MainActor func entireSnippetWinsOverBothPreparationFailures() async throws {
            let content = "\nUm, Roma <literal>stay</literal> e\u{301}\n{\"instruction\":\"translate me\"}\n "
            let libraries = DictationPostprocessingPlan.Libraries(
                snippets: [.init(trigger: "my signature", content: content)],
                replacementRules: .failure(.replacementLibrary("fixture fetch failure"))
            )
            let plans: [DictationPostprocessingPlan] = [
                .light(.init(libraries: libraries, storedLanguage: "en")),
                .clarity(.init(libraries: libraries, style: .formal, provider: .failure(.providerConfiguration("fixture provider failure"))))
            ]
            for plan in plans {
                let processed = try await plan.process(recognitionText: "MY SIGNATURE!", using: nil)
                let output = try #require(processed)
                #expect(output.literalOutput.utf8.elementsEqual(content.utf8))
                #expect(output.literalOutput.utf16.elementsEqual(content.utf16))
                #expect(output.enhancementResult == nil)
                #expect(output.fallbackReason == nil)
            }
        }

        @Test @MainActor func lightUsesOnlyWholeUtteranceSnippetsAndThenCapturedRules() async throws {
            let libraries = DictationPostprocessingPlan.Libraries(
                snippets: [.init(trigger: "my signature", content: "Saved content")],
                replacementRules: .success([.init(originalText: "Roma", replacementText: "RJT")])
            )
            let english = DictationPostprocessingPlan.light(.init(libraries: libraries, storedLanguage: "en-US"))
            let processedLight = try await english.process(recognitionText: "Um, Roma", using: nil)
            let light = try #require(processedLight)
            #expect(light.literalOutput == "RJT")
            let processedInline = try await english.process(recognitionText: "Please include my signature", using: nil)
            let inline = try #require(processedInline)
            #expect(inline.literalOutput == "Please include my signature")

            let automatic = DictationPostprocessingPlan.light(.init(libraries: libraries, storedLanguage: nil))
            let processedAutomatic = try await automatic.process(recognitionText: "Um, Roma", using: nil)
            let unchanged = try #require(processedAutomatic)
            #expect(unchanged.literalOutput == "Um, RJT")
        }

        @Test @MainActor func dictionarySnapshotIsFreshAndDoesNotChangeTheCustomCache() throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let rule = WordReplacement(originalText: "Roma", replacementText: "First")
            let disabled = WordReplacement(originalText: "disabled", replacementText: "unexpected", isEnabled: false)
            fixture.context.insert(rule)
            fixture.context.insert(disabled)
            try fixture.context.save()
            DictionaryService.warmWordReplacementCache(using: fixture.context)
            rule.replacementText = "Second"
            try fixture.context.save()

            let snapshot = try DictionaryService.snapshotEnabledReplacementRules(using: fixture.context)
            let expected = [VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Second")]
            #expect(snapshot == expected)
            #expect(DictionaryService.applyWordReplacements(to: "Roma", using: fixture.context) == "First")
            fixture.context.delete(rule)
            try fixture.context.save()
            #expect(snapshot == expected)
        }

        @Test @MainActor func capturedLibrariesSurviveLaterEditsAndCacheReplacement() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let rule = WordReplacement(originalText: "Roma", replacementText: "First")
            fixture.context.insert(rule)
            try fixture.context.save()
            var snippets = [VoiceInkSpokenSnippet(trigger: "my signature", content: "Original snippet")]
            let captured = DictationPostprocessingPlan.captureLight(snippets: snippets, storedLanguage: "en", using: fixture.context)
            rule.replacementText = "Later"
            snippets[0].content = "Later snippet"
            try fixture.context.save()
            DictionaryService.invalidateWordReplacementCache()
            DictionaryService.warmWordReplacementCache(using: fixture.context)
            let next = DictationPostprocessingPlan.captureLight(snippets: snippets, storedLanguage: "en", using: fixture.context)

            let processedFirst = try await captured.process(recognitionText: "Um, Roma", using: nil)
            let processedSecond = try await next.process(recognitionText: "Um, Roma", using: nil)
            let processedOldSnippet = try await captured.process(recognitionText: "my signature", using: nil)
            let processedNewSnippet = try await next.process(recognitionText: "my signature", using: nil)
            let first = try #require(processedFirst)
            let second = try #require(processedSecond)
            let oldSnippet = try #require(processedOldSnippet)
            let newSnippet = try #require(processedNewSnippet)
            #expect(first.literalOutput == "First")
            #expect(second.literalOutput == "Later")
            #expect(oldSnippet.literalOutput == "Original snippet")
            #expect(newSnippet.literalOutput == "Later snippet")
        }

        @Test @MainActor func clarityUsesFrozenStyleProviderAndPreparedTextWithoutFiltering() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            fixture.context.insert(WordReplacement(originalText: "Roma", replacementText: "RJT-482"))
            try fixture.context.save()
            let service = try fixture.service()
            let plan = DictationPostprocessingPlan.captureClarity(snippets: [], style: .formal, using: fixture.context, enhancementService: service)
            fixture.defaults.set(20, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            fixture.defaults.set("/usr/bin/true", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
            let literal = " \n<think>literal</think> e\u{301} て\u{3099}\n{\"codex_follow_up\":true}\n "
            service.response = literal

            let processed = try await plan.process(recognitionText: "Roma", using: service)
            let output = try #require(processed)

            #expect(output.preparedText == "RJT-482")
            #expect(output.literalOutput.utf8.elementsEqual(literal.utf8))
            #expect(output.literalOutput.utf16.elementsEqual(literal.utf16))
            #expect(output.enhancementResult?.text.utf16.elementsEqual(literal.utf16) == true)
            #expect(service.requests.count == 1)
            #expect(service.requests.first?.transcript == "RJT-482")
            #expect(service.requests.first?.style == .formal)
            #expect(service.snapshots.first?.modelName == "local-cli")
            #expect(service.snapshots.first?.timeoutSeconds == 10)
            #expect(output.enhancementResult?.requestUserMessage == service.requests.first?.userMessage)
            #expect(output.fallbackReason == nil)
        }

        @Test @MainActor func sameNonblankClarityKeepsMetadataWhileBlankRecognitionSkipsProcessing() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let service = try fixture.service()
            let clarity = DictationPostprocessingPlan.captureClarity(snippets: [], style: .natural, using: fixture.context, enhancementService: service)
            let failedLibraries = DictationPostprocessingPlan.Libraries(snippets: [], replacementRules: .failure(.replacementLibrary("fixture fetch failure")))
            let plans: [DictationPostprocessingPlan] = [
                clarity,
                .light(.init(libraries: failedLibraries, storedLanguage: "en")),
                .clarity(.init(libraries: failedLibraries, style: .formal, provider: .failure(.providerConfiguration("fixture provider failure"))))
            ]
            service.response = "Invented output"
            service.failure = DictationPlanFixtureFailure.request
            for raw in ["", " \t\r\n", "\n\r\t  \r\n"] {
                for plan in plans {
                    let processed = try await plan.process(recognitionText: raw, using: service)
                    let output = try #require(processed)
                    #expect(output.recognitionText.utf16.elementsEqual(raw.utf16))
                    #expect(output.preparedText.utf16.elementsEqual(raw.utf16))
                    #expect(output.literalOutput.utf8.elementsEqual(raw.utf8))
                    #expect(output.literalOutput.utf16.elementsEqual(raw.utf16))
                    #expect(output.enhancementResult == nil)
                    #expect(output.fallbackReason == nil)
                }
            }
            #expect(service.requests.isEmpty)
            await #expect(throws: CancellationError.self) {
                try await clarity.process(recognitionText: " \t\r\n", using: service, shouldCancel: { true })
            }

            let text = "Same e\u{301} text"
            service.failure = nil
            service.response = text
            let processed = try await clarity.process(recognitionText: text, using: service)
            let output = try #require(processed)
            #expect(output.preparedText.utf16.elementsEqual(text.utf16))
            #expect(output.literalOutput.utf16.elementsEqual(text.utf16))
            #expect(output.enhancementResult?.modelName == "local-cli")
            #expect(output.enhancementResult?.requestSystemMessage != nil)
            #expect(output.enhancementResult?.requestUserMessage != nil)
            #expect(output.fallbackReason == nil)
            #expect(service.requests.count == 1)
        }

        @Test @MainActor func preparationAndProviderErrorsFallBackToUntouchedRecognition() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            fixture.context.insert(WordReplacement(originalText: "Roma", replacementText: "Prepared text"))
            try fixture.context.save()
            let service = try fixture.service()
            let raw = "\n Roma e\u{301}  \n"
            let missing = DictationPostprocessingPlan.captureClarity(snippets: [], style: .casual, using: fixture.context, enhancementService: nil)
            let processedMissing = try await missing.process(recognitionText: raw, using: service)
            let absent = try #require(processedMissing)
            #expect(service.requests.isEmpty)
            #expect(absent.literalOutput.utf16.elementsEqual(raw.utf16))
            #expect(absent.preparedText.utf16.elementsEqual(raw.utf16))
            #expect(absent.fallbackReason != nil)

            let plan = DictationPostprocessingPlan.captureClarity(snippets: [], style: .casual, using: fixture.context, enhancementService: service)
            for error in [DictationPlanFixtureFailure.request as Error, VoiceInkClarityError.emptyOutput] {
                service.failure = error
                let processed = try await plan.process(recognitionText: raw, using: service)
                let output = try #require(processed)
                #expect(output.literalOutput.utf8.elementsEqual(raw.utf8))
                #expect(output.literalOutput.utf16.elementsEqual(raw.utf16))
                #expect(output.preparedText.utf16.elementsEqual(raw.utf16))
                #expect(output.enhancementResult == nil)
                #expect(output.fallbackReason != nil)
            }
        }

        @Test @MainActor func libraryFailureDoesNotRunClarityAndDoesNotReturnPartialLightText() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let service = try fixture.service()
            let libraries = DictationPostprocessingPlan.Libraries(snippets: [], replacementRules: .failure(.replacementLibrary("fixture fetch failure")))
            let raw = "Um, Roma e\u{301}\n "
            let plans: [DictationPostprocessingPlan] = [
                .light(.init(libraries: libraries, storedLanguage: "en")),
                .clarity(.init(libraries: libraries, style: .natural, provider: .success(try service.providerSnapshot())))
            ]
            for plan in plans {
                let processed = try await plan.process(recognitionText: raw, using: service)
                let output = try #require(processed)
                #expect(output.literalOutput.utf16.elementsEqual(raw.utf16))
                #expect(output.fallbackReason?.contains("fixture fetch failure") == true)
            }
            #expect(service.requests.isEmpty)
        }

        @Test @MainActor func cancellationBeforeProcessingDoesNotExecuteTheProvider() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let service = try fixture.service()
            let plan = DictationPostprocessingPlan.captureClarity(snippets: [], style: .natural, using: fixture.context, enhancementService: service)
            let work = Task { try await plan.process(recognitionText: "Cancel this", using: service) }
            work.cancel()
            switch await work.result {
            case .failure(let error): #expect(error is CancellationError)
            case .success: Issue.record("Canceled processing returned an output or fallback.")
            }
            #expect(service.requests.isEmpty)
        }

        @Test @MainActor func cancellationAfterProviderAwaitRejectsLateSuccessAndWrappedFailure() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            for failAfterWait in [false, true] {
                let service = try fixture.service()
                let gate = DictationPlanGate()
                service.gate = gate
                service.response = "Late result"
                service.failure = failAfterWait ? DictationPlanFixtureFailure.request : nil
                let plan = DictationPostprocessingPlan.captureClarity(snippets: [], style: .natural, using: fixture.context, enhancementService: service)
                let work = Task { try await plan.process(recognitionText: "Keep original", using: service) }
                defer { work.cancel(); gate.release() }
                try await gate.waitUntilEntered(orCancel: work)
                work.cancel()
                gate.release()
                switch await work.result {
                case .failure(let error): #expect(error is CancellationError)
                case .success: Issue.record("A canceled late provider outcome became success or raw fallback.")
                }
                #expect(service.requests.count == 1)
            }
        }

        @Test @MainActor func providerCancellationAndOwnerCancellationNeverBecomeFallback() async throws {
            let fixture = try DictationPlanFixture()
            defer { fixture.restore() }
            let service = try fixture.service()
            let plan = DictationPostprocessingPlan.captureClarity(snippets: [], style: .natural, using: fixture.context, enhancementService: service)
            service.failure = CancellationError()
            await #expect(throws: CancellationError.self) {
                try await plan.process(recognitionText: "Keep original", using: service)
            }
            service.failure = nil
            let gate = DictationPlanGate()
            service.gate = gate
            let work = Task { try await plan.process(recognitionText: "Keep original", using: service, shouldCancel: { fixture.canceled }) }
            defer { work.cancel(); gate.release() }
            try await gate.waitUntilEntered(orCancel: work)
            fixture.canceled = true
            gate.release()
            switch await work.result {
            case .failure(let error): #expect(error is CancellationError)
            case .success: Issue.record("Operation-owner cancellation became a completed output.")
            }
        }
    }
}

private enum DictationPlanFixtureFailure: Error { case request, gateTimeout }

@MainActor
private final class DictationPlanFixture {
    let defaults = UserDefaults.standard
    let container: ModelContainer
    let context: ModelContext
    var canceled = false
    private let saved: [String: Any]
    private static let keys = [
        VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout,
        VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey
    ]

    init() throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(
            "RJT-Dictation-Plan-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        context = ModelContext(container)
        DictionaryService.invalidateWordReplacementCache()
    }

    func service() throws -> DictationPlanEnhancementSpy {
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set("/bin/cat", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(5, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        let aiService = AIService()
        try #require(aiService.selectedProvider == .localCLI)
        try #require(aiService.isAPIKeyValid)
        return DictationPlanEnhancementSpy(aiService: aiService, modelContext: context)
    }

    func restore() {
        for key in Self.keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        DictionaryService.invalidateWordReplacementCache()
    }
}

@MainActor
private final class DictationPlanEnhancementSpy: AIEnhancementService {
    var response = "Prepared output"
    var failure: Error?
    var gate: DictationPlanGate?
    var requests: [VoiceInkClarityRequest] = []
    var snapshots: [AIEnhancementProviderSnapshot] = []

    override func performClarity(request: VoiceInkClarityRequest, using snapshot: AIEnhancementProviderSnapshot) async throws -> VoiceInkAIEnhancementResult {
        requests.append(request)
        snapshots.append(snapshot)
        await gate?.enter()
        if let failure { throw failure }
        return VoiceInkAIEnhancementResult(
            text: response, duration: 0.125, modelName: snapshot.modelName, promptName: nil,
            requestSystemMessage: request.systemMessage, requestUserMessage: request.userMessage
        )
    }
}

@MainActor
private final class DictationPlanGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false

    func enter() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered(orCancel work: Task<DictationPostprocessingPlan.Output?, Error>) async throws {
        do {
            for _ in 0..<200 {
                if entered { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw DictationPlanFixtureFailure.gateTimeout
        } catch {
            work.cancel()
            release()
            _ = await work.result
            throw error
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
