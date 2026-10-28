import CryptoKit
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test(.enabled(if: NoneProfileImportInputs.isEnabled), .timeLimit(.minutes(10)))
    @MainActor func liveNoneProfileImportQueueUsesRealWhisperRecognition() async throws {
        let evidence = URL(fileURLWithPath: try #require(NoneProfileImportInputs.value("RJT_NONE_IMPORT_EVIDENCE")), isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        var receipt = NoneProfileImportInputs.hostReceipt
        try NoneProfileImportInputs.write(receipt, to: evidence)
        do {
            let inputs = try NoneProfileImportInputs(evidence: evidence)
            receipt.merge(inputs.receipt) { _, new in new }
            try NoneProfileImportInputs.write(receipt, to: evidence)
            let fixture = try NoneProfileImportFixture(inputs: inputs)
            do {
                try await fixture.run(receipt: &receipt)
            } catch {
                receipt["ownedCleanupCompleted"] = await fixture.restore()
                throw error
            }
            let cleaned = await fixture.restore()
            receipt["ownedCleanupCompleted"] = cleaned
            try #require(cleaned, "Successful proof requires complete cleanup of its owned queue item and files.")
            receipt["classification"] = "passed"
            try NoneProfileImportInputs.write(receipt, to: evidence)
        } catch {
            receipt["classification"] = "failed"
            receipt["failure"] = String(describing: error)
            try NoneProfileImportInputs.write(receipt, to: evidence)
            throw error
        }
    }
}

