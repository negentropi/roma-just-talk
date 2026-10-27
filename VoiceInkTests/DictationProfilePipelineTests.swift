import AVFoundation
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test @MainActor func dictationNonePreservesSnippetTriggersAndReplacementWordsLiterally() async throws {
        let fixture = try DictationProfilePipelineFixture()
        defer { fixture.restore() }
        fixture.setProfile("none")
        try fixture.installSnippet()
        let raw = "\n  MY SIGNATURE Roma [keep this] <literal>quoted</literal>\n\n繁體中文 👩🏽‍💻 e\u{301}  \n"

        let record = await fixture.run(raw)

        #expect(fixture.delivered.count == 1)
        #expect(fixture.delivered.first?.utf8.elementsEqual(raw.utf8) == true, "None snippet-trigger dictation must deliver exact UTF-8 recognition text.")
        #expect(fixture.delivered.first?.utf16.elementsEqual(raw.utf16) == true, "None snippet-trigger dictation must deliver exact UTF-16 recognition text.")
        #expect(record.text.utf8.elementsEqual(raw.utf8))
        #expect(record.text.utf16.elementsEqual(raw.utf16))
        #expect(record.enhancedText == nil, "None snippet-trigger dictation must not store an expanded result.")
        #expect(record.transcriptionState == .completed)
        #expect(fixture.enhancementCalls == 0)
        #expect(fixture.promptDetectionCalls == 0)
        let saved = try fixture.freshSavedRecord(id: record.id)
        #expect(saved.text.utf8.elementsEqual(raw.utf8))
        #expect(saved.text.utf16.elementsEqual(raw.utf16))
        #expect(saved.enhancedText == nil, "Saved None snippet-trigger dictation must not store an expanded result.")
        #expect(fixture.dismissCount == 1)
    }

    @Test @MainActor func dictationNoneDoesNotActivatePromptTriggersOrAI() async throws {
        let fixture = try DictationProfilePipelineFixture(enableEnhancement: false)
        defer { fixture.restore() }
        fixture.setProfile("none")
        let raw = "voice change Roma  um [keep] <literal>stay</literal> \"new line\".\n繁體中文 👩🏽‍💻"
        #expect(fixture.hasPromptTriggers)

        let record = await fixture.run(raw)

        #expect(fixture.delivered.count == 1)
        #expect(fixture.delivered.first?.utf8.elementsEqual(raw.utf8) == true, "None prompt-trigger dictation must deliver exact UTF-8 recognition text.")
        #expect(fixture.delivered.first?.utf16.elementsEqual(raw.utf16) == true, "None prompt-trigger dictation must deliver exact UTF-16 recognition text.")
        #expect(record.text.utf8.elementsEqual(raw.utf8), "None prompt-trigger dictation must save exact recognition text.")
        #expect(record.enhancedText == nil, "None prompt-trigger dictation must not store AI output.")
        #expect(fixture.promptDetectionCalls == 0, "None prompt-trigger dictation must not analyze prompt triggers.")
        #expect(fixture.enhancementCalls == 0, "None prompt-trigger dictation must not request AI output.")
        #expect(!fixture.isEnhancementEnabled)
    }

    @Test @MainActor func dictationCustomRetainsItsExistingCleanupPath() async throws {
        let fixture = try DictationProfilePipelineFixture(enableEnhancement: false)
        defer { fixture.restore() }
        fixture.setProfile("custom")

        let record = await fixture.run("Ordinary Dictated Words.")

        #expect(fixture.delivered == ["ordinary dictated words "])
        #expect(record.text == "ordinary dictated words")
        #expect(record.enhancedText == nil)
        #expect(record.transcriptionState == .completed)
        #expect(fixture.enhancementCalls == 0)
    }

    @Test @MainActor func dictationNoneKeepsItsProfileWhileRecognitionWaits() async throws {
        let fixture = try DictationProfilePipelineFixture(enableEnhancement: false)
        defer { fixture.restore() }
        fixture.setProfile("none")
        let raw = "  Keep [literal] Roma.\n\n繁體中文 👩🏽‍💻  "
        let gate = DictationRecognitionGate()
        let pending = Task { await fixture.run(raw, gate: gate) }
        let entered = await gate.waitUntilEntered()
        fixture.setProfile("custom")
        gate.release()
        let first = await pending.value
        #expect(entered, "Recognition did not reach the owned gate.")
        #expect(fixture.delivered.first?.utf8.elementsEqual(raw.utf8) == true)
        #expect(fixture.delivered.first?.utf16.elementsEqual(raw.utf16) == true)
        #expect(first.text.utf8.elementsEqual(raw.utf8))
        #expect(first.enhancedText == nil)

        let second = await fixture.run("Ordinary Dictated Words.")

        #expect(fixture.delivered.count == 2)
        #expect(fixture.delivered.last == "ordinary dictated words ")
        #expect(second.text == "ordinary dictated words")
        #expect(second.enhancedText == nil)
        #expect(fixture.enhancementCalls == 0)
    }

    @Test @MainActor func dictationNoneCancellationDuringRecognitionDoesNotDeliver() async throws {
        let fixture = try DictationProfilePipelineFixture()
        defer { fixture.restore() }
        fixture.setProfile("none")
        let gate = DictationRecognitionGate()
        let pending = Task { await fixture.run("Keep this raw.", gate: gate) }
        let entered = await gate.waitUntilEntered()
        fixture.shouldCancel = true
        gate.release()
        let record = await pending.value

        #expect(entered, "Recognition did not reach the owned gate.")
        #expect(fixture.delivered.isEmpty)
        #expect(fixture.enhancementCalls == 0)
        #expect(fixture.promptDetectionCalls == 0)
        #expect(fixture.cancelCount == 1)
        #expect(fixture.completedRecordingNotifications == 0)
        let metrics = try fixture.context.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.isEmpty)
        #expect(record.transcriptionState == .canceled)
        let saved = try fixture.freshSavedRecord(id: record.id)
        #expect(saved.transcriptionState == .canceled)
    }

    @Test @MainActor func dictationNoneBlankRecognitionConsumesPendingPreviousTextFallback() async throws {
        for raw in ["", " \n\t "] {
            let fixture = try DictationProfilePipelineFixture(enableEnhancement: false)
            defer { fixture.restore() }
            fixture.setProfile("none")
            SpecialShortcutEmptyTranscriptionFallback.scheduleFallback()

            let record = await fixture.run(raw)
            let sentinel = Transcription(text: "", duration: 1, transcriptionStatus: .completed)
            let pendingWasLeftBehind = SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(
                for: sentinel,
                modelContext: fixture.context
            )

            #expect(record.text.utf8.elementsEqual(raw.utf8))
            #expect(record.enhancedText == nil)
            #expect(record.transcriptionState == .completed)
            #expect(fixture.delivered.isEmpty)
            #expect(!pendingWasLeftBehind)
            #expect(fixture.enhancementCalls == 0)
        }
    }

    @Test @MainActor func retranscriptionNonePreservesRecognitionWithoutPromptOrAI() async throws {
        let fixture = try DictationProfilePipelineFixture()
        defer { fixture.restore() }
        fixture.setProfile("none")
        let raw = "\n voice change Roma [keep] <literal>stay</literal>\n\n繁體中文 👩🏽‍💻 e\u{301}  "
        fixture.registry.recognizedText = raw
        let audio = try fixture.makeAudioFile()

        let record = try await fixture.retranscribe(audio)

        #expect(record.text.utf8.elementsEqual(raw.utf8))
        #expect(record.text.utf16.elementsEqual(raw.utf16))
        #expect(record.enhancedText == nil)
        #expect(record.transcriptionState == .completed)
        #expect(fixture.enhancementCalls == 0)
        #expect(fixture.promptDetectionCalls == 0)
        #expect(fixture.delivered.isEmpty)
        #expect(fixture.registry.calls == 1)
        let saved = try fixture.freshSavedRecord(id: record.id)
        #expect(saved.text.utf8.elementsEqual(raw.utf8))
        #expect(saved.text.utf16.elementsEqual(raw.utf16))
        #expect(saved.enhancedText == nil)
    }

    @Test @MainActor func retranscriptionNoneKeepsItsProfileWhileRecognitionWaits() async throws {
        let fixture = try DictationProfilePipelineFixture(enableEnhancement: false)
        defer { fixture.restore() }
        fixture.setProfile("none")
        let raw = "  Keep [literal] Roma.\n繁體中文 👩🏽‍💻  "
        fixture.registry.recognizedText = raw
        let audio = try fixture.makeAudioFile()
        let gate = DictationRecognitionGate()
        fixture.registry.gate = gate
        let pending = Task { try await fixture.retranscribe(audio) }
        let entered = await gate.waitUntilEntered()
        fixture.setProfile("custom")
        gate.release()
        let first = try await pending.value
        #expect(entered, "Retranscription did not reach the owned gate.")
        #expect(first.text.utf8.elementsEqual(raw.utf8))
        #expect(first.text.utf16.elementsEqual(raw.utf16))
        #expect(first.enhancedText == nil)

        fixture.registry.gate = nil
        fixture.registry.recognizedText = "Ordinary Dictated Words."
        let second = try await fixture.retranscribe(audio)

        #expect(second.text == "ordinary dictated words")
        #expect(second.enhancedText == nil)
        #expect(fixture.enhancementCalls == 0)
        #expect(fixture.registry.calls == 2)
    }

    @Test @MainActor func retranscriptionNoneCancellationAfterRecognitionDoesNotSaveFallback() async throws {
        let fixture = try DictationProfilePipelineFixture()
        defer { fixture.restore() }
        fixture.setProfile("none")
        fixture.registry.recognizedText = "voice change Roma [keep]."
        let audio = try fixture.makeAudioFile()
        let gate = DictationRecognitionGate()
        fixture.registry.gate = gate
        let pending = Task { try await fixture.retranscribe(audio) }
        let entered = await gate.waitUntilEntered()
        pending.cancel()
        gate.release()
        var receivedCancellation = false
        do {
            _ = try await pending.value
        } catch is CancellationError {
            receivedCancellation = true
        }

        #expect(entered, "Retranscription did not reach the owned gate.")
        #expect(receivedCancellation)
        let saved = try fixture.context.fetch(FetchDescriptor<Transcription>())
        #expect(saved.isEmpty)
        #expect(fixture.enhancementCalls == 0)
        #expect(fixture.promptDetectionCalls == 0)
        #expect(fixture.delivered.isEmpty)
    }
    @Test @MainActor func canceledQueuedDictationPasteDoesNotWriteTheTarget() async {
        let defaults = UserDefaults.standard
        let previousMethod = defaults.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
        var writes: [String] = []
        VoiceInkPasteMethod.setCurrent(.standard)
        CursorPaster.configureAccessibilityTextInserterForTesting { text, _ in
            writes.append(text)
            return .inserted
        }
        defer {
            CursorPaster.configureAccessibilityTextInserterForTesting()
            if let previousMethod {
                defaults.set(previousMethod, forKey: VoiceInkPasteMethod.userDefaultsKey)
            } else {
                defaults.removeObject(forKey: VoiceInkPasteMethod.userDefaultsKey)
            }
        }

        let paste = CursorPaster.startPasteAtCursor("Canceled queued text")
        paste.cancel()
        let result = await paste.value

        #expect(result == .commandNotPosted, "A canceled queued dictation paste must return commandNotPosted.")
        #expect(writes.isEmpty, "A canceled queued dictation paste must not call the target inserter.")
    }
}

