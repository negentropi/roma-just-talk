import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test @MainActor func spokenSnippetPipelineInsertsExactWholeTriggerContentAndSavesIt() async throws {
        let fixture = try SpokenSnippetPipelineFixture(enableEnhancement: true)
        defer { fixture.restore() }
        try fixture.setSnippets(trigger: "my signature", content: "\nFelix C. Order\nRJT, Inc.\n\n")

        let record = await fixture.run("MY SIGNATURE.")

        #expect(fixture.delivered == ["\nFelix C. Order\nRJT, Inc.\n\n"])
        #expect(fixture.enhancementCalls == 0)
        #expect(record.text == "MY SIGNATURE.")
        #expect(record.enhancedText == "\nFelix C. Order\nRJT, Inc.\n\n")
        #expect(record.transcriptionState == .completed)
        let saved = try fixture.context.fetch(FetchDescriptor<Transcription>())
        #expect(saved.count == 1)
        #expect(saved.first?.enhancedText == "\nFelix C. Order\nRJT, Inc.\n\n")
        #expect(fixture.dismissCount == 1)
    }

    @Test @MainActor func spokenSnippetPipelinePreservesInlineCapitalsPunctuationAndParagraphs() async throws {
        let fixture = try SpokenSnippetPipelineFixture(enableEnhancement: true)
        defer { fixture.restore() }
        try fixture.setSnippets(trigger: "my address", content: "First Floor, 10 Main St.\n\nTaipei 100")

        let record = await fixture.run("Please send MY ADDRESS today.")

        #expect(fixture.delivered == ["Please send First Floor, 10 Main St.\n\nTaipei 100 today."])
        #expect(fixture.enhancementCalls == 0)
        #expect(record.text == "Please send MY ADDRESS today.")
        #expect(record.enhancedText == "Please send First Floor, 10 Main St.\n\nTaipei 100 today.")
        #expect(record.transcriptionState == .completed)
        #expect(fixture.dismissCount == 1)
    }

    @Test @MainActor func spokenSnippetPipelineLeavesUnmatchedDictationOnItsExistingFormattingPath() async throws {
        let fixture = try SpokenSnippetPipelineFixture()
        defer { fixture.restore() }
        try fixture.setSnippets(trigger: "my signature", content: "Felix")

        let record = await fixture.run("Ordinary Dictated Words.")

        #expect(fixture.delivered == ["ordinary dictated words "])
        #expect(record.text == "ordinary dictated words")
        #expect(record.enhancedText == nil)
        #expect(record.transcriptionState == .completed)
        #expect(fixture.dismissCount == 1)
    }
}

@MainActor
private final class SpokenSnippetPipelineFixture {
    private let container: ModelContainer
    let context: ModelContext
    private let pipeline: TranscriptionPipeline
    private let provider: SnippetUnusedWhisperProvider
    private let enhancement: SnippetNeverEnhanceService?
    private let savedDefaults: [String: Any]
    private let savedPowerMode: PowerModeConfig?
    private let savedSoundEnabled: Bool
    private static let keys = [
        "VoiceInkDictationProfile",
        "VoiceInkSpokenSnippets",
        VoiceInkUserDefaultsKey.isTextFormattingEnabled,
        VoiceInkUserDefaultsKey.lowercaseTranscription,
        VoiceInkUserDefaultsKey.removeFillerWords,
        VoiceInkUserDefaultsKey.appendTrailingSpace,
        PunctuationCleanupMode.userDefaultsKey,
        PunctuationCleanupMode.legacyRemovePunctuationKey,
        VoiceInkPasteMethod.userDefaultsKey,
        VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey,
        VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.skipShortEnhancement
    ]
    var delivered: [String] = []
    var dismissCount = 0
    var enhancementCalls: Int { enhancement?.calls ?? 0 }

    init(enableEnhancement: Bool = false) throws {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let configuration = ModelConfiguration(
            "SpokenSnippetPipeline-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        self.container = container
        let modelContext = container.mainContext
        context = modelContext
        let modelProvider = SnippetUnusedWhisperProvider()
        provider = modelProvider
        let registry = TranscriptionServiceRegistry(
            modelProvider: modelProvider,
            modelsDirectory: FileManager.default.temporaryDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: .failure(SnippetFixtureError.unusedRuntime)
        )
        let defaults = UserDefaults.standard
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        savedSoundEnabled = SoundManager.shared.isEnabled
        defaults.set("custom", forKey: "VoiceInkDictationProfile")
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(enableEnhancement, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        let enhancement = enableEnhancement
            ? SnippetNeverEnhanceService(aiService: AIService(), modelContext: modelContext) : nil
        self.enhancement = enhancement
        pipeline = TranscriptionPipeline(modelContext: modelContext, serviceRegistry: registry, enhancementService: enhancement)
        PunctuationCleanupMode.setCurrent(.removeAll)
        VoiceInkPasteMethod.setCurrent(.standard)
        PowerModeManager.shared.activeConfiguration = nil
        SoundManager.shared.isEnabled = false
        CursorPaster.configureAccessibilityTextInserterForTesting { [weak self] text, _ in
            self?.delivered.append(text)
            return .inserted
        }
    }

    func setSnippets(trigger: String, content: String) throws {
        let payload: [[String: Any]] = [[
            "id": "908E575D-1138-4E13-879C-C86A370DBCF8",
            "trigger": trigger,
            "content": content,
            "enabled": true
        ]]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: payload), forKey: "VoiceInkSpokenSnippets")
    }

    func run(_ transcript: String) async -> Transcription {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("snippet-\(UUID().uuidString).wav")
        let record = Transcription(text: "", duration: 1, audioFileURL: audioURL.absoluteString)
        context.insert(record)
        await pipeline.run(
            transcription: record,
            audioURL: audioURL,
            model: TranscriptionModelRegistry.defaultMacOSFluidAudioModel,
            session: SnippetTranscriptSession(text: transcript),
            latencyTraceToken: nil,
            onStateChange: { _ in },
            shouldCancel: { false },
            onCancel: { Issue.record("Successful dictation must not cancel") },
            onDismiss: { self.dismissCount += 1 }
        )
        return record
    }

    func restore() {
        CursorPaster.configureAccessibilityTextInserterForTesting()
        SoundManager.shared.isEnabled = savedSoundEnabled
        for key in Self.keys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        PowerModeManager.shared.activeConfiguration = savedPowerMode
    }
}

private enum SnippetFixtureError: Error { case unusedRuntime }

@MainActor
private final class SnippetNeverEnhanceService: AIEnhancementService {
    var calls = 0
    override var isConfigured: Bool { true }

    override func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        calls += 1
        return VoiceInkAIEnhancementResult(
            text: "UNEXPECTED AI OUTPUT",
            duration: 0,
            modelName: "never-call-fixture",
            promptName: nil,
            requestSystemMessage: nil,
            requestUserMessage: nil
        )
    }
}

@MainActor
private final class SnippetUnusedWhisperProvider: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class SnippetTranscriptSession: TranscriptionSession {
    private let text: String

    init(text: String) { self.text = text }

    func prepare(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String { text }
    func cancel() {}
}