private struct NoneProfileImportInputs {
    static let testName = "liveNoneProfileImportQueueUsesRealWhisperRecognition"
    static let expectedModelSHA256 = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
    static var isEnabled: Bool {
        value("RJT_NONE_IMPORT_LIVE_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }

    let model: URL
    let audio: URL
    let evidence: URL
    let receipt: [String: Any]

    static var hostReceipt: [String: Any] {
        [
            "version": 1, "testName": testName, "classification": "started",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "executablePath": Bundle.main.executableURL?.path ?? "",
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "sourcePath": #filePath
        ]
    }

    init(evidence: URL) throws {
        model = URL(fileURLWithPath: try #require(Self.value("RJT_NONE_IMPORT_MODEL")))
        audio = URL(fileURLWithPath: try #require(Self.value("RJT_NONE_IMPORT_AUDIO")))
        self.evidence = evidence
        let modelHash = try Self.sha256(model)
        try #require(modelHash == Self.expectedModelSHA256, "The remote fixture must use the pinned Whisper base model.")
        receipt = [
            "modelSHA256": modelHash, "audioSHA256": try Self.sha256(audio),
            "scope": "One real public file-import queue inference using AudioProcessor and WhisperTranscriptionService; synthetic Samantha speech.",
            "recognitionOracle": "The same preloaded WhisperContext.getTranscription result after that inference; no second recognition.",
            "limitations": "No microphone, human speech, AI semantics, insertion, crash durability, or relaunch proof. Fresh ModelContext reads the retained in-memory store.",
            "failureCleanupLimit": "The import API exposes its allocated WAV only after persistence. Failed or canceled allocation may leave a WAV on this disposable runner; failure never claims complete cleanup."
        ]
    }

    static func value(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_" + key]
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func write(_ receipt: [String: Any], to evidence: URL) throws {
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("import-observation.json"), options: .atomic)
    }
}

@MainActor
private final class NoneProfileImportFixture {
    private static let preferenceKeys = [
        VoiceInkDictationProfile.storageKey,
        VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.prewarmModelOnWake,
        VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled,
        VoiceInkUserDefaultsKey.isAudioCleanupEnabled,
        VoiceInkUserDefaultsKey.isTextFormattingEnabled,
        VoiceInkUserDefaultsKey.lowercaseTranscription,
        VoiceInkUserDefaultsKey.removeFillerWords,
        VoiceInkUserDefaultsKey.fillerWords,
        VoiceInkUserDefaultsKey.appendTrailingSpace,
        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage,
        VoiceInkUserDefaultsKey.transcriptionPrompt,
        VoiceInkUserDefaultsKey.isVADEnabled,
        VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey,
        PunctuationCleanupMode.userDefaultsKey,
        PunctuationCleanupMode.legacyRemovePunctuationKey,
        VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey,
        VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceIDKey,
        VoiceInkUserDefaultsKey.activePowerModeConfigurationId,
        VoiceInkUserDefaultsKey.powerModePersistConfig
    ]

    private let inputs: NoneProfileImportInputs
    private let directory: URL
    private let container: ModelContainer
    private let context: ModelContext
    private let whisper: WhisperModelManager
    private let engine: VoiceInkEngine
    private let savedDefaults: [String: Any]
    private let savedSoundEnabled: Bool
    private let savedPowerMode: PowerModeConfig?
    private let savedLastCompletedItemID: UUID?
    private let manager = AudioTranscriptionManager.shared
    private var ownedItem: AudioFileQueueItem?

    init(inputs: NoneProfileImportInputs) throws {
        self.inputs = inputs
        let queueManager = AudioTranscriptionManager.shared
        try #require(queueManager.queue.isEmpty && !queueManager.isProcessingQueue, "A disposable runner with an idle, empty import queue is required.")
        let defaults = UserDefaults.standard
        let domain = try #require(Bundle.main.bundleIdentifier)
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.preferenceKeys.compactMap { key in
            persisted[key].map { (key, $0) }
        })
        savedSoundEnabled = SoundManager.shared.isEnabled
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        savedLastCompletedItemID = queueManager.lastCompletedItemId
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-None-Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "NoneImport-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        context = container.mainContext
        context.autosaveEnabled = false
        context.insert(WordReplacement(originalText: "fox", replacementText: "REPLACEMENT MUST NOT APPEAR"))
        try context.save()
        VoiceInkAIEnhancementProviderPreference.saveSelectedProvider(.localCLI)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.prewarmModelOnWake)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(["quick"], forKey: VoiceInkUserDefaultsKey.fillerWords)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
        defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        defaults.set("", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isVADEnabled)
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts([:])
        PunctuationCleanupMode.setCurrent(.removeAll)
        VoiceInkDictationProfile.none.save()
        PowerModeManager.shared.activeConfiguration = nil
        SoundManager.shared.isEnabled = false
        whisper = WhisperModelManager(modelsDirectory: directory)
        whisper.availableModels = [.init(name: "base", url: inputs.model)]
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = ImportedWhisperModel(fileBaseName: "base")
        engine = VoiceInkEngine(
            modelContext: context, whisperModelManager: whisper, transcriptionModelManager: models,
            qwenRuntimeResult: .failure(NoneProfileImportFailure.unusedQwenRuntime)
        )
    }

    func run(receipt: inout [String: Any]) async throws {
        let modelFile = try #require(whisper.availableModels.first)
        try await whisper.loadModel(modelFile)
        let recognitionContext = try #require(whisper.whisperContext)
        let previousRecognition = await recognitionContext.getTranscription()
        try #require(previousRecognition == "", "The owned context must not contain a previous inference.")
        manager.addToQueue(urls: [inputs.audio])
        try #require(manager.queue.count == 1)
        let item = try #require(manager.queue.first)
        ownedItem = item
        receipt["queueItemID"] = item.id.uuidString
        try #require(item.status == .pending)
        manager.startProcessing(modelContext: context, engine: engine)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(180))
        while manager.isProcessingQueue && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(!manager.isProcessingQueue, "Real file import did not finish within 180 seconds.")
        try #require(item.status == .completed, "Real file import must complete, observed \(item.status).")
        try #require(manager.lastCompletedItemId == item.id)
        let record = try #require(item.transcription)
        let freshContext = ModelContext(container)
        let records = try freshContext.fetch(FetchDescriptor<Transcription>())
        try #require(records.count == 1)
        let saved = try #require(records.first)
        try #require(saved.id == record.id && saved.transcriptionState == .completed)
        let permanentURL = try #require(saved.audioFileURL.flatMap(URL.init(string:)))
        try #require(permanentURL.isFileURL && FileManager.default.fileExists(atPath: permanentURL.path))
        let raw = await recognitionContext.getTranscription()
        try #require(!raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && raw.utf8.count < 2_048)
        let words = Set(raw.lowercased().split { !$0.isLetter }.map(String.init))
        try #require(Set(["quick", "brown", "fox"]).isSubset(of: words), "The fixture must produce recognizable synthetic speech.")
        try #require(raw != raw.lowercased(), "The fixture must exercise the incompatible lowercase setting.")
        let utf8Equal = saved.text.utf8.elementsEqual(raw.utf8)
        let utf16Equal = saved.text.utf16.elementsEqual(raw.utf16)
        receipt["sameContextRecognition"] = raw
        receipt["storedText"] = saved.text
        receipt["utf8Equal"] = utf8Equal
        receipt["utf16Equal"] = utf16Equal
        receipt["enhancedText"] = saved.enhancedText as Any? ?? NSNull()
        receipt["recordID"] = saved.id.uuidString
        receipt["permanentAudioURL"] = permanentURL.absoluteString
        receipt["permanentAudioSHA256"] = try NoneProfileImportInputs.sha256(permanentURL)
        receipt["completed"] = true
        let processed = inputs.evidence.appendingPathComponent("processed-input.wav")
        try Data(contentsOf: permanentURL).write(to: processed, options: .atomic)
        try #require(utf8Equal && utf16Equal, "None must persist the exact same inference return string.")
        try #require(saved.enhancedText == nil)
        try #require(!saved.text.contains("REPLACEMENT MUST NOT APPEAR"))
        try #require(whisper.whisperContext === recognitionContext && whisper.loadedWhisperModel?.name == "base")
    }

    func restore() async -> Bool {
        var cleaned = true
        if let item = ownedItem {
            if manager.isProcessingQueue {
                cleaned = false
                if manager.queue.allSatisfy({ $0.id == item.id }) { manager.cancelProcessing() }
                else { Issue.record("Foreign queue work appeared; refusing to cancel it.") }
            }
            if let url = item.transcription?.audioFileURL.flatMap(URL.init(string:)), url.isFileURL {
                do { try FileManager.default.removeItem(at: url) }
                catch {
                    cleaned = false
                    Issue.record("Could not remove owned imported WAV: \(error)")
                }
            } else {
                cleaned = false
            }
            manager.queue.removeAll { $0.id == item.id }
            if manager.lastCompletedItemId == item.id { manager.lastCompletedItemId = savedLastCompletedItemID }
        }
        await engine.cleanupResources()
        PowerModeManager.shared.activeConfiguration = savedPowerMode
        SoundManager.shared.isEnabled = savedSoundEnabled
        for key in Self.preferenceKeys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch {
            cleaned = false
            Issue.record("Could not remove owned model metadata directory: \(error)")
        }
        return cleaned
    }
}

private enum NoneProfileImportFailure: Error {
    case unusedQwenRuntime
}

extension VoiceInkTests {
    @Test(.enabled(if: DictationPolishLiveInputs.isEnabled), .timeLimit(.minutes(10)))
    @MainActor func liveLightImportQueueUsesRealWhisperRecognition() async throws {
        try await runPolishWhisperCase(.light, retranscribing: false, name: #function)
    }

    @Test(.enabled(if: DictationPolishLiveInputs.isEnabled), .timeLimit(.minutes(10)))
    @MainActor func liveClarityImportQueueUsesRealWhisperRecognition() async throws {
        try await runPolishWhisperCase(.clarity, retranscribing: false, name: #function)
    }

    @Test(.enabled(if: DictationPolishLiveInputs.isEnabled), .timeLimit(.minutes(10)))
    @MainActor func liveLightRetranscriptionUsesRealWhisperRecognition() async throws {
        try await runPolishWhisperCase(.light, retranscribing: true, name: #function)
    }

    @Test(.enabled(if: DictationPolishLiveInputs.isEnabled), .timeLimit(.minutes(10)))
    @MainActor func liveClarityRetranscriptionUsesRealWhisperRecognition() async throws {
        try await runPolishWhisperCase(.clarity, retranscribing: true, name: #function)
    }

    @MainActor private func runPolishWhisperCase(
        _ profile: VoiceInkDictationProfile, retranscribing: Bool, name: String
    ) async throws {
        let testName = String(name.prefix { $0 != "(" })
        let environment = try DictationPolishLiveEnvironment(testName: testName)
        var receipt = environment.hostReceipt
        do {
            let fixture = try DictationPolishWhisperFixture(environment: environment)
            do {
                receipt.merge(try await fixture.run(profile: profile, retranscribing: retranscribing)) { _, new in new }
                try await fixture.close()
            } catch {
                try? await fixture.close()
                throw error
            }
            try environment.close()
            receipt["ownedCleanupCompleted"] = true
            receipt["classification"] = "passed"
            try environment.write(receipt)
        } catch {
            receipt["classification"] = "failed"
            receipt["failure"] = String(describing: error)
            try? environment.close()
            try? environment.write(receipt)
            throw error
        }
    }
}

enum DictationPolishLiveInputs {
    static let modelSHA256 = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
    static let audioSHA256 = "a9f5d6fad663dccaaf1a3a72487ae8653cac36b88c8d81e470a0702dc30ad805"
    static var isEnabled: Bool {
        value("RJT_DICTATION_POLISH_LIVE_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }
    static func value(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_" + key]
    }
    static func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
    }
    static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8) && lhs.utf16.elementsEqual(rhs.utf16)
    }
}

/// Disposable native-host configuration shared by the file and actual-editor observations.
@MainActor
final class DictationPolishLiveEnvironment {
    static let replacement = "RJT-482 $5 \\path e\u{301} 🧪"
    static let enhanced = "\n  <think>Literal e\u{301} 🧪</think> $5 \\path\r\n  "
    let testName: String
    let directory: URL
    let evidence: URL
    let container: ModelContainer
    let context: ModelContext
    let ai: AIService
    let enhancement: AIEnhancementService
    private let savedDefaults: [String: Any]
    private let savedSound: Bool
    private let savedPowerMode: PowerModeConfig?
    private var closed = false
    private static let keys = [
        VoiceInkDictationProfile.storageKey, VoiceInkClarityStyle.storageKey,
        VoiceInkUserDefaultsKey.selectedAIProvider, VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.useClipboardContext, VoiceInkUserDefaultsKey.useScreenCaptureContext,
        VoiceInkUserDefaultsKey.customPrompts, VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkLocalCLIPreference.commandTemplateKey, VoiceInkLocalCLIPreference.timeoutSecondsKey,
        VoiceInkUserDefaultsKey.prewarmModelOnWake, VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled,
        VoiceInkUserDefaultsKey.isAudioCleanupEnabled, VoiceInkUserDefaultsKey.isTextFormattingEnabled,
        VoiceInkUserDefaultsKey.lowercaseTranscription, VoiceInkUserDefaultsKey.removeFillerWords,
        VoiceInkUserDefaultsKey.fillerWords, VoiceInkUserDefaultsKey.appendTrailingSpace,
        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, VoiceInkUserDefaultsKey.transcriptionPrompt,
        VoiceInkUserDefaultsKey.isVADEnabled, VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey,
        PunctuationCleanupMode.userDefaultsKey, PunctuationCleanupMode.legacyRemovePunctuationKey,
        VoiceInkSpokenSnippets.userDefaultsKey, VoiceInkUserDefaultsKey.activePowerModeConfigurationId,
        VoiceInkUserDefaultsKey.powerModePersistConfig, VoiceInkPasteMethod.userDefaultsKey,
        VoiceInkPastePreference.restoreClipboardAfterPasteKey
    ]

    init(testName: String) throws {
        try #require(DictationPolishLiveInputs.isEnabled)
        try #require(DictationPolishLiveInputs.value("RUNNER_ENVIRONMENT") == "github-hosted")
        #if !LOCAL_BUILD
        throw NoneProfileImportFailure.unusedQwenRuntime
        #endif
        self.testName = testName
        evidence = URL(fileURLWithPath: try #require(DictationPolishLiveInputs.value("RJT_DICTATION_POLISH_EVIDENCE")), isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Polish-Native-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let defaults = UserDefaults.standard
        let domain = try #require(Bundle.main.bundleIdentifier)
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in persisted[key].map { (key, $0) } })
        savedSound = SoundManager.shared.isEnabled
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let configuration = ModelConfiguration("PolishNative-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        // Select Local CLI before either AIService initialization; no saved credential is needed.
        VoiceInkAIEnhancementProviderPreference.saveSelectedProvider(.localCLI)
        VoiceInkLocalCLIPreference.saveCommandTemplate("/usr/bin/true")
        VoiceInkLocalCLIPreference.saveTimeoutSeconds(5)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
        defaults.set(Data("[]".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.prewarmModelOnWake)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(["quick", "send"], forKey: VoiceInkUserDefaultsKey.fillerWords)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
        defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        defaults.set("", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isVADEnabled)
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts([:])
        defaults.removeObject(forKey: VoiceInkSpokenSnippets.userDefaultsKey)
        PunctuationCleanupMode.setCurrent(.removeAll)
        VoiceInkPasteMethod.setCurrent(.standard)
        VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(false)
        VoiceInkClarityStyle.natural.save()
        PowerModeManager.shared.activeConfiguration = nil
        SoundManager.shared.isEnabled = false
        SpecialShortcutEmptyTranscriptionFallback.clear()
        let cleanupDefaults = savedDefaults
        let cleanupSound = savedSound
        let cleanupPowerMode = savedPowerMode
        let cleanupDirectory = directory
        var setupSucceeded = false
        defer {
            if !setupSucceeded {
                SoundManager.shared.isEnabled = cleanupSound
                PowerModeManager.shared.activeConfiguration = cleanupPowerMode
                for key in Self.keys {
                    if let value = cleanupDefaults[key] { defaults.set(value, forKey: key) }
                    else { defaults.removeObject(forKey: key) }
                }
                do { try FileManager.default.removeItem(at: cleanupDirectory) }
                catch { Issue.record("Failed to clean up the owned native setup: \(error)") }
            }
        }
        ai = AIService()
        try Self.writeSetupSnapshot(stage: "after-ai-init", ai: ai, testName: testName, evidence: evidence)
        enhancement = AIEnhancementService(aiService: ai, modelContext: context)
        try Self.writeSetupSnapshot(stage: "after-enhancement-init", ai: ai, testName: testName, evidence: evidence)
        try #require(ai.selectedProvider == .localCLI)
        try #require(ai.isAPIKeyValid)
        try #require(ai.apiKey.isEmpty)
        setupSucceeded = true
    }

    private static func writeSetupSnapshot(stage: String, ai: AIService, testName: String, evidence: URL) throws {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let directory = evidence.appendingPathComponent("setup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(testName + ".json")
        var snapshots: [[String: Any]] = []
        if FileManager.default.fileExists(atPath: file.path) {
            let previous = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            snapshots = previous?["snapshots"] as? [[String: Any]] ?? []
        }
        snapshots.append([
            "stage": stage,
            "provider": ai.selectedProvider.rawValue,
            "isAPIKeyValid": ai.isAPIKeyValid,
            "apiKeyIsEmpty": ai.apiKey.isEmpty,
            "aiCommandMatchesFixture": ai.localCLICommandTemplate == "/usr/bin/true",
            "aiCommandIsConfigured": VoiceInkLocalCLIPreference.isCommandConfigured(ai.localCLICommandTemplate),
            "commandPreferenceMatchesFixture": VoiceInkLocalCLIPreference.commandTemplate() == "/usr/bin/true",
            "commandArgumentDomainKeyExists": arguments[VoiceInkLocalCLIPreference.commandTemplateKey] != nil,
            "standardDefaultsProvider": defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProvider) as Any? ?? NSNull(),
            "argumentDomainProvider": (arguments[VoiceInkUserDefaultsKey.selectedAIProvider] as? String) as Any? ?? NSNull()
        ])
        try JSONSerialization.data(withJSONObject: ["testName": testName, "snapshots": snapshots],
            options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }

    var hostReceipt: [String: Any] {
        ["version": 1, "testName": testName, "classification": "started",
         "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "executablePath": Bundle.main.executableURL?.path ?? "",
         "processIdentifier": ProcessInfo.processInfo.processIdentifier, "sourcePath": #filePath]
    }

    func installCommand(label: String, fails: Bool) throws -> URL {
        let commandDirectory = directory.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: commandDirectory, withIntermediateDirectories: false)
        let response = commandDirectory.appendingPathComponent("response.json")
        try JSONSerialization.data(withJSONObject: ["text": Self.enhanced]).write(to: response)
        let script = commandDirectory.appendingPathComponent("command.sh")
        let content = """
        umask 077
        /bin/cat > \(Self.quote(commandDirectory.appendingPathComponent("stdin.txt").path))
        printf '%s' "$VOICEINK_SYSTEM_PROMPT" > \(Self.quote(commandDirectory.appendingPathComponent("system.txt").path))
        printf '%s' "$VOICEINK_USER_PROMPT" > \(Self.quote(commandDirectory.appendingPathComponent("user.txt").path))
        printf '%s' "$$" > \(Self.quote(commandDirectory.appendingPathComponent("pid.txt").path))
        printf '%s\\n' "$$" >> \(Self.quote(commandDirectory.appendingPathComponent("calls.txt").path))
        \(fails ? "printf '%s' 'Synthetic Clarity failure 23' >&2; exit 23" : "/bin/cat " + Self.quote(response.path))
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        ai.updateLocalCLICommandTemplate("/bin/sh " + Self.quote(script.path))
        return commandDirectory
    }

    func verifyCommand(_ directory: URL, prepared: String, expectedStyle: VoiceInkClarityStyle) throws -> [String: Any] {
        let request = try VoiceInkClarityRequest(transcript: prepared, style: expectedStyle)
        let user = try String(contentsOf: directory.appendingPathComponent("user.txt"), encoding: .utf8)
        let system = try String(contentsOf: directory.appendingPathComponent("system.txt"), encoding: .utf8)
        let childPID = try #require(Int32(String(contentsOf: directory.appendingPathComponent("pid.txt"), encoding: .utf8)))
        let calls = try String(contentsOf: directory.appendingPathComponent("calls.txt"), encoding: .utf8).split(separator: "\n")
        try #require(calls.count == 1 && Int32(calls[0]) == childPID)
        try #require(DictationPolishLiveInputs.exact(user, request.userMessage))
        try #require(DictationPolishLiveInputs.exact(system, request.systemMessage))
        try #require(childPID > 0 && childPID != ProcessInfo.processInfo.processIdentifier)
        let retained = evidence.appendingPathComponent(testName + "-" + directory.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: directory, to: retained)
        return ["childPID": childPID, "requestSystemMessage": system, "requestUserMessage": user,
                "requestFrozen": true, "actualCLIRequestCount": 1]
    }

    func write(_ receipt: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
            .write(to: evidence.appendingPathComponent(testName + ".json"), options: .atomic)
    }

    func close() throws {
        guard !closed else { return }
        closed = true
        SoundManager.shared.isEnabled = savedSound
        PowerModeManager.shared.activeConfiguration = savedPowerMode
        for key in Self.keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try FileManager.default.removeItem(at: directory)
    }

    private static func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

@MainActor
private final class DictationPolishCountingRegistry: TranscriptionServiceRegistry {
    private(set) var returns: [String] = []
    override func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let text = try await super.transcribe(audioURL: audioURL, model: model)
        returns.append(text)
        return text
    }
}

@MainActor
private final class DictationPolishWhisperFixture {
    private let environment: DictationPolishLiveEnvironment
    private let whisper: WhisperModelManager
    private let engine: VoiceInkEngine
    private let registry: DictationPolishCountingRegistry
    private let audio: URL
    private let model: URL
    private var manager: AudioTranscriptionManager?
    private var ownedAudio: URL?
    private var closed = false

    init(environment: DictationPolishLiveEnvironment) throws {
        self.environment = environment
        model = URL(fileURLWithPath: try #require(DictationPolishLiveInputs.value("RJT_DICTATION_POLISH_MODEL")))
        audio = URL(fileURLWithPath: try #require(DictationPolishLiveInputs.value("RJT_DICTATION_POLISH_AUDIO")))
        try #require(DictationPolishLiveInputs.hash(model) == DictationPolishLiveInputs.modelSHA256)
        try #require(DictationPolishLiveInputs.hash(audio) == DictationPolishLiveInputs.audioSHA256)
        whisper = WhisperModelManager(modelsDirectory: environment.directory)
        whisper.availableModels = [.init(name: "base", url: model)]
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = ImportedWhisperModel(fileBaseName: "base")
        engine = VoiceInkEngine(modelContext: environment.context, whisperModelManager: whisper,
            transcriptionModelManager: models, qwenRuntimeResult: .failure(NoneProfileImportFailure.unusedQwenRuntime),
            enhancementService: environment.enhancement)
        registry = DictationPolishCountingRegistry(modelProvider: whisper, modelsDirectory: environment.directory,
            modelContext: environment.context, qwenRuntimeResult: .failure(NoneProfileImportFailure.unusedQwenRuntime))
    }

    func run(profile: VoiceInkDictationProfile, retranscribing: Bool) async throws -> [String: Any] {
        let context = environment.context
        context.insert(WordReplacement(originalText: "fox", replacementText: DictationPolishLiveEnvironment.replacement))
        try context.save()
        profile.save()
        let fails = profile == .clarity && !retranscribing
        let command = try environment.installCommand(label: "file-command", fails: fails)
        try await whisper.loadModel(try #require(whisper.availableModels.first))
        let recognitionContext = try #require(whisper.whisperContext)
        let beforeRecognition = await recognitionContext.getTranscription()
        try #require(beforeRecognition == "")
        var warnings: [String] = []
        var warningSawSavedRecord = false
        let record: Transcription
        if retranscribing {
            let service = AudioTranscriptionService(modelContext: context, serviceRegistry: registry,
                enhancementService: environment.enhancement)
            record = try await service.retranscribeAudio(from: audio, using: ImportedWhisperModel(fileBaseName: "base"))
        } else {
            let queue = AudioTranscriptionManager(serviceRegistryFactory: { _, _ in self.registry }, processingWarning: { reason in
                warnings.append(reason)
                let fresh = ModelContext(self.environment.container)
                if let saved = try? fresh.fetch(FetchDescriptor<Transcription>()).first {
                    warningSawSavedRecord = saved.transcriptionState == .completed && saved.processingFailureReason == reason
                }
            })
            manager = queue
            queue.addToQueue(urls: [audio])
            try #require(queue.queue.count == 1)
            queue.startProcessing(modelContext: context, engine: engine)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(180))
            while queue.isProcessingQueue && clock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
            try #require(!queue.isProcessingQueue)
            let item = try #require(queue.queue.first)
            try #require(item.status == .completed && queue.lastCompletedItemId == item.id)
            record = try #require(item.transcription)
        }
        ownedAudio = try #require(record.audioFileURL.flatMap(URL.init(string:)))
        try #require(registry.returns.count == 1)
        let raw = try #require(registry.returns.first)
        let sameContext = await recognitionContext.getTranscription()
        try #require(DictationPolishLiveInputs.exact(raw, sameContext))
        let words = Set(raw.lowercased().split { !$0.isLetter }.map(String.init))
        try #require(Set(["quick", "brown", "fox"]).isSubset(of: words))
        let range = try #require(raw.range(of: "fox", options: .caseInsensitive))
        try #require(raw[range.upperBound...].range(of: "fox", options: .caseInsensitive) == nil)
        let prepared = String(raw[..<range.lowerBound]) + DictationPolishLiveEnvironment.replacement + String(raw[range.upperBound...])
        let expected = fails ? raw : prepared
        let expectedEnhanced = profile == .clarity && !fails ? DictationPolishLiveEnvironment.enhanced : nil
        let fresh = ModelContext(environment.container)
        let saved = try #require(try fresh.fetch(FetchDescriptor<Transcription>()).first)
        try #require(saved.id == record.id && saved.transcriptionState == .completed)
        try #require(saved.dictationProfile == profile)
        try #require(saved.clarityStyle == (profile == .clarity ? .natural : nil))
        let capturedRaw = try #require(saved.recognitionText)
        try #require(DictationPolishLiveInputs.exact(capturedRaw, raw))
        try #require(DictationPolishLiveInputs.exact(saved.text, expected))
        if let expectedEnhanced {
            try #require(DictationPolishLiveInputs.exact(try #require(saved.enhancedText), expectedEnhanced))
        } else { try #require(saved.enhancedText == nil) }
        try #require(warnings.count == (fails ? 1 : 0))
        if fails {
            try #require(saved.processingFailureReason?.isEmpty == false)
            try #require(warningSawSavedRecord)
        }
        else { try #require(saved.processingFailureReason == nil) }
        let permanent = try #require(ownedAudio)
        try #require(permanent.isFileURL && FileManager.default.fileExists(atPath: permanent.path))
        try FileManager.default.copyItem(at: permanent,
            to: environment.evidence.appendingPathComponent(environment.testName + ".wav"))
        var receipt: [String: Any] = [
            "modelSHA256": try DictationPolishLiveInputs.hash(model), "audioSHA256": try DictationPolishLiveInputs.hash(audio),
            "profile": profile.rawValue, "style": saved.clarityStyleRawValue as Any? ?? NSNull(),
            "sameContextRecognition": sameContext, "recognitionText": capturedRaw, "storedText": saved.text,
            "enhancedText": saved.enhancedText as Any? ?? NSNull(), "expectedText": expected,
            "expectedEnhancedText": expectedEnhanced as Any? ?? NSNull(),
            "processingFailureReason": saved.processingFailureReason as Any? ?? NSNull(),
            "warningCount": warnings.count, "warnings": warnings, "recordID": saved.id.uuidString,
            "warningSawSavedRecord": warningSawSavedRecord,
            "permanentAudioURL": permanent.absoluteString,
            "permanentAudioSHA256": try DictationPolishLiveInputs.hash(permanent),
            "utf8Equal": true, "utf16Equal": true, "sameContextRecognitionExact": true,
            "actualWhisperInferenceCount": registry.returns.count,
            "scope": "One real Whisper service dispatch, same loaded context and actual file adapter; synthetic committed WAV.",
            "limitations": "No microphone, human speech, editor insertion, model semantics or crash/relaunch durability."
        ]
        if profile == .clarity {
            receipt.merge(try environment.verifyCommand(command, prepared: prepared, expectedStyle: .natural)) { _, new in new }
            if !fails {
                let request = try VoiceInkClarityRequest(transcript: prepared, style: .natural)
                try #require(saved.aiRequestSystemMessage == request.systemMessage && saved.aiRequestUserMessage == request.userMessage)
                try #require(saved.aiEnhancementModelName == "local-cli")
            } else {
                try #require(saved.aiRequestSystemMessage == nil && saved.aiRequestUserMessage == nil && saved.aiEnhancementModelName == nil)
            }
        } else {
            try #require(!FileManager.default.fileExists(atPath: command.appendingPathComponent("pid.txt").path))
            receipt["actualCLIRequestCount"] = 0
        }
        return receipt
    }

    func close() async throws {
        guard !closed else { return }
        closed = true
        manager?.clearAll()
        await registry.cleanup()
        await engine.cleanupResources()
        if let ownedAudio { try FileManager.default.removeItem(at: ownedAudio) }
    }
}