@MainActor
private final class DictationProfilePipelineFixture {
    private static let profileKey = "VoiceInkDictationProfile"
    private static let keys = [
        profileKey,
        "VoiceInkSpokenSnippets",
        VoiceInkUserDefaultsKey.isTextFormattingEnabled,
        VoiceInkUserDefaultsKey.lowercaseTranscription,
        VoiceInkUserDefaultsKey.removeFillerWords,
        VoiceInkUserDefaultsKey.fillerWords,
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
    private let container: ModelContainer
    let context: ModelContext
    let registry: DictationProfileRegistry
    private let provider: DictationUnusedWhisperProvider
    private let enhancement: DictationProfileEnhancementSpy
    private let pipeline: TranscriptionPipeline
    private let temporaryDirectory: URL
    private let savedDefaults: [String: Any]
    private let savedPowerMode: PowerModeConfig?
    private let savedSoundEnabled: Bool
    private var completionObserver: NSObjectProtocol?
    private var ownedRecordingIDs = Set<UUID>()
    private(set) var completedRecordingNotifications = 0
    var delivered: [String] = []
    var dismissCount = 0
    var cancelCount = 0
    var shouldCancel = false
    var enhancementCalls: Int { enhancement.calls }
    var promptDetectionCalls: Int { enhancement.promptDetectionCalls }
    var hasPromptTriggers: Bool { enhancement.hasPromptTriggerWords }
    var isEnhancementEnabled: Bool { enhancement.isEnhancementEnabled }

    init(enableEnhancement: Bool = true) throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictationProfile-\(UUID().uuidString)", isDirectory: true)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let configuration = ModelConfiguration(
            "DictationProfile-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
        provider = DictationUnusedWhisperProvider()
        registry = DictationProfileRegistry(
            modelProvider: provider,
            modelsDirectory: temporaryDirectory,
            modelContext: context,
            qwenRuntimeResult: .failure(DictationProfileFixtureError.unusedRuntime)
        )
        context.insert(WordReplacement(originalText: "Roma", replacementText: "CHANGED REPLACEMENT"))
        try context.save()
        let defaults = UserDefaults.standard
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        savedSoundEnabled = SoundManager.shared.isEnabled
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(["um"], forKey: VoiceInkUserDefaultsKey.fillerWords)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(enableEnhancement, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
        defaults.removeObject(forKey: "VoiceInkSpokenSnippets")
        let prompt = VoiceInkCustomPrompt(
            id: UUID(uuidString: "252CB58C-93DC-4E3C-98D5-E2ADFC6FCDF9")!,
            title: "Owned trigger fixture",
            promptText: "Never execute in None.",
            triggerWords: ["voice change"]
        )
        VoiceInkCustomPromptStorage.savePrompts([prompt])
        VoiceInkCustomPromptStorage.saveSelectedPromptId(nil)
        enhancement = DictationProfileEnhancementSpy(aiService: AIService(), modelContext: context)
        pipeline = TranscriptionPipeline(modelContext: context, serviceRegistry: registry, enhancementService: enhancement)
        PunctuationCleanupMode.setCurrent(.removeAll)
        VoiceInkPasteMethod.setCurrent(.standard)
        PowerModeManager.shared.activeConfiguration = nil
        SoundManager.shared.isEnabled = false
        discardPendingFallback()
        CursorPaster.configureAccessibilityTextInserterForTesting { [weak self] text, _ in
            self?.delivered.append(text)
            return .inserted
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .transcriptionCompleted, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let record = notification.object as? Transcription,
                      self.ownedRecordingIDs.contains(record.id) else { return }
                self.completedRecordingNotifications += 1
            }
        }
    }

