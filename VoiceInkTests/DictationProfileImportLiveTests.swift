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
        DictionaryService.invalidateWordReplacementCache()
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
        DictionaryService.invalidateWordReplacementCache()
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
