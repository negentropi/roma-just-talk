import AppKit
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct WritingActionDeliveryCommitTests {
        @Test @MainActor func cancellationAfterConfirmedWritingMutationKeepsGeneratedMetadata() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            fixture.access.afterMutation = { fixture.canceled = true }
            let record = try await fixture.run()
            #expect(fixture.access.value.utf16.elementsEqual(fixture.expectedDocument.utf16))
            #expect(fixture.access.attempts == 1)
            #expect(record.transcriptionState == .completed, "Confirmed external delivery must not become a canceled recording.")
            #expect(record.text == fixture.instruction)
            #expect(record.enhancedText?.utf16.elementsEqual(fixture.enhancement.output.utf16) == true)
            #expect(record.aiEnhancementModelName == "owned-writing-model")
            #expect(record.aiRequestSystemMessage == "owned system request")
            #expect(record.aiRequestUserMessage == "owned user request")
            #expect(fixture.cancellations == 0)
            let saved = try fixture.savedRecord(record.id)
            #expect(saved.transcriptionState == .completed)
            #expect(saved.text == fixture.instruction)
            #expect(saved.enhancedText?.utf16.elementsEqual(fixture.enhancement.output.utf16) == true)
            #expect(saved.aiRequestSystemMessage == "owned system request")
            #expect(saved.aiRequestUserMessage == "owned user request")
        }

        @Test @MainActor func cancellationAfterUnconfirmedWritingMutationKeepsRecoveryMetadata() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            fixture.access.partialValue = "prefix partial e\u{301} 🧪 suffix"
            fixture.access.afterMutation = { fixture.canceled = true }
            let record = try await fixture.run()
            #expect(fixture.access.value == "prefix partial e\u{301} 🧪 suffix")
            #expect(fixture.access.attempts == 1, "An uncertain editor action must never trigger an automatic second edit.")
            #expect(record.transcriptionState == .failed, "An attempted unconfirmed edit retains a recoverable failed result.")
            #expect(record.text == fixture.instruction)
            #expect(record.enhancedText?.utf8.elementsEqual(fixture.enhancement.output.utf8) == true)
            #expect(record.aiEnhancementModelName == "owned-writing-model")
            #expect(record.aiRequestSystemMessage == "owned system request")
            #expect(record.aiRequestUserMessage == "owned user request")
            #expect(fixture.cancellations == 0)
            let saved = try fixture.savedRecord(record.id)
            #expect(saved.transcriptionState == .failed)
            #expect(saved.text == fixture.instruction)
            #expect(saved.enhancedText?.utf16.elementsEqual(fixture.enhancement.output.utf16) == true)
            #expect(saved.aiRequestSystemMessage == "owned system request")
            #expect(saved.aiRequestUserMessage == "owned user request")
        }
    }
}

/// Uses the captured-value session initializer in both lanes. The old lane adds only that initializer;
/// its pipeline, target and cancellation implementation remain the actual predecessor source.
@MainActor
final class WritingDeliveryFixture {
    let directory: URL
    let container: ModelContainer
    let context: ModelContext
    let registry: TranscriptionServiceRegistry
    let enhancement: WritingDeliveryEnhancement
    let access = WritingDeliveryAccess()
    let instruction = "Rewrite the selected phrase without changing its identifier."
    var canceled = false
    var cancellations = 0
    var dismissals = 0
    var notices: [String] = []
    var saveFailures: [String] = []
    private let defaults = UserDefaults.standard
    private let savedDefaults: [String: Any]
    private let savedSound: Bool
    private let provider = WritingDeliveryUnusedWhisper()
    lazy var pipeline = TranscriptionPipeline(modelContext: context, serviceRegistry: registry, enhancementService: enhancement)

    var expectedDocument: String { "prefix \(enhancement.output) suffix" }

    private static let keys = [
        VoiceInkUserDefaultsKey.selectedAIProvider, VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.customPrompts, VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.useClipboardContext, VoiceInkUserDefaultsKey.useScreenCaptureContext,
        VoiceInkUserDefaultsKey.enhancementTimeoutSeconds, VoiceInkUserDefaultsKey.enhancementRetryOnTimeout,
        VoiceInkLocalCLIPreference.commandTemplateKey, VoiceInkLocalCLIPreference.timeoutSecondsKey,
        VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey
    ]