    func setProfile(_ value: String) {
        UserDefaults.standard.set(value, forKey: Self.profileKey)
    }

    func installSnippet() throws {
        let rows: [[String: Any]] = [[
            "id": "D63A1561-64B5-4E93-96D4-EB6072D25AC2",
            "trigger": "my signature",
            "content": "UNEXPECTED SNIPPET\n",
            "enabled": true
        ]]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: rows), forKey: "VoiceInkSpokenSnippets")
    }

    func run(_ text: String, gate: DictationRecognitionGate? = nil) async -> Transcription {
        let record = Transcription(text: "", duration: 1)
        ownedRecordingIDs.insert(record.id)
        context.insert(record)
        await pipeline.run(
            transcription: record,
            audioURL: temporaryDirectory.appendingPathComponent("unused.wav"),
            model: TranscriptionModelRegistry.defaultMacOSFluidAudioModel,
            session: DictationRecognitionSession(text: text, gate: gate),
            latencyTraceToken: nil,
            onStateChange: { _ in },
            shouldCancel: { self.shouldCancel },
            onCancel: { self.cancelCount += 1 },
            onDismiss: { self.dismissCount += 1 }
        )
        return record
    }

    func makeAudioFile() throws -> URL {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let url = temporaryDirectory.appendingPathComponent("input-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        buffer.floatChannelData![0].initialize(repeating: 0, count: 1_600)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func retranscribe(_ audio: URL) async throws -> Transcription {
        let service = AudioTranscriptionService(modelContext: context, serviceRegistry: registry, enhancementService: enhancement)
        return try await service.retranscribeAudio(from: audio, using: TranscriptionModelRegistry.defaultMacOSFluidAudioModel)
    }

    func freshSavedRecord(id: UUID) throws -> (text: String, enhancedText: String?, transcriptionState: VoiceInkTranscriptionStatus?) {
        let freshContext = ModelContext(container)
        let records = try freshContext.fetch(FetchDescriptor<Transcription>())
        let record = try #require(records.first { $0.id == id })
        return (record.text, record.enhancedText, record.transcriptionState)
    }

    private func discardPendingFallback() {
        let sentinel = Transcription(text: "Owned fixture cleanup", duration: 1, transcriptionStatus: .completed)
        _ = SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(for: sentinel, modelContext: context)
    }

    func restore() {
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        CursorPaster.configureAccessibilityTextInserterForTesting()
        discardPendingFallback()
        SoundManager.shared.isEnabled = savedSoundEnabled
        for key in Self.keys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        PowerModeManager.shared.activeConfiguration = savedPowerMode
        if let records = try? context.fetch(FetchDescriptor<Transcription>()) {
            for record in records {
                if let value = record.audioFileURL, let url = URL(string: value),
                   url.isFileURL, url.deletingLastPathComponent() == VoiceInkMacOSStorageDirectories.appSupportDirectory
                    .appendingPathComponent("Recordings", isDirectory: true) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

private enum DictationProfileFixtureError: Error { case unusedRuntime }

@MainActor
private final class DictationProfileEnhancementSpy: AIEnhancementService {
    var calls = 0
    var promptDetectionCalls = 0
    override var isConfigured: Bool { true }

    override func analyzePromptTrigger(in text: String) -> VoiceInkPromptDetectionResult {
        promptDetectionCalls += 1
        return super.analyzePromptTrigger(in: text)
    }

    override func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        calls += 1
        return VoiceInkAIEnhancementResult(
            text: "UNEXPECTED AI OUTPUT",
            duration: 0,
            modelName: "owned-profile-fixture",
            promptName: nil,
            requestSystemMessage: nil,
            requestUserMessage: nil
        )
    }
}

@MainActor
private final class DictationUnusedWhisperProvider: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class DictationProfileRegistry: TranscriptionServiceRegistry {
    var recognizedText = ""
    var gate: DictationRecognitionGate?
    var calls = 0

    override func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        calls += 1
        await gate?.enterAndWait()
        return recognizedText
    }
}

@MainActor
private final class DictationRecognitionSession: TranscriptionSession {
    private let text: String
    private let gate: DictationRecognitionGate?

    init(text: String, gate: DictationRecognitionGate?) {
        self.text = text
        self.gate = gate
    }

    func prepare(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String {
        await gate?.enterAndWait()
        return text
    }

    func cancel() {}
}

@MainActor
private final class DictationRecognitionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Bool, Never>?
    private var entered = false
    private var released = false

    func enterAndWait() async {
        entered = true
        observer?.resume(returning: true)
        observer = nil
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async -> Bool {
        if entered { return true }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            observer?.resume(returning: false)
            observer = nil
        }
        let result = await withCheckedContinuation { observer = $0 }
        timeout.cancel()
        return result
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
