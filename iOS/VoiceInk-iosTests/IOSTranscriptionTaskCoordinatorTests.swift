import Foundation
import XCTest
import VoiceInkCore
@testable import roma_just_talk

@MainActor
final class IOSTranscriptionTaskCoordinatorTests: XCTestCase {
    func testSuccessfulRunEndsBackgroundTimeAndCompletesKeyboardRequest() async {
        let background = BackgroundExecutionHarness()
        let keyboardRequestID = UUID()
        var keyboardCompletions: [(UUID, String)] = []
        var runOutcome: VoiceInkStoredAudioRetranscriptionOutcome?
        var persistCount = 0
        let note = Transcription(text: "", duration: 1, transcriptionStatus: .pending)
        let coordinator = IOSTranscriptionTaskCoordinator(
            backgroundExecution: background.execution,
            retranscribe: { note in
                note.text = "Completed text"
                note.transcriptionStatus = .completed
                return .succeeded("Completed text")
            },
            completeKeyboard: { keyboardCompletions.append(($0, $1)) },
            failKeyboard: { _, _ in XCTFail("Successful run must not fail keyboard delivery") }
        )

        XCTAssertTrue(coordinator.start(
            note: note,
            keyboardRequestID: keyboardRequestID,
            persist: { persistCount += 1 },
            completion: { runOutcome = $0 }
        ))
        let didFinish = await waitUntil { !coordinator.isActive(noteID: note.id) }

        XCTAssertTrue(didFinish)
        XCTAssertEqual(note.transcriptionStatus, .completed)
        XCTAssertEqual(keyboardCompletions.count, 1)
        XCTAssertEqual(keyboardCompletions.first?.0, keyboardRequestID)
        XCTAssertEqual(keyboardCompletions.first?.1, "Completed text")
        XCTAssertEqual(background.beginCount, 1)
        XCTAssertEqual(background.endCount, 1)
        XCTAssertEqual(persistCount, 2)
        XCTAssertEqual(runOutcome, .succeeded("Completed text"))
    }

    func testUserCancellationMarksRecordCanceledAndEndsBackgroundTime() {
        let background = BackgroundExecutionHarness()
        var keyboardFailure: String?
        var runOutcome: VoiceInkStoredAudioRetranscriptionOutcome?
        var persistCount = 0
        let note = Transcription(text: "", duration: 1, transcriptionStatus: .pending)
        let coordinator = IOSTranscriptionTaskCoordinator(
            backgroundExecution: background.execution,
            retranscribe: { _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .failed(reason: "Unexpected completion")
                } catch {
                    return .canceled
                }
            },
            completeKeyboard: { _, _ in XCTFail("Canceled run must not complete keyboard delivery") },
            failKeyboard: { _, message in keyboardFailure = message }
        )

        XCTAssertTrue(coordinator.start(
            note: note,
            keyboardRequestID: UUID(),
            persist: { persistCount += 1 },
            completion: { runOutcome = $0 }
        ))
        XCTAssertTrue(coordinator.cancel(noteID: note.id))

