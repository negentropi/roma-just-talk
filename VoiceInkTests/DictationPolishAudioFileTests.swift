import AVFoundation
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictationPolishAudioFileTests {
        @Test @MainActor func retranscriptionLightCapturesLanguageRulesAndSnippetsBeforeRecognition() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.light)
                let rule = try fixture.replace("Roma", with: "RJT")
                try fixture.snippet("my signature", content: "Original\r\n e\u{301} 🧪 ")
                let gate = fixture.gate()
                let registry = fixture.registry([.init("Um, Roma", gate: gate)])
                let service = fixture.service(registry: registry)
                let work = fixture.retranscribe(service)
                try await gate.waitUntilEntered()
                fixture.profile(.none)
                fixture.defaults.set("pt", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
                rule.replacementText = "Later"
                try fixture.context.save()
                DictionaryService.invalidateWordReplacementCache()
                let laterSnippet = "Later\r\n<tag>e\u{301}</tag> 🧪 "
                try fixture.snippet("my signature", content: laterSnippet)
                gate.release()
                let first = try await work.value
                #expect(first.text == "RJT")
                #expect(first.recognitionText == "Um, Roma")
                #expect(first.dictationProfile == .light)
                #expect(first.clarityStyle == nil)
                #expect(first.enhancedText == nil)

                fixture.profile(.light)
                registry.steps = [.init("Um, Roma")]
                let second = try await fixture.retranscribe(service).value
                #expect(second.text == "Um, Later")
                let snippetGate = fixture.gate()
                registry.steps = [.init("my signature", gate: snippetGate)]
                let heldSnippet = fixture.retranscribe(service)
                try await snippetGate.waitUntilEntered()
                let newestSnippet = "Newest\r\n<tag>e\u{301}</tag> 🧪 "
                try fixture.snippet("my signature", content: newestSnippet)
                snippetGate.release()
                let third = try await heldSnippet.value
                #expect(third.text.utf8.elementsEqual(laterSnippet.utf8))
                #expect(third.text.utf16.elementsEqual(laterSnippet.utf16))
                #expect(third.recognitionText == "my signature")
                #expect(third.enhancedText == nil)
                registry.steps = [.init("my signature")]
                let fourth = try await fixture.retranscribe(service).value
                #expect(fourth.text.utf8.elementsEqual(newestSnippet.utf8))
                #expect(fourth.text.utf16.elementsEqual(newestSnippet.utf16))
                #expect(fixture.enhancement.requests.isEmpty)
                let saved = try fixture.saved(first.id)
                #expect(saved.text == "RJT")
                #expect(saved.recognitionText == "Um, Roma")
                #expect(saved.dictationProfile == .light)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func retranscriptionClarityKeepsCapturedStyleTimeoutAndSameOutputMetadata() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.clarity)
                VoiceInkClarityStyle.formal.save()
                try fixture.replace("Roma", with: "RJT-482")
                fixture.enhancement.response = "RJT-482"
                let gate = fixture.gate()
                let registry = fixture.registry([.init("Roma", gate: gate)])
                let work = fixture.retranscribe(fixture.service(registry: registry))
                try await gate.waitUntilEntered()
                fixture.profile(.none)
                VoiceInkClarityStyle.casual.save()
                fixture.defaults.set(45, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
                fixture.defaults.set("/bin/false", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
                gate.release()
                let record = try await work.value
                #expect(record.text == "RJT-482")
                #expect(record.enhancedText == "RJT-482")
                #expect(record.recognitionText == "Roma")
                #expect(record.dictationProfile == .clarity)
                #expect(record.clarityStyle == .formal)
                #expect(record.processingFailureReason == nil)
                #expect(record.aiEnhancementModelName == "local-cli")
                #expect(record.aiRequestSystemMessage != nil)
                #expect(record.aiRequestUserMessage != nil)
                #expect(fixture.enhancement.requests.map(\.style) == [.formal])
                #expect(fixture.enhancement.requests.map(\.transcript) == ["RJT-482"])
                #expect(fixture.enhancement.snapshots.map(\.timeoutSeconds) == [10])
                #expect(fixture.enhancement.legacyCalls == 0)
                let saved = try fixture.saved(record.id)
                #expect(saved.enhancedText == "RJT-482")
                #expect(saved.clarityStyle == .formal)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func retranscriptionClaritySnippetWinsBeforeMissingProvider() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.clarity)
                let content = " \r\n<think>e\u{301}</think> {\"text\":\"literal\"} 🧪 "
                try fixture.snippet("my signature", content: content)
                let registry = fixture.registry([.init("my signature")])
                let service = fixture.service(registry: registry, withEnhancement: false)
                let record = try await fixture.retranscribe(service).value
                #expect(record.text.utf8.elementsEqual(content.utf8))
                #expect(record.text.utf16.elementsEqual(content.utf16))
                #expect(record.recognitionText == "my signature")
                #expect(record.enhancedText == nil)
                #expect(record.processingFailureReason == nil)
                #expect(record.aiRequestSystemMessage == nil)
                #expect(record.dictationProfile == .clarity)
                #expect(fixture.enhancement.requests.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func retranscriptionProviderFailureRetainsUntouchedRecognitionAndOneFailureField() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.clarity)
                try fixture.replace("Roma", with: "Prepared replacement")
                let raw = " Um, Roma <tag>e\u{301}</tag> [keep] 🧪\r\n "
                fixture.enhancement.failure = PolishAudioFailure.provider
                let registry = fixture.registry([.init(raw)])
                let record = try await fixture.retranscribe(fixture.service(registry: registry)).value
                #expect(record.text.utf8.elementsEqual(raw.utf8))
                #expect(record.text.utf16.elementsEqual(raw.utf16))
                #expect(record.recognitionText?.utf16.elementsEqual(raw.utf16) == true)
                #expect(record.enhancedText == nil)
                #expect(record.processingFailureReason?.isEmpty == false)
                #expect(record.aiEnhancementModelName == nil)
                #expect(record.aiRequestSystemMessage == nil)
                #expect(record.transcriptionState == .completed)
                #expect(fixture.enhancement.requests.count == 1)
                #expect(fixture.enhancement.requests.first?.transcript.contains("Prepared replacement") == true)
                let saved = try fixture.saved(record.id)
                #expect(saved.text.utf8.elementsEqual(raw.utf8))
                #expect(saved.processingFailureReason == record.processingFailureReason)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func retranscriptionLateProviderCancellationDoesNotSaveOrKeepOwnedCopy() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.clarity)
                let gate = fixture.gate()
                fixture.enhancement.gate = gate
                fixture.enhancement.response = "Late output"
                let registry = fixture.registry([.init("Keep original")])
                let before = try fixture.recordingFiles()
                let work = fixture.retranscribe(fixture.service(registry: registry))
                try await gate.waitUntilEntered()
                let created = try fixture.recordingFiles().subtracting(before)
                let copy = try #require(created.count == 1 ? created.first : nil)
                fixture.ownedCopies.insert(copy)
                let copiedAudio = try Data(contentsOf: copy)
                let originalAudio = try Data(contentsOf: fixture.audio)
                #expect(copiedAudio == originalAudio)
                work.cancel()
                gate.release()
                switch await work.result {
                case .failure(let error): #expect(error is CancellationError)
                case .success: Issue.record("Canceled file processing saved a completed fallback.")
                }
                #expect(try fixture.records().isEmpty)
                #expect(!FileManager.default.fileExists(atPath: copy.path))
                #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func retranscriptionReadOnlyStoreSaveFailureThrowsAndRemovesItsCopy() async throws {
            let fixture = try PolishAudioFixture(readOnlyStore: true)
            do {
                fixture.profile(.clarity)
                fixture.enhancement.response = "Read-only processed result"
                let registry = fixture.registry([.init("Read-only original e\u{301} 🧪")])
                let before = try fixture.recordingFiles()
                var failed = false
                do {
                    _ = try await fixture.retranscribe(fixture.service(registry: registry)).value
                    Issue.record("An actual read-only store accepted a completed transcription.")
                } catch {
                    failed = true
                    #expect(!(error is CancellationError))
                }
                #expect(failed)
                // The provider runs after the actual duration load and permanent copy.
                #expect(fixture.enhancement.requests.count == 1)
                #expect(fixture.enhancement.requests.first?.transcript == "Read-only original e\u{301} 🧪")
                #expect(fixture.enhancement.snapshots.first?.modelName == "local-cli")
                #expect(try fixture.records().isEmpty)
                #expect(try fixture.recordingFiles() == before)
                #expect(try fixture.context.fetchCount(FetchDescriptor<VocabularyWord>()) == 1)
                #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func importCapturesEachItemWhenItStartsAndPreservesItsRawMetadata() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.light)
                try fixture.replace("Roma", with: "RJT")
                let firstGate = fixture.gate(), secondGate = fixture.gate()
                let secondRaw = " \r\nRoma [keep] <tag>e\u{301}</tag> 🧪 "
                let registry = fixture.registry([.init("Um, Roma", gate: firstGate), .init(secondRaw, gate: secondGate)])
                let manager = fixture.manager([registry, registry])
                let secondAudio = try fixture.makeAudio()
                manager.addToQueue(urls: [fixture.audio, secondAudio])
                #expect(manager.queue.count == 2)
                let firstItem = try #require(manager.queue.first)
                let secondItem = try #require(manager.queue.last)
                let engine = fixture.engine()
                manager.startProcessing(modelContext: fixture.context, engine: engine)
                try await firstGate.waitUntilEntered()
                fixture.profile(.none)
                firstGate.release()
                try await secondGate.waitUntilEntered()
                fixture.profile(.clarity)
                secondGate.release()
                try await fixture.waitUntil { !manager.isProcessingQueue && registry.cleanupCalls == 2 }
                let first = try #require(firstItem.transcription)
                let second = try #require(secondItem.transcription)
                #expect(firstItem.status == .completed)
                #expect(secondItem.status == .completed)
                #expect(first.text == "RJT")
                #expect(first.recognitionText == "Um, Roma")
                #expect(first.dictationProfile == .light)
                #expect(second.text.utf8.elementsEqual(secondRaw.utf8))
                #expect(second.recognitionText?.utf16.elementsEqual(secondRaw.utf16) == true)
                #expect(second.dictationProfile == VoiceInkDictationProfile.none)
                #expect(second.enhancedText == nil)
                #expect(manager.lastCompletedItemId == secondItem.id)
                #expect(fixture.warnings.isEmpty)
                #expect(try fixture.records().count == 2)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func canceledImportCannotResetItsRestartedItemsNewerState() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.none)
                let oldGate = fixture.gate(), newGate = fixture.gate()
                let oldRegistry = fixture.registry([.init("Old result", gate: oldGate)])
                let newRegistry = fixture.registry([.init("New result", gate: newGate)])
                let manager = fixture.manager([oldRegistry, newRegistry])
                manager.addToQueue(urls: [fixture.audio])
                let item = try #require(manager.queue.first)
                let engine = fixture.engine()
                manager.startProcessing(modelContext: fixture.context, engine: engine)
                try await oldGate.waitUntilEntered()
                let oldCopy = try #require(oldRegistry.inputs.first)
                manager.cancelProcessing()
                manager.startProcessing(modelContext: fixture.context, engine: engine)
                try await newGate.waitUntilEntered()
                let newCopy = try #require(newRegistry.inputs.first)
                #expect(oldCopy != newCopy)
                oldGate.release()
                try await fixture.waitUntil {
                    oldRegistry.cleanupCalls == 1 && !FileManager.default.fileExists(atPath: oldCopy.path)
                }
                #expect(manager.isProcessingQueue)
                #expect(item.status == .processing(phase: .transcribing))
                #expect(item.transcription == nil)
                #expect(try fixture.records().isEmpty)
                #expect(!FileManager.default.fileExists(atPath: oldCopy.path))
                #expect(FileManager.default.fileExists(atPath: newCopy.path))
                newGate.release()
                try await fixture.waitUntil { !manager.isProcessingQueue && newRegistry.cleanupCalls == 1 }
                #expect(item.status == .completed)
                #expect(item.transcription?.text == "New result")
                #expect(try fixture.records().count == 1)
                #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
                #expect(fixture.warnings.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func importMissingClarityProviderRetainsOriginalAndWarnsExactlyOnce() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.clarity)
                try fixture.replace("Roma", with: "Prepared replacement")
                let raw = " Roma <tag>e\u{301}</tag> 🧪\r\n "
                let registry = fixture.registry([.init(raw)])
                let manager = fixture.manager([registry])
                manager.addToQueue(urls: [fixture.audio])
                let item = try #require(manager.queue.first)
                let engine = fixture.engine()
                manager.startProcessing(modelContext: fixture.context, engine: engine)
                try await fixture.waitUntil { !manager.isProcessingQueue && registry.cleanupCalls == 1 }
                let record = try #require(item.transcription)
                #expect(item.status == .completed)
                #expect(record.text.utf8.elementsEqual(raw.utf8))
                #expect(record.recognitionText?.utf16.elementsEqual(raw.utf16) == true)
                #expect(record.enhancedText == nil)
                #expect(record.aiRequestSystemMessage == nil)
                #expect(record.processingFailureReason?.isEmpty == false)
                #expect(fixture.warnings == [record.processingFailureReason ?? "missing reason"])
                let saved = try fixture.saved(record.id)
                #expect(saved.text.utf16.elementsEqual(raw.utf16))
                #expect(saved.processingFailureReason == record.processingFailureReason)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func clearingCanceledImportLeavesNoCompletedRecordOrOwnedAudio() async throws {
            let fixture = try PolishAudioFixture()
            do {
                fixture.profile(.none)
                let gate = fixture.gate()
                let registry = fixture.registry([.init("Late result", gate: gate)])
                let manager = fixture.manager([registry])
                manager.addToQueue(urls: [fixture.audio])
                let engine = fixture.engine()
                manager.startProcessing(modelContext: fixture.context, engine: engine)
                try await gate.waitUntilEntered()
                let copy = try #require(registry.inputs.first)
                manager.clearAll()
                gate.release()
                try await fixture.waitUntil {
                    registry.cleanupCalls == 1 && !FileManager.default.fileExists(atPath: copy.path)
                }
                #expect(!manager.isProcessingQueue)
                #expect(manager.queue.isEmpty)
                #expect(manager.lastCompletedItemId == nil)
                #expect(try fixture.records().isEmpty)
                #expect(!FileManager.default.fileExists(atPath: copy.path))
                #expect(FileManager.default.fileExists(atPath: fixture.audio.path))
                #expect(fixture.warnings.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }
    }
}

private enum PolishAudioFailure: Error { case provider, missingRecognition, timeout }

@MainActor
private final class PolishAudioFixture {
    let defaults = UserDefaults.standard
    let directory: URL
    let audio: URL
    let container: ModelContainer
    let context: ModelContext
    let enhancement: PolishAudioEnhancementSpy
    var ownedCopies = Set<URL>()
    var warnings: [String] = []
    private let provider = PolishAudioUnusedWhisperProvider()
    private let savedDefaults: [String: Any]
    private let savedPowerMode: PowerModeConfig?
    private var gates: [PolishAudioGate] = []
    private var tasks: [Task<Transcription, Error>] = []
    private var managers: [AudioTranscriptionManager] = []
    private var registries: [PolishAudioRegistry] = []
    private var engines: [VoiceInkEngine] = []
    private var freshContexts: [ModelContext] = []
    private static let keys = [
        VoiceInkDictationProfile.storageKey, VoiceInkClarityStyle.storageKey, VoiceInkSpokenSnippets.userDefaultsKey,
        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled, VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId, VoiceInkUserDefaultsKey.useClipboardContext,
        VoiceInkUserDefaultsKey.useScreenCaptureContext, VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey, VoiceInkLocalCLIPreference.selectedTemplateKey,
        VoiceInkUserDefaultsKey.isTextFormattingEnabled, VoiceInkUserDefaultsKey.lowercaseTranscription,
        VoiceInkUserDefaultsKey.removeFillerWords, VoiceInkUserDefaultsKey.fillerWords,
        VoiceInkUserDefaultsKey.appendTrailingSpace, VoiceInkUserDefaultsKey.skipShortEnhancement,
        VoiceInkUserDefaultsKey.prewarmModelOnWake, VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled,
        VoiceInkUserDefaultsKey.isAudioCleanupEnabled, PunctuationCleanupMode.userDefaultsKey,
        PunctuationCleanupMode.legacyRemovePunctuationKey,
        VoiceInkUserDefaultsKey.activePowerModeConfigurationId, VoiceInkUserDefaultsKey.powerModePersistConfig
    ]

    init(readOnlyStore: Bool = false) throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Polish-Audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        audio = try Self.writeAudio(in: directory)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        if readOnlyStore {
            let url = directory.appendingPathComponent("read-only.store")
            try Self.seedStore(schema: schema, url: url)
            let configuration = ModelConfiguration("PolishAudioReadOnly", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
            try #require(!configuration.allowsSave && !configuration.isStoredInMemoryOnly)
            try #require(configuration.groupAppContainerIdentifier == nil && configuration.cloudKitContainerIdentifier == nil)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } else {
            let configuration = ModelConfiguration("PolishAudio-\(UUID().uuidString)", schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [configuration])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(Data("[]".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set("/bin/cat", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(5, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.prewarmModelOnWake)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkSpokenSnippets.userDefaultsKey)
        PowerModeManager.shared.activeConfiguration = nil
        DictionaryService.invalidateWordReplacementCache()
        let ai = AIService()
        try #require(ai.selectedProvider == .localCLI && ai.isAPIKeyValid && ai.apiKey.isEmpty)
        enhancement = PolishAudioEnhancementSpy(aiService: ai, modelContext: context)
    }

    private static func seedStore(schema: Schema, url: URL) throws {
        let configuration = ModelConfiguration("PolishAudioReadOnly", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(VocabularyWord(word: "Read-only seed"))
        try context.save()
    }

    private static func writeAudio(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("input-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        let channels = try #require(buffer.floatChannelData)
        channels[0].initialize(repeating: 0, count: 1_600)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func makeAudio() throws -> URL { try Self.writeAudio(in: directory) }
    func profile(_ profile: VoiceInkDictationProfile) { profile.save() }

    @discardableResult func replace(_ source: String, with replacement: String) throws -> WordReplacement {
        let rule = WordReplacement(originalText: source, replacementText: replacement)
        context.insert(rule)
        try context.save()
        DictionaryService.invalidateWordReplacementCache()
        return rule
    }

    func snippet(_ trigger: String, content: String) throws {
        try VoiceInkSpokenSnippets.save([.init(trigger: trigger, content: content)])
    }

    func gate() -> PolishAudioGate {
        let value = PolishAudioGate()
        gates.append(value)
        return value
    }

    func registry(_ steps: [PolishAudioRegistry.Step]) -> PolishAudioRegistry {
        let value = PolishAudioRegistry(modelProvider: provider, modelsDirectory: directory, modelContext: context,
            qwenRuntimeResult: .failure(PolishAudioFailure.missingRecognition))
        value.steps = steps
        registries.append(value)
        return value
    }

    func service(registry: PolishAudioRegistry, withEnhancement: Bool = true) -> AudioTranscriptionService {
        AudioTranscriptionService(modelContext: context, serviceRegistry: registry,
            enhancementService: withEnhancement ? enhancement : nil)
    }

    func retranscribe(_ service: AudioTranscriptionService) -> Task<Transcription, Error> {
        let input = audio
        let work = Task { try await service.retranscribeAudio(from: input, using: TranscriptionModelRegistry.defaultMacOSFluidAudioModel) }
        tasks.append(work)
        return work
    }

    func manager(_ values: [PolishAudioRegistry]) -> AudioTranscriptionManager {
        var index = 0
        let manager = AudioTranscriptionManager(serviceRegistryFactory: { _, _ in
            guard index < values.count else {
                Issue.record("The queue requested an unexpected extra registry.")
                return values[values.count - 1]
            }
            let result = values[index]
            index += 1
            result.expectedCleanupCalls += 1
            return result
        }, processingWarning: { [weak self] reason in self?.warnings.append(reason) })
        managers.append(manager)
        return manager
    }

    func engine() -> VoiceInkEngine {
        let whisper = WhisperModelManager(modelsDirectory: directory)
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        let engine = VoiceInkEngine(modelContext: context, whisperModelManager: whisper,
            transcriptionModelManager: models, qwenRuntimeResult: .failure(PolishAudioFailure.missingRecognition))
        engines.append(engine)
        return engine
    }

    func records() throws -> [Transcription] { try context.fetch(FetchDescriptor<Transcription>()) }

    func saved(_ id: UUID) throws -> Transcription {
        let fresh = ModelContext(container)
        freshContexts.append(fresh)
        let rows = try fresh.fetch(FetchDescriptor<Transcription>())
        return try #require(rows.first { $0.id == id })
    }

    func recordingFiles() throws -> Set<URL> {
        let directory = VoiceInkMacOSStorageDirectories.recordingsDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("retranscribed_") && $0.pathExtension == "wav" })
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw PolishAudioFailure.timeout
    }

    func close() async {
        for manager in managers { manager.cancelProcessing() }
        for task in tasks { task.cancel() }
        for gate in gates { gate.release() }
        for task in tasks {
            if case .success(let record) = await task.result,
               let value = record.audioFileURL, let url = URL(string: value) { ownedCopies.insert(url) }
        }
        for _ in 0..<400 {
            if ownedWorkFinished() { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if !ownedWorkFinished() {
            Issue.record("An owned file task did not finish cleanup before restoring its fixture.")
        }
        for manager in managers {
            for item in manager.queue {
                if let value = item.transcription?.audioFileURL, let url = URL(string: value) { ownedCopies.insert(url) }
            }
            manager.clearAll()
        }
        for registry in registries {
            for url in registry.inputs where url.deletingLastPathComponent() == VoiceInkMacOSStorageDirectories.recordingsDirectory {
                ownedCopies.insert(url)
            }
        }
        for url in ownedCopies where url.isFileURL && url.deletingLastPathComponent() == VoiceInkMacOSStorageDirectories.recordingsDirectory {
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { Issue.record("Could not remove owned processed audio: \(error)") }
            }
        }
        DictionaryService.invalidateWordReplacementCache()
        PowerModeManager.shared.activeConfiguration = savedPowerMode
        for key in Self.keys {
            if let value = savedDefaults[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove owned audio fixture: \(error)") }
    }

    private func ownedWorkFinished() -> Bool {
        guard registries.allSatisfy({ $0.activeCalls == 0 && $0.cleanupCalls >= $0.expectedCleanupCalls }),
              let records = try? records() else { return false }
        let committed = Set(records.compactMap { $0.audioFileURL.flatMap(URL.init(string:)) })
        return registries.flatMap(\.inputs).allSatisfy { url in
            url.deletingLastPathComponent() != VoiceInkMacOSStorageDirectories.recordingsDirectory
                || committed.contains(url) || !FileManager.default.fileExists(atPath: url.path)
        }
    }
}

@MainActor
private final class PolishAudioRegistry: TranscriptionServiceRegistry {
    struct Step {
        let text: String
        let gate: PolishAudioGate?
        init(_ text: String, gate: PolishAudioGate? = nil) { self.text = text; self.gate = gate }
    }
    var steps: [Step] = []
    var inputs: [URL] = []
    var activeCalls = 0
    var cleanupCalls = 0
    var expectedCleanupCalls = 0

    override func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard !steps.isEmpty else { throw PolishAudioFailure.missingRecognition }
        let step = steps.removeFirst()
        inputs.append(audioURL)
        activeCalls += 1
        defer { activeCalls -= 1 }
        await step.gate?.enter()
        return step.text
    }

    override func cleanup() async { cleanupCalls += 1 }
}

@MainActor
private final class PolishAudioEnhancementSpy: AIEnhancementService {
    var response = "Polished output"
    var failure: Error?
    var gate: PolishAudioGate?
    var requests: [VoiceInkClarityRequest] = []
    var snapshots: [AIEnhancementProviderSnapshot] = []
    var legacyCalls = 0

    override func performClarity(request: VoiceInkClarityRequest, using snapshot: AIEnhancementProviderSnapshot) async throws -> VoiceInkAIEnhancementResult {
        requests.append(request)
        snapshots.append(snapshot)
        await gate?.enter()
        if let failure { throw failure }
        return VoiceInkAIEnhancementResult(text: response, duration: 0.125, modelName: snapshot.modelName,
            promptName: nil, requestSystemMessage: request.systemMessage, requestUserMessage: request.userMessage)
    }

    override func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        legacyCalls += 1
        throw PolishAudioFailure.provider
    }
}

@MainActor
private final class PolishAudioUnusedWhisperProvider: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class PolishAudioGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false

    func enter() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async throws {
        for _ in 0..<400 {
            if entered { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw PolishAudioFailure.timeout
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