    init(readOnly: Bool = false) throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        savedSound = SoundManager.shared.isEnabled
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Writing-Delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let configuration: ModelConfiguration
        if readOnly {
            let url = directory.appendingPathComponent("read-only.store")
            try Self.seed(schema: schema, url: url)
            configuration = ModelConfiguration("WritingDeliveryReadOnly", schema: schema, url: url,
                allowsSave: false, cloudKitDatabase: .none)
            try #require(!configuration.allowsSave && configuration.groupAppContainerIdentifier == nil)
        } else {
            configuration = ModelConfiguration("WritingDelivery-\(UUID().uuidString)", schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        registry = TranscriptionServiceRegistry(modelProvider: provider, modelsDirectory: directory,
            modelContext: context, qwenRuntimeResult: .failure(WritingDeliveryFixtureError.unusedRecognizer))
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(Data("[]".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
        defaults.set(5, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set("/bin/cat", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(5, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        SoundManager.shared.isEnabled = false
        do {
            let ai = AIService()
            try #require(ai.selectedProvider == .localCLI && ai.isAPIKeyValid && ai.apiKey.isEmpty)
            enhancement = WritingDeliveryEnhancement(aiService: ai, modelContext: context)
        } catch {
            SoundManager.shared.isEnabled = savedSound
            for key in Self.keys {
                if let value = savedDefaults[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func session(kind: VoiceInkWritingActionKind = .rewriteSelection, access: WritingDeliveryAccess? = nil) throws -> WritingActionSession {
        let destination = access ?? self.access
        return try WritingActionSession(
            kind: kind, targetLanguage: "en", target: destination.target(), provider: enhancement.providerSnapshot()
        )
    }

    func run(
        kind: VoiceInkWritingActionKind = .rewriteSelection,
        pipeline suppliedPipeline: TranscriptionPipeline? = nil,
        access suppliedAccess: WritingDeliveryAccess? = nil,
        onDismiss: (() async -> Void)? = nil
    ) async throws -> Transcription {
        let record = Transcription(text: "", duration: 1)
        context.insert(record)
        let writing = try session(kind: kind, access: suppliedAccess)
        let recognizer = WritingDeliveryRecognizer(text: instruction)
        await (suppliedPipeline ?? pipeline).run(
            transcription: record, audioURL: directory.appendingPathComponent("synthetic.wav"),
            model: TranscriptionModelRegistry.defaultMacOSFluidAudioModel, session: recognizer,
            writingSession: writing, spokenSnippets: [], latencyTraceToken: nil,
            onStateChange: { _ in }, shouldCancel: { self.canceled },
            onCancel: { self.cancellations += 1 },
            onDismiss: { self.dismissals += 1; await onDismiss?() }
        )
        return record
    }

    func savedRecord(_ id: UUID) throws -> Transcription {
        let fresh = ModelContext(container)
        return try #require(fresh.fetch(FetchDescriptor<Transcription>()).first { $0.id == id })
    }

    func close() {
        enhancement.gate?.release()
        NotificationManager.shared.dismissNotification()
        SoundManager.shared.isEnabled = savedSound
        for key in Self.keys {
            if let value = savedDefaults[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func seed(schema: Schema, url: URL) throws {
        let configuration = ModelConfiguration("WritingDeliveryReadOnly", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(VocabularyWord(word: "Owned writing save-failure seed"))
        try context.save()
    }
}

@MainActor
final class WritingDeliveryAccess: WritingTarget.Access {
    var value = "prefix old suffix"
    var range = NSRange(location: 7, length: 3)
    var partialValue: String?
    var afterMutation: (() -> Void)?
    var validationFailure: WritingTarget.Failure?
    private(set) var attempts = 0
    var supportsUndoSelection: Bool { true }
    var isUndoTargetAlive: Bool { true }
    func validate() throws { if let validationFailure { throw validationFailure } }
    func validateUndoIdentity() throws { try validate() }
    func isUndoTargetApplication(_ application: NSRunningApplication) -> Bool { false }
    func readValue() -> String? { value }
    func readSnapshot() -> WritingTarget.TextSnapshot? { .init(value: value, range: range) }
    func setSelectedRange(_ range: NSRange) -> AXError? { self.range = range; return .success }
    func target() throws -> WritingTarget { WritingTarget(snapshot: try #require(readSnapshot()), access: self) }

    // Both protocol shapes share the same mutation body; only the candidate authorizes an attempt callback.
    func replaceSelection(_ text: String) -> AXError? {
        guard let before = readSnapshot() else { return nil }
        attempts += 1
        value = partialValue ?? before.replacement(text)
        range = NSRange(location: before.range.location + text.utf16.count, length: 0)
        afterMutation?()
        return partialValue == nil ? .success : .cannotComplete
    }
    func replaceSelection(_ text: String, willAttempt: () throws -> Void) throws -> AXError? {
        try willAttempt()
        return replaceSelection(text)
    }
}

@MainActor
final class WritingDeliveryEnhancement: AIEnhancementService {
    var output = "new e\u{301} 🧪"
    var failure: Error?
    var gate: WritingDeliveryGate?
    private(set) var requests = 0
    private(set) var sawCancellationAfterGate = false
    override func performWritingAction(_ request: VoiceInkWritingActionRequest, using snapshot: AIEnhancementProviderSnapshot) async throws -> VoiceInkAIEnhancementResult {
        requests += 1
        await gate?.enter()
        sawCancellationAfterGate = Task.isCancelled
        if let failure { throw failure }
        return .init(text: output, duration: 0.125, modelName: "owned-writing-model", promptName: request.promptName,
                     requestSystemMessage: "owned system request", requestUserMessage: "owned user request")
    }
}

@MainActor
final class WritingDeliveryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var entered = false
    func enter() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async throws {
        for _ in 0..<2000 {
            if entered { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw WritingDeliveryFixtureError.gateTimeout
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private enum WritingDeliveryFixtureError: Error { case unusedRecognizer, gateTimeout }

@MainActor
private final class WritingDeliveryUnusedWhisper: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class WritingDeliveryRecognizer: TranscriptionSession {
    let text: String
    init(text: String) { self.text = text }
    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }
    func transcribe(audioURL: URL) async throws -> String { text }
    func cancel() {}
}