        XCTAssertEqual(note.transcriptionStatus, .canceled)
        XCTAssertEqual(note.text, VoiceInkTranscriptPresentation.canceledTranscriptionText)
        XCTAssertEqual(keyboardFailure, VoiceInkTranscriptPresentation.canceledTranscriptionText)
        XCTAssertFalse(coordinator.isActive(noteID: note.id))
        XCTAssertEqual(background.endCount, 1)
        XCTAssertEqual(persistCount, 2)
        XCTAssertEqual(runOutcome, .canceled)
    }

    func testBackgroundExpirationCreatesRetryableFailureAndEndsBackgroundTime() {
        let background = BackgroundExecutionHarness()
        var keyboardFailure: String?
        var runOutcome: VoiceInkStoredAudioRetranscriptionOutcome?
        let note = Transcription(text: "", duration: 1, transcriptionStatus: .pending)
        let coordinator = IOSTranscriptionTaskCoordinator(
            backgroundExecution: background.execution,
            retranscribe: { _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .failed(reason: "Unexpected completion")
                } catch {
                    return .canceled
                }
            },
            completeKeyboard: { _, _ in XCTFail("Expired run must not complete keyboard delivery") },
            failKeyboard: { _, message in keyboardFailure = message }
        )

        XCTAssertTrue(coordinator.start(
            note: note,
            keyboardRequestID: UUID(),
            persist: {},
            completion: { runOutcome = $0 }
        ))
        background.expire()

        XCTAssertEqual(note.transcriptionStatus, .failed)
        XCTAssertEqual(
            note.transcriptionError,
            VoiceInkTranscriptPresentation.backgroundProcessingExpiredError
        )
        XCTAssertEqual(
            keyboardFailure,
            VoiceInkTranscriptPresentation.backgroundProcessingExpiredError
        )
        XCTAssertFalse(coordinator.isActive(noteID: note.id))
        XCTAssertEqual(background.endCount, 1)
        XCTAssertEqual(
            runOutcome,
            .failed(reason: VoiceInkTranscriptPresentation.backgroundProcessingExpiredError)
        )
    }

    func testImmediateBackgroundExpirationDoesNotStartWorkAndBalancesReturnedToken() {
        var endCount = 0
        var didTranscribe = false
        let backgroundExecution = VoiceInkIOSBackgroundExecution(
            begin: { _, expirationHandler in
                expirationHandler()
                return VoiceInkIOSBackgroundExecution.Token(identifier: .invalid)
            },
            end: { _ in endCount += 1 }
        )
        let note = Transcription(text: "", duration: 1, transcriptionStatus: .pending)
        let coordinator = IOSTranscriptionTaskCoordinator(
            backgroundExecution: backgroundExecution,
            retranscribe: { _ in
                didTranscribe = true
                return .failed(reason: "Unexpected run")
            },
            completeKeyboard: { _, _ in },
            failKeyboard: { _, _ in }
        )

        XCTAssertFalse(coordinator.start(note: note, persist: {}))

        XCTAssertFalse(didTranscribe)
        XCTAssertEqual(note.transcriptionStatus, .failed)
        XCTAssertFalse(coordinator.isActive(noteID: note.id))
        XCTAssertEqual(endCount, 1)
    }

    func testRelaunchRecoveryTurnsOrphanedPendingRecordIntoRetryableFailure() {
        let background = BackgroundExecutionHarness()
        let note = Transcription(text: "", duration: 1, transcriptionStatus: .pending)
        var persistCount = 0
        let coordinator = IOSTranscriptionTaskCoordinator(
            backgroundExecution: background.execution,
            retranscribe: { _ in .failed(reason: "unused") },
            completeKeyboard: { _, _ in },
            failKeyboard: { _, _ in }
        )

        coordinator.recoverInterruptedTranscriptions(
            [note],
            persist: { persistCount += 1 }
        )

        XCTAssertEqual(note.transcriptionStatus, .failed)
        XCTAssertEqual(
            note.transcriptionError,
            VoiceInkTranscriptPresentation.interruptedProcessingError
        )
        XCTAssertEqual(persistCount, 1)
    }

    func testStoredAudioCancellationDoesNotOverwriteCallerTerminalState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileName = "recording.wav"
        try Data().write(to: directory.appendingPathComponent(fileName))
        let note = Transcription(
            text: "",
            duration: 1,
            audioFileURL: fileName,
            transcriptionStatus: .pending
        )

        let task = Task {
            try await note.retranscribeStoredAudio(relativeTo: directory) { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return Self.completedResult
            }
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Canceled stored-audio work must throw CancellationError")
        } catch is CancellationError {
            XCTAssertEqual(note.transcriptionStatus, .pending)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testPostProcessingCancellationIsNotConvertedIntoCompletedFallback() async {
        let gate = PostProcessingGate()
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            try await gate.waitUntilCanceled()
        }
        let configuration = Mode(
            name: "Cancellation test",
            transcriptionProvider: .groq,
            transcriptionModel: "whisper-large-v3",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "gemini-2.5-flash",
            promptTemplate: VoiceInkPostProcessingPromptTemplate(
                type: .custom,
                customPrompt: "Clean this"
            )
        ).runtimeConfiguration
        let task = Task {
            try await processor.transcribe(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                configuration: configuration,
                apiKeyProvider: { _ in "key" },
                transcriptionServiceProvider: { _ in StubAudioTranscriptionService() }
            )
        }

        let postProcessingStarted = await waitUntil { await gate.hasStarted }
        XCTAssertTrue(postProcessingStarted)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Post-processing cancellation must escape the processor")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testWhisperCancellationTokenCanBeSignaledAcrossExecutionContexts() {
        let token = VoiceInkWhisperCancellationToken()
        let userData = Unmanaged.passUnretained(token).toOpaque()

        XCTAssertFalse(token.isCanceled)
        XCTAssertFalse(voiceInkWhisperAbortCallback(userData))
        token.cancel()
        XCTAssertTrue(token.isCanceled)
        XCTAssertTrue(voiceInkWhisperAbortCallback(userData))
    }

    func testImportedAudioWAVHeaderDescribesPCM16MonoAudio() {
        let header = VoiceInkIOSAudioImportPreparer.wavHeader(audioByteCount: 32_000)

        XCTAssertEqual(header.count, 44)
        XCTAssertEqual(String(data: header[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: header[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: header[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 22, as: UInt16.self) }, 1)
        XCTAssertEqual(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self) }, 16_000)
        XCTAssertEqual(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 34, as: UInt16.self) }, 16)
        XCTAssertEqual(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self) }, 32_000)
    }

    private static let completedResult = VoiceInkTranscriptionRunResult(
        cleanedText: "Completed text",
        finalText: "Completed text",
        transcriptionModelName: "test-model",
        aiEnhancementModelName: nil,
        postProcessingError: nil
    )

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }
}

@MainActor
private final class BackgroundExecutionHarness {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var expirationHandler: VoiceInkIOSBackgroundExecution.ExpirationHandler?

    var execution: VoiceInkIOSBackgroundExecution {
        VoiceInkIOSBackgroundExecution(
            begin: { [weak self] _, expirationHandler in
                self?.beginCount += 1
                self?.expirationHandler = expirationHandler
                return VoiceInkIOSBackgroundExecution.Token(identifier: .invalid)
            },
            end: { [weak self] _ in
                self?.endCount += 1
            }
        )
    }

    func expire() {
        expirationHandler?()
    }
}

private actor PostProcessingGate {
    private(set) var hasStarted = false

    func waitUntilCanceled() async throws -> String {
        hasStarted = true
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return "Unexpected completion"
    }
}

private struct StubAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        "raw text"
    }
}
