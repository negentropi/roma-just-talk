import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetTextEditPreservesUnicodeOutsideSelection() async throws {
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        try await editor.selectOriginalPassage()

        let target = try WritingTarget.capture(requiresSelection: true)
        #expect(target.selectedText.utf16.elementsEqual(LiveWritingEditor.passage.utf16))
        let replacement = "Rewritten 台灣\nSecond line"
        try await target.replace(with: replacement)
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        try await editor.waitForValue(expected)
        #expect(editor.value?.utf16.elementsEqual(expected.utf16) == true)
        editor.record("textedit-replacement", expected: expected)
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetTextEditRefusesRangeTextAndFocusDrift() async throws {
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        try await editor.selectOriginalPassage()
        let rangeTarget = try WritingTarget.capture(requiresSelection: true)
        try await editor.select(NSRange(location: 0, length: 3))
        await expectLiveTargetChanged(rangeTarget)
        #expect(editor.value == LiveWritingEditor.original)
        editor.record("textedit-range-drift", expected: LiveWritingEditor.original)

        try await editor.selectOriginalPassage()
        let textTarget = try WritingTarget.capture(requiresSelection: true)
        try editor.replaceSelection("User's edit")
        let userEdited = LiveWritingEditor.prefix + "User's edit" + LiveWritingEditor.suffix
        try await editor.waitForValue(userEdited)
        await expectLiveTargetChanged(textTarget)
        #expect(editor.value == userEdited)
        editor.record("textedit-text-drift", expected: userEdited)

        try await editor.select(NSRange(location: 0, length: userEdited.utf16.count))
        try editor.replaceSelection(LiveWritingEditor.original)
        try await editor.waitForValue(LiveWritingEditor.original)
        try await editor.selectOriginalPassage()
        let focusTarget = try WritingTarget.capture(requiresSelection: true)
        let other = try await LiveWritingEditor.open(.textEdit)
        defer { other.close() }
        try await other.selectOriginalPassage()
        await expectLiveTargetChanged(focusTarget)
        #expect(editor.value == LiveWritingEditor.original)
        #expect(other.value == LiveWritingEditor.original)
        editor.record("textedit-focus-drift", expected: LiveWritingEditor.original)
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetSafariTextareaReplacesOnlySelection() async throws {
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        try await editor.selectOriginalPassage()

        let target = try WritingTarget.capture(requiresSelection: true)
        #expect(target.selectedText.utf16.elementsEqual(LiveWritingEditor.passage.utf16))
        let replacement = "Translated 日本語\nNext paragraph"
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        do { try await target.replace(with: replacement) }
        catch {
            editor.recordOperationFailure("safari-replacement-failure", expected: expected)
            throw error
        }
        try await editor.waitForValue(expected)
        #expect(editor.value?.utf16.elementsEqual(expected.utf16) == true)
        editor.record("safari-replacement", expected: expected)
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingActionPipelineUsesLocalCLIAndRetainsFailure() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require((environment["TEST_RUNNER_GITHUB_ACTIONS"] ?? environment["GITHUB_ACTIONS"]) == "true")
        try #require((environment["TEST_RUNNER_RUNNER_ENVIRONMENT"] ?? environment["RUNNER_ENVIRONMENT"]) == "github-hosted")
        #if LOCAL_BUILD
        let fixture = try LiveWritingPipelineFixture()
        defer { fixture.restore() }
        try await fixture.runCase(succeeds: true)
        try await fixture.runCase(succeeds: false)
        let verificationContext = ModelContext(fixture.container)
        let savedCount = try verificationContext.fetchCount(FetchDescriptor<Transcription>())
        #expect(savedCount == 2)
        #else
        throw LiveWritingPipelineFailure.localBuildRequired
        #endif
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingStartupContextRespectsOwnerAfterCancellation() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require((environment["TEST_RUNNER_GITHUB_ACTIONS"] ?? environment["GITHUB_ACTIONS"]) == "true")
        try #require((environment["TEST_RUNNER_RUNNER_ENVIRONMENT"] ?? environment["RUNNER_ENVIRONMENT"]) == "github-hosted")
        #if LOCAL_BUILD
        let fixture = try LiveWritingStartupContextFixture()
        defer { fixture.restore() }
        do {
            try await fixture.runCase(cancelWriting: true)
            try await fixture.runCase(cancelWriting: false)
            try fixture.saveEvidence(noSetupFailure: true)
        } catch {
            try? fixture.saveEvidence(noSetupFailure: false, error: String(describing: error))
            throw error
        }
        #else
        throw LiveWritingPipelineFailure.localBuildRequired
        #endif
    }

    @MainActor private func expectLiveTargetChanged(_ target: WritingTarget) async {
        do {
            try await target.replace(with: "MUST NOT BE INSERTED")
            Issue.record("A stale live editor accepted a writing replacement.")
        } catch {
            #expect(error as? WritingTarget.Failure == .targetChanged)
        }
    }
}

private enum LiveWritingPipelineFailure: Error {
    case localBuildRequired, unusedRecognizerRuntime
}

@MainActor
private final class LiveWritingPipelineFixture {
    let container: ModelContainer
    private let context: ModelContext
    private let directory: URL
    private let evidenceDirectory: URL
    private let provider = LiveWritingUnusedRecognizerProvider()
    private let savedDefaults: [String: Any]
    private let savedSoundEnabled: Bool
    private static let preferenceKeys = [
        VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.useClipboardContext,
        VoiceInkUserDefaultsKey.useScreenCaptureContext,
        VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout,
        VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey,
        VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey
    ]

    init() throws {
        let defaults = UserDefaults.standard
        let domain = try #require(Bundle.main.bundleIdentifier)
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        let environment = ProcessInfo.processInfo.environment
        let evidencePath = try #require(environment["RJT_LIVE_WRITING_TARGET_EVIDENCE"] ?? environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE"])
        evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "LiveWritingPipeline-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        context = container.mainContext
        context.autosaveEnabled = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Writing-Pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.preferenceKeys.compactMap { key in
            persisted[key].map { (key, $0) }
        })
        savedSoundEnabled = SoundManager.shared.isEnabled
        VoiceInkAIEnhancementProviderPreference.saveSelectedProvider(.localCLI)
        VoiceInkAIEnhancementPreference.saveIsEnabled(false)
        VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(false)
        VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(false)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        VoiceInkLocalCLIPreference.saveTimeoutSeconds(5)
        SoundManager.shared.isEnabled = false
    }

    func runCase(succeeds: Bool) async throws {
        let label = succeeds ? "success" : "failure"
        let receipts = directory.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let output = "Pipeline 台灣\nSecond line"
        let instruction = succeeds ? "Rewrite the selection as two concise lines." : "Rewrite this selection and retain my instruction if processing fails."
        let script = receipts.appendingPathComponent("synthetic-command.sh")
        let response = receipts.appendingPathComponent("synthetic-output.txt")
        try output.write(to: response, atomically: true, encoding: .utf8)
        let scriptBody = """
        umask 077
        /bin/cat > \(Self.shellQuote(receipts.appendingPathComponent("stdin.txt").path))
        printf '%s' "$VOICEINK_SYSTEM_PROMPT" > \(Self.shellQuote(receipts.appendingPathComponent("system.txt").path))
        printf '%s' "$VOICEINK_USER_PROMPT" > \(Self.shellQuote(receipts.appendingPathComponent("user.txt").path))
        printf '%s' "$VOICEINK_FULL_PROMPT" > \(Self.shellQuote(receipts.appendingPathComponent("full.txt").path))
        printf '%s' "$$" > \(Self.shellQuote(receipts.appendingPathComponent("pid.txt").path))
        \(succeeds ? "/bin/cat " + Self.shellQuote(response.path) : "printf '%s' 'Synthetic CLI failure 23' >&2; exit 23")
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        let command = "/bin/sh " + Self.shellQuote(script.path)
        VoiceInkLocalCLIPreference.saveCommandTemplate(command)
        let aiService = AIService()
        let enhancement = AIEnhancementService(aiService: aiService, modelContext: context)
        try #require(aiService.selectedProvider == .localCLI)
        try #require(enhancement.isConfigured)
        try #require(!enhancement.isEnhancementEnabled)
        let registry = TranscriptionServiceRegistry(
            modelProvider: provider, modelsDirectory: directory, modelContext: context,
            qwenRuntimeResult: .failure(LiveWritingPipelineFailure.unusedRecognizerRuntime)
        )
        let pipeline = TranscriptionPipeline(modelContext: context, serviceRegistry: registry, enhancementService: enhancement)
        let editor = try await LiveWritingEditor.open(.safari)
        defer {
            NotificationManager.shared.dismissNotification()
            editor.close()
        }
        try await editor.selectOriginalPassage()
        let writing = try WritingActionSession(kind: .rewriteSelection, provider: enhancement.writingActionProviderSnapshot())
        let request = try writing.request(transcript: instruction)
        let poison = "printf '%s' 'MUST NOT USE CHANGED CLI PREFERENCES'"
        aiService.updateLocalCLICommandTemplate(poison)
        try #require(aiService.localCLICommandTemplate == poison)
        let audio = receipts.appendingPathComponent("synthetic-recognizer-input.wav")
        let record = Transcription(text: "", duration: 1, audioFileURL: audio.absoluteString)
        context.insert(record)
        let recognizer = LiveWritingFixedTranscriptSession(text: instruction)
        var dismissals = 0
        var states: [VoiceInkRecordingState] = []
        await pipeline.run(
            transcription: record, audioURL: audio,
            model: TranscriptionModelRegistry.defaultMacOSFluidAudioModel,
            session: recognizer, writingSession: writing, spokenSnippets: [], latencyTraceToken: nil,
            onStateChange: { states.append($0) }, shouldCancel: { false },
            onCancel: { Issue.record("The fixed writing pipeline fixture unexpectedly canceled.") },
            onDismiss: { dismissals += 1 }
        )
        let expectedDocument = succeeds ? LiveWritingEditor.prefix + output + LiveWritingEditor.suffix : LiveWritingEditor.original
        do { try await editor.waitForValue(expectedDocument) }
        catch {
            editor.recordOperationFailure("pipeline-\(label)-delivery-failure", expected: expectedDocument)
            throw error
        }
        let exactDocument = editor.value?.utf16.elementsEqual(expectedDocument.utf16) == true
        #expect(exactDocument)
        #expect(recognizer.transcribeCalls == 1)
        #expect(dismissals == 1)
        #expect(states == [.enhancing])
        #expect(!enhancement.isEnhancementEnabled)
        let recordID = record.id
        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.id == recordID }
        ))
        let saved = try #require(fetched.first)
        #expect(saved !== record)
        #expect(saved.text == instruction)
        #expect(saved.transcriptionState == (succeeds ? .completed : .failed))
        #expect(saved.transcriptionModelName == TranscriptionModelRegistry.defaultMacOSFluidAudioModel.displayName)
        #expect(saved.promptName == "Edit selected text")
        #expect(saved.transcriptionDuration != nil)
        #expect(saved.duration == 1)
        #expect(saved.audioFileURL == audio.absoluteString)
        if succeeds {
            let exactEnhancedText = saved.enhancedText?.utf16.elementsEqual(output.utf16) == true
            #expect(exactEnhancedText)
            #expect(saved.aiEnhancementModelName == "local-cli")
            #expect(saved.enhancementDuration != nil)
            #expect(saved.aiRequestSystemMessage == request.systemMessage)
            #expect(saved.aiRequestUserMessage == request.userMessage)
        } else {
            #expect(saved.enhancedText == nil)
            #expect(saved.aiEnhancementModelName == nil)
            #expect(saved.enhancementDuration == nil)
        }
        let system = try String(contentsOf: receipts.appendingPathComponent("system.txt"), encoding: .utf8)
        let user = try String(contentsOf: receipts.appendingPathComponent("user.txt"), encoding: .utf8)
        let full = try String(contentsOf: receipts.appendingPathComponent("full.txt"), encoding: .utf8)
        let stdin = try String(contentsOf: receipts.appendingPathComponent("stdin.txt"), encoding: .utf8)
        let childPIDText = try String(contentsOf: receipts.appendingPathComponent("pid.txt"), encoding: .utf8)
        let childPID = try #require(Int32(childPIDText))
        #expect(system == request.systemMessage)
        #expect(user == request.userMessage)
        #expect(full == stdin)
        let containsInstructionAndSelection = full.contains(instruction) && full.contains(LiveWritingEditor.passage)
        #expect(containsInstructionAndSelection)
        #expect(childPID > 0 && childPID != ProcessInfo.processInfo.processIdentifier)
        editor.record("pipeline-\(label)-delivery", expected: expectedDocument)
        try saveEvidence(label, record: saved, childPID: childPID, system: system, user: user, full: full, document: editor.value)
    }

    private func saveEvidence(
        _ label: String, record: Transcription, childPID: pid_t,
        system: String, user: String, full: String, document: String?
    ) throws {
        let output = evidenceDirectory
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let receipt: [String: Any] = [
            "checkpoint": "writing-pipeline-\(label)", "recordID": record.id.uuidString,
            "scope": "Real pipeline, LocalCLIService child process and Safari delivery; fixed synthetic recognizer text and CLI output",
            "historyProof": "Fresh ModelContext reads saved finalization from retained in-memory store; no crash or relaunch durability claim",
            "audioProof": "Fixed transcript session bypasses microphone and audio decoding; audio URL is a synthetic fixture reference",
            "ordinaryEnhancementEnabled": false, "preferencesChangedAfterCapture": true,
            "childPID": childPID, "systemPrompt": system, "userPrompt": user, "stdin": full,
            "rawInstruction": record.text, "enhancedText": record.enhancedText as Any? ?? NSNull(),
            "status": record.transcriptionStatus as Any? ?? NSNull(), "promptName": record.promptName as Any? ?? NSNull(),
            "enhancementModel": record.aiEnhancementModelName as Any? ?? NSNull(),
            "observedDocument": document as Any? ?? NSNull()
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(directory.lastPathComponent)-\(label).json"))
    }

    func restore() {
        SoundManager.shared.isEnabled = savedSoundEnabled
        for key in Self.preferenceKeys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove owned writing pipeline fixture: \(error)") }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
private final class LiveWritingUnusedRecognizerProvider: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class LiveWritingFixedTranscriptSession: TranscriptionSession {
    let text: String
    private(set) var transcribeCalls = 0
    init(text: String) { self.text = text }
    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }
    func transcribe(audioURL: URL) async throws -> String {
        transcribeCalls += 1
        return text
    }
    func cancel() { Issue.record("The fixed transcript session unexpectedly canceled.") }
}

@MainActor
private final class LiveWritingStartupContextFixture {
    private let environmentFixture: LiveWritingPipelineFixture
    private let directory: URL
    private let savedConfigurations: [PowerModeConfig]
    private let savedActiveConfiguration: PowerModeConfig?
    private let savedDefaults: [String: Any]
    private var cases: [String: [String: Any]] = [:]
    private static let extraPreferenceKeys = [
        "activeConfigurationId", "powerModePersistConfig",
        VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceIDKey,
        VoiceInkRecordingFeedbackPreference.systemMuteModeKey,
        VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey,
        VoiceInkRecordingFeedbackPreference.isPauseMediaEnabledKey
    ]

    init() throws {
        let defaults = UserDefaults.standard
        try #require(defaults.object(forKey: "powerModeActiveSession.v1") == nil)
        let domain = try #require(Bundle.main.bundleIdentifier)
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Startup-Context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        directory = path
        environmentFixture = try LiveWritingPipelineFixture()
        savedConfigurations = PowerModeManager.shared.configurations
        savedActiveConfiguration = PowerModeManager.shared.activeConfiguration
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.extraPreferenceKeys.compactMap { key in
            persisted[key].map { (key, $0) }
        })
        PowerModeManager.shared.configurations = []
        PowerModeManager.shared.activeConfiguration = nil
        defaults.set(false, forKey: "powerModePersistConfig")
        VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(.never)
        defaults.set(false, forKey: VoiceInkRecordingFeedbackPreference.isPauseMediaEnabledKey)
        VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(true)
        VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(true)
        VoiceInkLocalCLIPreference.saveCommandTemplate("/usr/bin/false")
    }

    func runCase(cancelWriting: Bool) async throws {
        let label = cancelWriting ? "canceled-writing" : "active-ordinary"
        let gate = LiveWritingStartupLoadGate()
        let whisper = LiveWritingGatedWhisperManager(modelsDirectory: directory, gate: gate)
        let model = ImportedWhisperModel(fileBaseName: "RJT-Context-\(UUID().uuidString)")
        whisper.availableModels = [.init(name: model.name, url: directory.appendingPathComponent(model.name + ".bin"))]
        let fluid = FluidAudioModelManager()
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
        models.currentTranscriptionModel = model
        let enhancement = LiveWritingContextSpy(aiService: AIService(), modelContext: environmentFixture.container.mainContext)
        let engine = VoiceInkEngine(
            modelContext: environmentFixture.container.mainContext,
            whisperModelManager: whisper, transcriptionModelManager: models,
            qwenRuntimeResult: .failure(LiveWritingPipelineFailure.unusedRecognizerRuntime),
            enhancementService: enhancement
        )
        engine.recordPermissionRequestForTesting = { true }
        enhancement.isOwnerRecording = { [weak engine] in engine?.recordingState == .recording }
        let editor = cancelWriting ? try await LiveWritingEditor.open(.textEdit) : nil
        defer { editor?.close() }
        let writing: WritingActionSession?
        if let editor {
            try await editor.selectOriginalPassage()
            writing = try WritingActionSession(kind: .rewriteSelection, provider: enhancement.writingActionProviderSnapshot())
        } else {
            writing = nil
        }
        let starting = Task { await engine.toggleRecord(writingSession: writing) }
        var startupTask: Task<Void, Never>?
        var audioURL: URL?
        do {
            let gateEntered = await gate.waitUntilEntered()
            try #require(gateEntered, "The actual recording startup did not reach the Whisper load override.")
            await starting.value
            try #require(engine.recordingState == .recording)
            try #require(whisper.loadCalls == 1)
            let task = try #require(engine.recordingStartupTask)
            startupTask = task
            audioURL = try #require(engine.recordedFile)
            let audioExists = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
            try #require(audioExists, "The actual recorder did not create its owned audio file.")
            if cancelWriting { await engine.cancelRecording() }
            let detachedAfterCancellation = cancelWriting && engine.recordingStartupTask == nil
            gate.release()
            await task.value
            let wasRecordingAtCompletion = engine.recordingState == .recording
            if !cancelWriting { await engine.cancelRecording() }
            let ownerEnded = engine.recordingState == .idle && engine.writingActionKind == nil
            #expect(ownerEnded)
            if cancelWriting {
                #expect(enhancement.clipboardReads == 0, "Canceled writing startup must not capture clipboard context")
                #expect(enhancement.screenReads == 0, "Canceled writing startup must not capture screen context")
            } else {
                #expect(wasRecordingAtCompletion)
                #expect(enhancement.clipboardReads == 1, "Active ordinary startup must capture clipboard context")
                #expect(enhancement.screenReads == 1, "Active ordinary startup must capture screen context")
                let onlyActiveOwnerReads = enhancement.captureStates.allSatisfy { $0 }
                #expect(onlyActiveOwnerReads)
            }
            cases[label] = [
                "gateEntered": gateEntered, "taskCompleted": true, "ownerEnded": ownerEnded,
                "recordingCanceled": ownerEnded, "clipboardReads": enhancement.clipboardReads,
                "screenReads": enhancement.screenReads, "modelLoadCalls": whisper.loadCalls,
                "actualAudioFileCreated": audioExists,
                "taskDetachedOnCancellation": detachedAfterCancellation,
                "wasRecordingAtTaskCompletion": wasRecordingAtCompletion,
                "captureStatesWereRecording": enhancement.captureStates
            ]
        } catch {
            let taskToDrain = startupTask ?? engine.recordingStartupTask
            let fileToRemove = audioURL ?? engine.recordedFile
            gate.release()
            await engine.cancelRecording()
            await starting.value
            await taskToDrain?.value
            if let fileToRemove, FileManager.default.fileExists(atPath: fileToRemove.path) {
                do { try FileManager.default.removeItem(at: fileToRemove) }
                catch { Issue.record("Could not remove owned failed startup audio: \(error)") }
            }
            throw error
        }
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.removeItem(at: audioURL)
        }
    }

    func saveEvidence(noSetupFailure: Bool, error: String? = nil) throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["RJT_LIVE_WRITING_TARGET_EVIDENCE"] ?? environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE"])
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let receipt: [String: Any] = [
            "checkpoint": "startup-context-ownership", "test": "liveWritingStartupContextRespectsOwnerAfterCancellation",
            "version": 1, "cases": cases, "noSetupFailure": noSetupFailure,
            "error": error as Any? ?? NSNull(), "bundleIdentifier": Bundle.main.bundleIdentifier as Any? ?? NSNull(),
            "executablePath": Bundle.main.executableURL?.path as Any? ?? NSNull(),
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "scope": "Actual engine and recorder with gated Whisper loader and context-call spies; no model weights, transcription or OS context reads"
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("startup-context-ownership.json"))
    }

    func restore() {
        PowerModeManager.shared.configurations = savedConfigurations
        PowerModeManager.shared.activeConfiguration = savedActiveConfiguration
        for key in Self.extraPreferenceKeys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        environmentFixture.restore()
        NotificationManager.shared.dismissNotification()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove owned startup context fixture: \(error)") }
    }
}

@MainActor
private final class LiveWritingContextSpy: AIEnhancementService {
    private(set) var clipboardReads = 0
    private(set) var screenReads = 0
    private(set) var captureStates: [Bool] = []
    var isOwnerRecording: (() -> Bool)?
    override func captureClipboardContext() {
        clipboardReads += 1
        captureStates.append(isOwnerRecording?() == true)
    }
    override func captureScreenContext() async {
        screenReads += 1
        captureStates.append(isOwnerRecording?() == true)
    }
}

@MainActor
private final class LiveWritingGatedWhisperManager: WhisperModelManager {
    private let gate: LiveWritingStartupLoadGate
    private(set) var loadCalls = 0
    init(modelsDirectory: URL, gate: LiveWritingStartupLoadGate) {
        self.gate = gate
        super.init(modelsDirectory: modelsDirectory)
    }
    override func loadModel(_ model: VoiceInkWhisperLocalModelFile) async throws {
        loadCalls += 1
        await gate.enter()
    }
}

@MainActor
private final class LiveWritingStartupLoadGate {
    private var load: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Bool, Never>?
    private var entered = false
    private var released = false
    func enter() async {
        entered = true
        observer?.resume(returning: true)
        observer = nil
        guard !released else { return }
        await withCheckedContinuation { load = $0 }
    }
    func waitUntilEntered() async -> Bool {
        if entered { return true }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(20))
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
        load?.resume()
        load = nil
    }
}

private enum LiveWritingFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): message }
    }
}

@MainActor
private final class LiveWritingEditor {
    enum Kind {
        case textEdit, safari
        var bundleIdentifier: String {
            self == .textEdit ? "com.apple.TextEdit" : "com.apple.Safari"
        }
    }

    nonisolated static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["RJT_LIVE_WRITING_TARGET_CHECKS"] == "1"
            || environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS"] == "1"
    }

    static let prefix = "Before 👩🏽‍💻 "
    static let passage = "target e\u{301}"
    static let suffix = " after 🧑‍🚀.\n"
    static var original: String { prefix + passage + suffix }

    let token: String
    let kind: Kind
    let directory: URL
    let resource: URL
    let application: NSRunningApplication
    let appElement: AXUIElement
    let window: AXUIElement
    let editor: AXUIElement
    let previousApplication: NSRunningApplication?
    let previousWindows: [AXUIElement]

    private init(
        token: String, kind: Kind, directory: URL, resource: URL,
        application: NSRunningApplication, window: AXUIElement, editor: AXUIElement,
        previousApplication: NSRunningApplication?, previousWindows: [AXUIElement]
    ) {
        self.token = token
        self.kind = kind
        self.directory = directory
        self.resource = resource
        self.application = application
        appElement = AXUIElementCreateApplication(application.processIdentifier)
        self.window = window
        self.editor = editor
        self.previousApplication = previousApplication
        self.previousWindows = previousWindows
    }

    var value: String? {
        _ = AXUIElementSetMessagingTimeout(editor, 0.1)
        return Self.string(kAXValueAttribute, from: editor)
    }
    var selectedRange: NSRange? {
        _ = AXUIElementSetMessagingTimeout(editor, 0.1)
        return Self.range(from: editor).map { NSRange(location: $0.location, length: $0.length) }
    }

    static func open(_ kind: Kind) async throws -> LiveWritingEditor {
        guard AXIsProcessTrusted() else {
            throw LiveWritingFailure.failed("Live writing checks require Accessibility for the exact test-host signature.")
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleIdentifier) else {
            throw LiveWritingFailure.failed("Missing live editor \(kind.bundleIdentifier).")
        }
        var windowsBeforeLaunch: [pid_t: [AXUIElement]] = [:]
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier) {
            guard let windows = windows(in: AXUIElementCreateApplication(application.processIdentifier)) else {
                throw LiveWritingFailure.failed("Cannot inventory existing editor windows before the live check.")
            }
            windowsBeforeLaunch[application.processIdentifier] = windows
        }
        let previous = NSWorkspace.shared.frontmostApplication
        let token = "RJT-Writing-Live-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resource = directory.appendingPathComponent(token + (kind == .textEdit ? ".txt" : ".html"))
        let content: String
        if kind == .textEdit {
            content = original
        } else {
            let escaped = original.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            content = """
            <!doctype html><meta charset="utf-8"><title>\(token)</title>
            <label for="editor">\(token)</label>
            <textarea id="editor" aria-label="\(token)" autofocus
              style="display:block;width:800px;height:300px;font:20px monospace">\(escaped)</textarea>
            """
        }
        try content.write(to: resource, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let openStarted = ProcessInfo.processInfo.systemUptime
        let application = try await NSWorkspace.shared.open(
            [resource], withApplicationAt: applicationURL, configuration: configuration
        )
        let openCompleted = ProcessInfo.processInfo.systemUptime
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let priorWindows = windowsBeforeLaunch[application.processIdentifier] ?? []
        let activationRequested = ProcessInfo.processInfo.systemUptime
        let activationAccepted = application.activate(options: [.activateAllWindows])
        var startupStages: [[String: Any]] = [
            ["stage": "workspace-open-completed", "sinceOpenMilliseconds": (openCompleted - openStarted) * 1_000],
            ["stage": "application-activation-requested", "sinceOpenMilliseconds": (activationRequested - openStarted) * 1_000,
             "accepted": activationAccepted]
        ]
        var frontmostObserved = false
        var documentWindow: AXUIElement?
        var startupPhase = "owned-document-readiness"
        var surface: (AXUIElement, AXUIElement)?
        do {
            let documentDeadline = ProcessInfo.processInfo.systemUptime + 20
            _ = AXUIElementSetMessagingTimeout(appElement, 0.1)
            repeat {
                guard !application.isTerminated else {
                    throw LiveWritingFailure.failed("The owned editor application terminated during startup.")
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                    if !frontmostObserved {
                        frontmostObserved = true
                        startupStages.append([
                            "stage": "frontmost-identity-observed",
                            "sinceOpenMilliseconds": (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000
                        ])
                    }
                    for window in windows(in: appElement) ?? [] {
                        guard ProcessInfo.processInfo.systemUptime < documentDeadline else { break }
                        guard hasDocumentMarker(window, token: token, deadline: documentDeadline) else { continue }
                        if kind == .textEdit, priorWindows.contains(where: { CFEqual($0, window) }) { continue }
                        documentWindow = window
                        startupStages.append([
                            "stage": "owned-document-observed",
                            "sinceOpenMilliseconds": (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000,
                            "ownershipMarkerMatched": true,
                            "titleContainsToken": string(kAXTitleAttribute, from: window)?.contains(token) == true,
                            "documentIsOwnedFile": scopedURL(kAXDocumentAttribute, from: window, resource: resource) == resource.absoluteString,
                            "existedBeforeOpen": priorWindows.contains { CFEqual($0, window) }
                        ])
                        break
                    }
                }
                if documentWindow != nil { break }
                try await Task.sleep(for: .milliseconds(30))
            } while ProcessInfo.processInfo.systemUptime < documentDeadline
            guard documentWindow != nil else {
                throw LiveWritingFailure.failed("The owned \(kind.bundleIdentifier) document did not become frontmost and accessible.")
            }
            _ = AXUIElementSetMessagingTimeout(appElement, 0)
            startupPhase = "exact-textarea-readiness"
            try await wait("The owned \(kind.bundleIdentifier) editor did not become accessible.") {
                guard let windows = windows(in: appElement) else { return false }
                for window in windows where identifies(window, token: token) {
                    if kind == .textEdit, priorWindows.contains(where: { CFEqual($0, window) }) { continue }
                    if let editor = descendants(of: window).first(where: {
                        string(kAXRoleAttribute, from: $0) == kAXTextAreaRole as String
                            && string(kAXValueAttribute, from: $0)?.utf16.elementsEqual(original.utf16) == true
                    }) {
                        surface = (window, editor)
                        return true
                    }
                }
                return false
            }
            startupStages.append([
                "stage": "exact-textarea-observed",
                "sinceOpenMilliseconds": (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000,
                "sameDocumentWindow": surface.map { pair in documentWindow.map { CFEqual($0, pair.0) } == true } == true
            ])
        } catch {
            recordStartup(
                token: token, kind: kind, application: application, stages: startupStages,
                finalStage: startupPhase, failure: String(describing: error)
            )
            recordSetupFailure(
                kind: kind, token: token, resource: resource, application: application,
                appElement: appElement, previousWindows: priorWindows
            )
            if kind == .safari {
                await recordSafariReadiness(
                    token: token, resource: resource, application: application,
                    previousWindows: priorWindows, openStarted: openStarted
                )
            }
            Issue.record("Could not claim the live editor; preserved fixture \(directory.path).")
            if let previous, !previous.isTerminated { previous.activate() }
            throw error
        }
        guard let (window, editor) = surface else {
            throw LiveWritingFailure.failed("The owned editor disappeared before capture.")
        }
        let fixture = LiveWritingEditor(
            token: token, kind: kind, directory: directory, resource: resource,
            application: application, window: window, editor: editor,
            previousApplication: previous, previousWindows: priorWindows
        )
        do {
            try await fixture.focus()
            startupStages.append([
                "stage": "owned-editor-focused",
                "sinceOpenMilliseconds": (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000
            ])
            recordStartup(
                token: token, kind: kind, application: application, stages: startupStages,
                finalStage: "ready", failure: nil
            )
            return fixture
        } catch {
            recordStartup(
                token: token, kind: kind, application: application, stages: startupStages,
                finalStage: "owned-editor-focus", failure: String(describing: error)
            )
            fixture.close()
            throw error
        }
    }

    func selectOriginalPassage() async throws {
        try await select(NSRange(location: Self.prefix.utf16.count, length: Self.passage.utf16.count))
    }

    func select(_ range: NSRange) async throws {
        try await focus()
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw LiveWritingFailure.failed("The owned editor did not accept its test selection.")
        }
        let expected = range
        try await Self.wait("The owned editor did not confirm its test selection.") {
            guard let actual = Self.range(from: self.editor) else { return false }
            return actual.location == expected.location && actual.length == expected.length
        }
    }

    func replaceSelection(_ text: String) throws {
        guard AXUIElementSetAttributeValue(editor, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            throw LiveWritingFailure.failed("The owned editor did not accept the fixture's selected-text mutation.")
        }
    }

    func waitForValue(_ expected: String) async throws {
        try await Self.wait("The owned editor did not display the expected text.") {
            self.value?.utf16.elementsEqual(expected.utf16) == true
        }
    }

    private func focus() async throws {
        guard Self.elements(kAXWindowsAttribute, from: appElement).contains(where: { CFEqual($0, window) }),
              Self.identifies(window, token: token) else {
            throw LiveWritingFailure.failed("The fixture no longer owns its editor window.")
        }
        application.activate(options: [.activateAllWindows])
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await Self.wait("The owned editor did not receive focus.") {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == self.application.processIdentifier,
                  let focused = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide()) else { return false }
            return CFEqual(focused, self.editor)
        }
    }

    func close() {
        guard Self.elements(kAXWindowsAttribute, from: appElement).contains(where: { CFEqual($0, window) }),
              Self.identifies(window, token: token) else {
            Issue.record("Live writing cleanup lost ownership; preserved fixture \(directory.path).")
            return
        }
        application.activate(options: [.activateAllWindows])
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard Self.poll(seconds: 2, {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == self.application.processIdentifier,
                  let focused = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide()) else { return false }
            return CFEqual(focused, self.editor)
        }) else {
            Issue.record("Live writing cleanup could not focus its owned editor; preserved \(directory.path).")
            return
        }
        if kind == .textEdit {
            guard let expected = value else {
                Issue.record("Live writing cleanup could not read its owned document.")
                return
            }
            Self.key(kVK_ANSI_S, pid: application.processIdentifier, flags: .maskCommand)
            guard Self.poll(seconds: 3, {
                (try? String(contentsOf: self.resource, encoding: .utf8))?.utf16.elementsEqual(expected.utf16) == true
            }) else {
                Issue.record("Live writing cleanup could not save its owned document; preserved \(directory.path).")
                return
            }
            guard let close = Self.element(kAXCloseButtonAttribute, from: window),
                  AXUIElementPerformAction(close, kAXPressAction as CFString) == .success else {
                Issue.record("Live writing cleanup could not close its owned document.")
                return
            }
        } else {
            Self.key(kVK_ANSI_W, pid: application.processIdentifier, flags: .maskCommand)
        }
        let closed = Self.poll(seconds: 3) {
            guard let windows = Self.windows(in: self.appElement) else {
                return self.application.isTerminated && self.previousWindows.isEmpty
            }
            guard self.previousWindows.allSatisfy({ previous in
                windows.contains { CFEqual($0, previous) }
            }) else { return false }
            return !windows.contains { candidate in
                Self.identifies(candidate, token: self.token)
            }
        }
        record("cleanup", expected: closed ? "owned surface closed" : "owned surface still open")
        guard closed else {
            Issue.record("Live writing cleanup did not prove its owned surface closed; preserved \(directory.path).")
            return
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Live writing cleanup could not remove its owned fixture: \(error)") }
        if let previousApplication, !previousApplication.isTerminated { previousApplication.activate() }
    }

    func record(_ name: String, expected: String) {
        guard let output = Self.evidenceDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let receipt: [String: Any] = [
                "checkpoint": name, "token": token, "bundleIdentifier": kind.bundleIdentifier,
                "processIdentifier": application.processIdentifier, "expected": expected,
                "observed": value ?? "<unavailable>", "date": ISO8601DateFormatter().string(from: Date())
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-\(name).json"))
        } catch { Issue.record("Could not write live writing evidence: \(error)") }
    }

    func recordOperationFailure(_ name: String, expected: String) {
        guard let output = Self.evidenceDirectory else { return }
        for element in [appElement, window, editor] { _ = AXUIElementSetMessagingTimeout(element, 0.1) }
        let windows = Self.windows(in: appElement)
        let windowPresent = windows?.contains { CFEqual($0, window) } == true
        let editorWindow = Self.element(kAXWindowAttribute, from: editor)
        let hasFixtureLabel = [kAXTitleAttribute, kAXDescriptionAttribute].contains {
            Self.string($0, from: editor)?.contains(token) == true
        }
        let owned = windowPresent && editorWindow.map { CFEqual($0, window) } == true && hasFixtureLabel
        let observedAt = ProcessInfo.processInfo.systemUptime
        let observedDate = ISO8601DateFormatter().string(from: Date())
        let observed = owned ? value : nil
        let range = owned ? selectedRange : nil
        let selected = owned ? Self.string(kAXSelectedTextAttribute, from: editor) : nil
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.1)
        let focused = Self.element(kAXFocusedUIElementAttribute, from: system)
        let frontmostIsExpected = NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        let title = Self.scopedString(kAXTitleAttribute, from: window, token: token)
        let document = Self.scopedURL(kAXDocumentAttribute, from: window, resource: resource)
        let screenshot: String
        if owned, !previousWindows.contains(where: { CFEqual($0, window) }) {
            screenshot = Self.captureOwnedWindow(
                window, application: application, token: token, resource: resource, output: output, name: name
            )
        } else {
            screenshot = "not captured; no new owned fixture window"
        }
        let receipt: [String: Any] = [
            "checkpoint": name, "token": token, "bundleIdentifier": kind.bundleIdentifier,
            "processIdentifier": application.processIdentifier, "ownedEditor": owned,
            "windowStillPresent": windowPresent,
            "expected": expected, "observed": observed as Any? ?? NSNull(),
            "observedUTF16Count": observed?.utf16.count ?? -1, "expectedUTF16Count": expected.utf16.count,
            "exactUTF16Equal": observed?.utf16.elementsEqual(expected.utf16) == true,
            "canonicalEqual": observed == expected,
            "originalStillPresent": observed?.utf16.elementsEqual(Self.original.utf16) == true,
            "prefixPreserved": observed?.utf16.starts(with: Self.prefix.utf16) == true,
            "suffixPreserved": observed.map { Array($0.utf16.suffix(Self.suffix.utf16.count)) == Array(Self.suffix.utf16) } == true,
            "selectedText": selected as Any? ?? NSNull(),
            "selectionLocationUTF16": range?.location ?? -1, "selectionLengthUTF16": range?.length ?? -1,
            "focusedEditor": focused.map { CFEqual($0, editor) } == true,
            "frontmostIsExpectedApplication": frontmostIsExpected, "title": title, "document": document,
            "screenshot": screenshot, "systemUptime": observedAt, "date": observedDate
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-\(name).json"))
        } catch { Issue.record("Could not write live editor failure observation: \(error)") }
    }

    private static var evidenceDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        return (environment["RJT_LIVE_WRITING_TARGET_EVIDENCE"]
            ?? environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE"])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func recordStartup(
        token: String, kind: Kind, application: NSRunningApplication, stages: [[String: Any]],
        finalStage: String, failure: String?
    ) {
        guard let output = evidenceDirectory else { return }
        let receipt: [String: Any] = [
            "checkpoint": "fixture-startup", "token": token, "bundleIdentifier": kind.bundleIdentifier,
            "processIdentifier": application.processIdentifier,
            "documentBudgetMilliseconds": 20_000, "textareaBudgetMilliseconds": 5_000,
            "finalStage": finalStage, "failure": failure as Any? ?? NSNull(), "stages": stages
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-fixture-startup.json"))
        } catch { Issue.record("Could not write live editor startup evidence: \(error)") }
    }

    private static func hasDocumentMarker(_ window: AXUIElement, token: String, deadline: TimeInterval) -> Bool {
        func read(_ name: String, from node: AXUIElement) -> String? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            _ = AXUIElementSetMessagingTimeout(node, Float(min(0.1, remaining)))
            let value = string(name, from: node)
            return ProcessInfo.processInfo.systemUptime < deadline ? value : nil
        }
        if read(kAXTitleAttribute, from: window)?.contains(token) == true
            || read(kAXDocumentAttribute, from: window)?.contains(token) == true { return true }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return false }
        let tree = diagnosticTree(window, deadline: Date(timeIntervalSinceNow: min(2, remaining)))
        for node in tree.nodes {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            if read(kAXDescriptionAttribute, from: node)?.contains(token) == true
                || read(kAXTitleAttribute, from: node)?.contains(token) == true { return true }
        }
        return false
    }

    private static func recordSetupFailure(
        kind: Kind, token: String, resource: URL, application: NSRunningApplication,
        appElement: AXUIElement, previousWindows: [AXUIElement]
    ) {
        guard let output = evidenceDirectory else { return }
        _ = AXUIElementSetMessagingTimeout(appElement, 0.2)
        let currentWindows = windows(in: appElement)
        let focused = element(kAXFocusedUIElementAttribute, from: appElement)
        let deadline = Date().addingTimeInterval(5)
        let focusedMetadata = focused.map { diagnosticNode($0, token: token, resource: resource, deadline: deadline) } ?? [:]
        let focusedWindow = focused.flatMap { element(kAXWindowAttribute, from: $0) }
        var ownedWindows: [AXUIElement] = []
        var summaries: [[String: Any]] = []
        for window in currentWindows ?? [] {
            guard Date() < deadline else { break }
            let tree = diagnosticTree(window, deadline: min(deadline, Date().addingTimeInterval(2)))
            let owned = tree.nodes.contains { node in
                guard Date() < deadline else { return false }
                return [kAXTitleAttribute, kAXDescriptionAttribute, kAXDocumentAttribute].contains {
                    string($0, from: node)?.contains(token) == true
                }
            }
            if owned { ownedWindows.append(window) }
            var summary: [String: Any] = [
                "owned": owned,
                "existedBeforeLaunch": previousWindows.contains { CFEqual($0, window) },
                "title": scopedString(kAXTitleAttribute, from: window, token: token),
                "document": scopedURL(kAXDocumentAttribute, from: window, resource: resource),
                "visitedNodes": tree.nodes.count, "traversalTruncated": tree.truncated,
                "childrenAXErrors": tree.errors, "roleCounts": tree.roles
            ]
            if owned {
                var nodes: [[String: Any]] = []
                for (index, node) in tree.nodes.enumerated() {
                    guard Date() < deadline else { break }
                    var metadata = diagnosticNode(node, token: token, resource: resource, deadline: deadline)
                    metadata["index"] = index
                    metadata["focused"] = focused.map { CFEqual($0, node) } ?? false
                    nodes.append(metadata)
                }
                summary["nodes"] = nodes
                summary["metadataTruncated"] = nodes.count != tree.nodes.count
            }
            summaries.append(summary)
        }
        let focusedOwned = focusedWindow.map { candidate in
            ownedWindows.contains { CFEqual($0, candidate) }
        } ?? false
        let screenshotWindow = ownedWindows.first { window in
            !previousWindows.contains { CFEqual($0, window) }
        }
        let screenshot: String
        if ownedWindows.count == 1, let screenshotWindow, Date() < deadline {
            screenshot = captureOwnedWindow(
                screenshotWindow, application: application, token: token, resource: resource, output: output
            )
        } else {
            screenshot = "not captured; no unique new token-owned window within AX deadline"
        }
        let receipt: [String: Any] = [
            "checkpoint": "setup-failure", "token": token, "bundleIdentifier": kind.bundleIdentifier,
            "processIdentifier": application.processIdentifier, "resource": resource.absoluteString,
            "windowsReadable": currentWindows != nil, "windows": summaries,
            "windowsTruncated": summaries.count != currentWindows?.count,
            "focusedElementInOwnedWindow": focusedOwned,
            "focusedElement": focusedMetadata,
            "screenshot": screenshot, "date": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-setup-failure.json"))
        } catch { Issue.record("Could not write live editor setup diagnostics: \(error)") }
    }

    private static func recordSafariReadiness(
        token: String, resource: URL, application: NSRunningApplication,
        previousWindows: [AXUIElement], openStarted: TimeInterval
    ) async {
        guard let output = evidenceDirectory else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 20
        let offsets: [TimeInterval] = [0, 0.5, 1, 2, 4, 7, 10, 14, 19]
        var samples: [[String: Any]] = []
        var firstOwnedField: TimeInterval?
        for offset in offsets {
            let delay = min(started + offset, deadline) - ProcessInfo.processInfo.systemUptime
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { break }
            }
            let sampledAt = ProcessInfo.processInfo.systemUptime
            guard sampledAt < deadline else { break }
            var sample = safariReadinessSample(
                token: token, resource: resource, application: application,
                previousWindows: previousWindows, deadline: min(deadline, sampledAt + 1)
            )
            let completedAt = ProcessInfo.processInfo.systemUptime
            sample["surveyMilliseconds"] = (sampledAt - started) * 1_000
            sample["sinceOpenMilliseconds"] = (sampledAt - openStarted) * 1_000
            sample["sampleCompletedSinceOpenMilliseconds"] = (completedAt - openStarted) * 1_000
            sample["sampleDurationMilliseconds"] = (completedAt - sampledAt) * 1_000
            if firstOwnedField == nil, sample["ownedExactTextAreaObserved"] as? Bool == true {
                firstOwnedField = completedAt - openStarted
            }
            samples.append(sample)
            if application.isTerminated { break }
        }
        let receipt: [String: Any] = [
            "checkpoint": "safari-readiness-after-setup-failure", "token": token,
            "processIdentifier": application.processIdentifier,
            "scope": "Read-only survey; original discovery failure remains a failure",
            "budgetMilliseconds": 20_000, "sampleBudgetMilliseconds": 1_000,
            "startedMillisecondsAfterOpen": (started - openStarted) * 1_000,
            "durationMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
            "scheduledSamples": offsets.count, "skippedSamples": offsets.count - samples.count,
            "firstOwnedExactTextAreaObservedMillisecondsAfterOpen": firstOwnedField.map { $0 * 1_000 } as Any? ?? NSNull(),
            "interpretation": "A negative or truncated sample does not prove that an owned textarea is absent",
            "activationPerformed": false, "accessibilityEnablementWritten": false,
            "samples": samples
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-safari-readiness.json"))
        } catch { Issue.record("Could not write Safari readiness evidence: \(error)") }
    }

    private static func safariReadinessSample(
        token: String, resource: URL, application: NSRunningApplication,
        previousWindows: [AXUIElement], deadline: TimeInterval
    ) -> [String: Any] {
        guard !application.isTerminated else {
            return ["applicationTerminated": true, "ownedExactTextAreaObserved": false]
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(app, 0.1)
        func read(_ name: String, from node: AXUIElement) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            _ = AXUIElementSetMessagingTimeout(node, Float(min(0.1, remaining)))
            return attribute(name, from: node)
        }
        var rawWindows: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        let currentWindows = rawWindows as? [AXUIElement]
        let focused = ProcessInfo.processInfo.systemUptime < deadline
            ? element(kAXFocusedUIElementAttribute, from: app) : nil
        if let focused { _ = AXUIElementSetMessagingTimeout(focused, 0.1) }
        let focusedRole = focused.flatMap { read(kAXRoleAttribute, from: $0) as? String }
        let focusedSubrole = focused.flatMap { read(kAXSubroleAttribute, from: $0) as? String }
        var summaries: [[String: Any]] = []
        var ownedExactFieldObserved = false
        for window in currentWindows ?? [] {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            _ = AXUIElementSetMessagingTimeout(window, 0.1)
            let title = read(kAXTitleAttribute, from: window) as? String
            let document = safariURLContext(read(kAXDocumentAttribute, from: window), resource: resource)
            let documentOwned = document["ownedFixture"] as? Bool == true
            let titleOwned = title?.contains(token) == true
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            let tree = diagnosticTree(window, deadline: Date(timeIntervalSinceNow: min(0.5, remaining)))
            var owned = titleOwned || documentOwned
            var exactOriginalField = false
            var textFieldContainsToken = false
            var textFieldContexts: [[String: Any]] = []
            var textAreas: [AXUIElement] = []
            var labels: Set<String> = []
            var inspected = 0
            for node in tree.nodes {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                inspected += 1
                let role = read(kAXRoleAttribute, from: node) as? String
                let nodeTitle = read(kAXTitleAttribute, from: node) as? String
                let description = read(kAXDescriptionAttribute, from: node) as? String
                let tokenLabel = nodeTitle?.contains(token) == true || description?.contains(token) == true
                owned = owned || tokenLabel
                for text in [nodeTitle, description].compactMap({ $0 }) {
                    if let label = safariSetupLabel(text) { labels.insert(label) }
                }
                if role == kAXStaticTextRole as String,
                   let text = read(kAXValueAttribute, from: node) as? String,
                   let label = safariSetupLabel(text) { labels.insert(label) }
                if role == kAXTextAreaRole as String {
                    textAreas.append(node)
                } else if role == kAXTextFieldRole as String {
                    let rawValue = read(kAXValueAttribute, from: node)
                    textFieldContainsToken = textFieldContainsToken || (rawValue as? String)?.contains(token) == true
                    textFieldContexts.append(safariURLContext(rawValue, resource: resource))
                }
            }
            var inspectedValues = 0
            if owned {
                for textArea in textAreas {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                    inspectedValues += 1
                    exactOriginalField = exactOriginalField
                        || (read(kAXValueAttribute, from: textArea) as? String)?.utf16.elementsEqual(original.utf16) == true
                }
            }
            ownedExactFieldObserved = ownedExactFieldObserved || (owned && exactOriginalField)
            summaries.append([
                "titleContainsToken": titleOwned, "documentIsOwnedFile": documentOwned,
                "documentContext": document, "textFieldContexts": textFieldContexts,
                "titleClassification": titleOwned ? "owned-local-fixture" : title.flatMap(safariSetupLabel) ?? "unrecognized-redacted",
                "tokenWindowPresent": owned, "existedBeforeOpen": previousWindows.contains { CFEqual($0, window) },
                "roleCounts": tree.roles, "childrenAXErrors": tree.errors,
                "webAreaPresent": tree.roles["AXWebArea", default: 0] > 0,
                "textAreaPresent": tree.roles[kAXTextAreaRole as String, default: 0] > 0,
                "exactOriginalFieldPresent": exactOriginalField, "textFieldContainsToken": textFieldContainsToken,
                "knownSetupLabelIdentifiers": labels.sorted(), "visitedNodes": tree.nodes.count,
                "traversalTruncated": tree.truncated,
                "metadataTruncated": inspected != tree.nodes.count || (owned && inspectedValues != textAreas.count)
            ])
        }
        return [
            "applicationFinishedLaunching": application.isFinishedLaunching,
            "applicationTerminated": application.isTerminated,
            "applicationFrontmost": NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
            "windowsAXError": windowsResult.rawValue, "windowsReadable": currentWindows != nil,
            "windows": summaries, "windowsTruncated": summaries.count != currentWindows?.count,
            "focusedRole": focusedRole ?? "<unavailable>", "focusedSubrole": focusedSubrole ?? "<unavailable>",
            "ownedExactTextAreaObserved": ownedExactFieldObserved
        ]
    }

    private static func safariURLContext(_ raw: CFTypeRef?, resource: URL) -> [String: Any] {
        guard let raw else { return ["state": "unavailable", "ownedFixture": false] }
        if let text = raw as? String, text.isEmpty { return ["state": "empty", "ownedFixture": false] }
        let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
        guard let url, let scheme = url.scheme else { return ["state": "text-redacted", "ownedFixture": false] }
        let owned = url.isFileURL && url.standardizedFileURL == resource.standardizedFileURL
        let knownBlank = url.absoluteString == "about:blank"
        return [
            "state": owned ? "owned-local-fixture" : knownBlank ? "known-blank" : "unrelated-url-redacted",
            "ownedFixture": owned, "hostEmpty": url.host?.isEmpty != false,
            "scheme": ["file", "about", "safari", "favorites", "http", "https"].contains(scheme) ? scheme : "other"
        ]
    }

    private static func safariSetupLabel(_ text: String) -> String? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "safari": "safari-title"
        case "start page": "start-page"
        case "address and search", "search or enter website name": "address-search-control"
        case "welcome to safari": "welcome-to-safari"
        case "get started": "get-started-control"
        case "start browsing": "start-browsing-control"
        case "continue": "continue-control"
        case "not now": "not-now-control"
        case "make safari your default browser", "use safari as your default web browser",
             "set safari as your default browser", "safari is not your default web browser": "default-browser-prompt"
        case "use safari": "use-safari-control"
        case "don't change": "dont-change-control"
        case "cancel": "cancel-control"
        case "open": "open-control"
        case "done": "done-control"
        default: nil
        }
    }

    private static func diagnosticNode(_ node: AXUIElement, token: String, resource: URL, deadline: Date) -> [String: Any] {
        _ = AXUIElementSetMessagingTimeout(node, 0.1)
        func read(_ name: String) -> CFTypeRef? {
            Date() < deadline ? attribute(name, from: node) : nil
        }
        let title = read(kAXTitleAttribute) as? String
        let description = read(kAXDescriptionAttribute) as? String
        var metadata: [String: Any] = [
            "role": read(kAXRoleAttribute) as? String ?? "<unavailable>",
            "subrole": read(kAXSubroleAttribute) as? String ?? "<unavailable>",
            "title": title.flatMap { $0.contains(token) ? $0 : nil } ?? "<unrelated text redacted>",
            "description": description.flatMap { $0.contains(token) ? $0 : nil } ?? "<unrelated text redacted>",
            "url": Date() < deadline ? scopedURL(kAXURLAttribute, from: node, resource: resource) : "<AX deadline reached>"
        ]
        guard Date() < deadline,
              title?.contains(token) == true || description?.contains(token) == true else { return metadata }
        let value = read(kAXValueAttribute) as? String
        var settable = DarwinBoolean(false)
        guard Date() < deadline else { return metadata }
        let writableResult = AXUIElementIsAttributeSettable(node, kAXSelectedTextAttribute as CFString, &settable)
        metadata["fixtureValue"] = value ?? "<unavailable>"
        metadata["expectedValue"] = original
        metadata["valueUTF16Count"] = value?.utf16.count ?? -1
        metadata["expectedUTF16Count"] = original.utf16.count
        metadata["prefixUTF16Count"] = prefix.utf16.count
        metadata["passageUTF16Count"] = passage.utf16.count
        metadata["suffixUTF16Count"] = suffix.utf16.count
        metadata["exactUTF16Equal"] = value?.utf16.elementsEqual(original.utf16) ?? false
        metadata["canonicalEqual"] = value == original
        metadata["selectedRangeReadable"] = Date() < deadline && range(from: node) != nil
        metadata["selectedTextWritable"] = writableResult == .success && settable.boolValue
        metadata["selectedTextWritableAXError"] = writableResult.rawValue
        return metadata
    }

    private static func diagnosticTree(
        _ root: AXUIElement, deadline: Date
    ) -> (nodes: [AXUIElement], truncated: Bool, errors: [String: Int], roles: [String: Int]) {
        var queue = [root]
        var index = 0
        var errors: [String: Int] = [:]
        var roles: [String: Int] = [:]
        while index < queue.count, queue.count < 512, Date() < deadline {
            let candidate = queue[index]
            index += 1
            _ = AXUIElementSetMessagingTimeout(candidate, Float(max(0.001, min(0.1, deadline.timeIntervalSinceNow))))
            roles[string(kAXRoleAttribute, from: candidate) ?? "<unavailable>", default: 0] += 1
            guard Date() < deadline else { break }
            var rawChildren: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(candidate, kAXChildrenAttribute as CFString, &rawChildren)
            if result != .success { errors[String(result.rawValue), default: 0] += 1 }
            for child in rawChildren as? [AXUIElement] ?? []
                where !queue.contains(where: { CFEqual($0, child) }) {
                if queue.count == 512 { break }
                queue.append(child)
            }
        }
        return (Array(queue.prefix(index)), index < queue.count, errors, roles)
    }

    private static func scopedString(_ name: String, from node: AXUIElement, token: String) -> String {
        guard let value = string(name, from: node) else { return "<unavailable>" }
        return value.contains(token) ? value : "<unrelated text redacted>"
    }

    private static func scopedURL(_ name: String, from node: AXUIElement, resource: URL) -> String {
        let raw = attribute(name, from: node)
        let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
        guard let url else { return "<unavailable>" }
        return url.isFileURL && url.standardizedFileURL == resource.standardizedFileURL
            ? url.absoluteString : "<unrelated URL redacted>"
    }

    private static func captureOwnedWindow(
        _ window: AXUIElement, application: NSRunningApplication, token: String, resource: URL, output: URL,
        name: String = "setup-failure"
    ) -> String {
        guard CGPreflightScreenCaptureAccess() else { return "not captured; Screen Recording unavailable" }
        guard string(kAXTitleAttribute, from: window)?.contains(token) == true
                || scopedURL(kAXDocumentAttribute, from: window, resource: resource) == resource.absoluteString else {
            return "not captured; active document ownership unproven"
        }
        guard
              let position = attribute(kAXPositionAttribute, from: window),
              let size = attribute(kAXSizeAttribute, from: window),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return "not captured; owned window bounds unavailable"
        }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              let inventory = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return "not captured; window inventory unavailable" }
        let matches = inventory.filter {
            guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application.processIdentifier,
                  let rawBounds = $0[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return false }
            return abs(bounds.minX - origin.x) < 1 && abs(bounds.minY - origin.y) < 1
                && abs(bounds.width - dimensions.width) < 1 && abs(bounds.height - dimensions.height) < 1
        }
        guard matches.count == 1, let number = matches[0][kCGWindowNumber as String] as? NSNumber else {
            return "not captured; no unique owned window number"
        }
        let image = output.appendingPathComponent("\(token)-\(name).png")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", number.stringValue, "-t", "png", image.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            guard poll(seconds: 2, { !process.isRunning }) else {
                process.terminate()
                return "capture timed out"
            }
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: image.path)
                ? image.lastPathComponent : "capture failed (\(process.terminationStatus))"
        } catch { return "capture failed (\(error))" }
    }

    private static func wait(_ failure: String, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(30))
        } while Date() < deadline
        throw LiveWritingFailure.failed(failure)
    }

    private static func poll(seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        } while Date() < deadline
        return predicate()
    }

    private static func identifies(_ window: AXUIElement, token: String) -> Bool {
        string(kAXTitleAttribute, from: window)?.contains(token) == true
            || string(kAXDocumentAttribute, from: window)?.contains(token) == true
            || descendants(of: window).contains {
                string(kAXDescriptionAttribute, from: $0)?.contains(token) == true
                    || string(kAXTitleAttribute, from: $0)?.contains(token) == true
            }
    }

    private static func descendants(of root: AXUIElement) -> [AXUIElement] {
        var queue = [root]
        var index = 0
        let deadline = Date().addingTimeInterval(2)
        while index < queue.count, queue.count < 512, Date() < deadline {
            let candidate = queue[index]
            index += 1
            for child in elements(kAXChildrenAttribute, from: candidate)
                where !queue.contains(where: { CFEqual($0, child) }) {
                queue.append(child)
            }
        }
        return queue
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private static func elements(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        attribute(name, from: element) as? [AXUIElement] ?? []
    }

    private static func windows(in application: AXUIElement) -> [AXUIElement]? {
        attribute(kAXWindowsAttribute, from: application) as? [AXUIElement]
    }

    private static func element(_ name: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func range(from element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func key(_ code: Int, pid: pid_t, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }
}
