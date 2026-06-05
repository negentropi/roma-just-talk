import Foundation

public enum WindowsDictationTrigger: Equatable, Hashable, Sendable {
    case toggle(recordSeconds: TimeInterval)
    case hold(timeoutMilliseconds: UInt32)

    public var recordingMode: String {
        switch self {
        case .toggle:
            return "toggle"
        case .hold:
            return "hold"
        }
    }

    public var recordingModeProofLine: String {
        "recording_mode=\(recordingMode)"
    }
}

public enum WindowsDictationRuntimeEvent: Equatable, Hashable, Sendable {
    case preRollBuffering
    case waitingForToggle(displayName: String)
    case toggleReceived
    case waitingForHoldKeyDown(displayName: String)
    case holdKeyDown
    case holdKeyUp

    public var proofOutputLine: String {
        switch self {
        case .preRollBuffering:
            return "pre_roll_buffering=true"
        case .waitingForToggle(let displayName):
            return "waiting_for=\(displayName)"
        case .toggleReceived:
            return "hotkey_received=true"
        case .waitingForHoldKeyDown(let displayName):
            return "waiting_for_key_down=\(displayName)"
        case .holdKeyDown:
            return "hold_key_down=true"
        case .holdKeyUp:
            return "hold_key_up=true"
        }
    }
}

public struct WindowsDictationRuntimeResultProofOptions: Sendable {
    public var wordReplacementCount: Int
    public var transcriptionClient: RomaTranscriptionClient?
    public var includesPasteTextSource: Bool

    public init(
        wordReplacementCount: Int,
        transcriptionClient: RomaTranscriptionClient? = nil,
        includesPasteTextSource: Bool = false
    ) {
        self.wordReplacementCount = wordReplacementCount
        self.transcriptionClient = transcriptionClient
        self.includesPasteTextSource = includesPasteTextSource
    }
}

public enum WindowsDictationRuntimeResultProof {
    public static func outputLines(
        for result: DictationPipelineResult,
        options: WindowsDictationRuntimeResultProofOptions
    ) -> [String] {
        let audio = result.session.recordedAudio
        var lines = [
            "wrote=\(audio.fileURL.path)",
            "duration_seconds=\(String(format: "%.3f", audio.durationSeconds ?? 0))",
            "included_pre_roll_seconds=\(audio.includedPreRollSeconds ?? 0)",
            "sample_rate=\(audio.format.sampleRate)",
            "channels=\(audio.format.channelCount)"
        ]

        if let client = options.transcriptionClient {
            lines.append("provider=\(client.name)")
            lines.append(contentsOf: client.details)
            lines.append("audio=\(audio.fileURL.path)")
            appendRawTranscriptionLines(to: &lines, result: result.transcription)
        } else {
            appendAgentTranscriptionLines(to: &lines, result: result.transcription)
        }

        lines.append("processed_transcript_length=\(result.processedText.count)")
        lines.append("processed_transcript_text=\(RomaCommandLineText.oneLine(result.processedText))")
        lines.append("word_replacements=\(options.wordReplacementCount)")
        lines.append("paste_sent=\(result.session.insertedText != nil)")
        if options.includesPasteTextSource {
            lines.append("paste_text_source=processed_transcript")
        }
        return lines
    }

    private static func appendAgentTranscriptionLines(
        to lines: inout [String],
        result: TranscriptionResult
    ) {
        if let language = result.language {
            lines.append("language=\(language)")
        }
        if let duration = result.durationSeconds {
            lines.append("transcription_duration_seconds=\(String(format: "%.3f", duration))")
        }
        lines.append("raw_transcript_length=\(result.text.count)")
    }

    private static func appendRawTranscriptionLines(
        to lines: inout [String],
        result: TranscriptionResult
    ) {
        if let language = result.language {
            lines.append("language=\(language)")
        }
        if let duration = result.durationSeconds {
            lines.append("duration_seconds=\(String(format: "%.3f", duration))")
        }
        lines.append("transcript_length=\(result.text.count)")
        lines.append("transcript_text=\(RomaCommandLineText.oneLine(result.text))")
    }
}

public struct WindowsDictationRuntimeRequest: Sendable {
    public var outputURL: URL
    public var model: TranscriptionModelDescriptor
    public var language: String?
    public var prompt: String?
    public var shouldPaste: Bool
    public var clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration
    public var textProcessing: DictationTextProcessingConfiguration
    public var trigger: WindowsDictationTrigger

    public init(
        outputURL: URL,
        model: TranscriptionModelDescriptor,
        language: String? = nil,
        prompt: String? = nil,
        shouldPaste: Bool = false,
        clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration = WindowsClipboardRestoreConfiguration(),
        textProcessing: DictationTextProcessingConfiguration = .standard,
        trigger: WindowsDictationTrigger
    ) {
        self.outputURL = outputURL
        self.model = model
        self.language = language
        self.prompt = prompt
        self.shouldPaste = shouldPaste
        self.clipboardRestoreConfiguration = clipboardRestoreConfiguration
        self.textProcessing = textProcessing
        self.trigger = trigger
    }
}

public enum WindowsDictationRuntimeError: Error, LocalizedError, Equatable {
    case unsupported
    case invalidRecordDuration(TimeInterval)
    case invalidHoldTimeoutMilliseconds(UInt32)
    case invalidMaxSessions(Int)
    case invalidClipboardRestoreDelay(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Windows dictation runtime is only available on Windows."
        case .invalidRecordDuration(let seconds):
            return "Windows toggle record duration must be finite and between \(RomaWindowsAgentConfiguration.minimumRecordSeconds) and \(RomaWindowsAgentConfiguration.maximumRecordSeconds) seconds; got \(seconds)."
        case .invalidHoldTimeoutMilliseconds(let milliseconds):
            return "Windows hold timeout must be positive; got \(milliseconds) milliseconds."
        case .invalidMaxSessions(let sessions):
            return "Windows listener max sessions must be non-negative; got \(sessions)."
        case .invalidClipboardRestoreDelay(let seconds):
            return "Windows clipboard restore delay must be finite and between 0 and \(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds) seconds; got \(seconds)."
        }
    }
}

public enum WindowsDictationRuntime {
    public static var isRuntimeAvailable: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    public static func run(
        _ request: WindowsDictationRuntimeRequest,
        transcriptionService: TranscriptionService,
        onEvent: @escaping @Sendable (WindowsDictationRuntimeEvent) -> Void = { _ in }
    ) async throws -> DictationPipelineResult {
        try validateRequest(request)

        #if os(Windows)
        let session = WindowsDictationRuntimeSession(
            transcriptionService: transcriptionService,
            onEvent: onEvent
        )

        do {
            try await session.startPreRollBuffering()
            return try await session.run(request, captureLifecycle: .stopAfterRun)
        } catch {
            await session.stopCapture()
            throw error
        }
        #else
        throw WindowsDictationRuntimeError.unsupported
        #endif
    }

    public static func runListener(
        _ request: WindowsDictationRuntimeRequest,
        maxSessions: Int?,
        outputURLForSession: @escaping (Int) -> URL,
        transcriptionService: TranscriptionService,
        onEvent: @escaping @Sendable (WindowsDictationRuntimeEvent) -> Void = { _ in },
        onSessionCompleted: @escaping (Int, DictationPipelineResult) -> Void = { _, _ in }
    ) async throws -> Int {
        try validateRequest(request)
        if let maxSessions, maxSessions < 0 {
            throw WindowsDictationRuntimeError.invalidMaxSessions(maxSessions)
        }
        if maxSessions == 0 {
            return 0
        }

        #if os(Windows)
        let session = WindowsDictationRuntimeSession(
            transcriptionService: transcriptionService,
            onEvent: onEvent
        )
        var completedSessions = 0

        do {
            try await session.startPreRollBuffering()
            while maxSessions.map({ completedSessions < $0 }) ?? true {
                var sessionRequest = request
                let sessionIndex = completedSessions + 1
                sessionRequest.outputURL = outputURLForSession(sessionIndex)
                let result = try await session.run(
                    sessionRequest,
                    captureLifecycle: .keepAliveAfterRun
                )
                completedSessions += 1
                onSessionCompleted(completedSessions, result)
            }
            await session.stopCapture()
            return completedSessions
        } catch {
            await session.stopCapture()
            throw error
        }
        #else
        throw WindowsDictationRuntimeError.unsupported
        #endif
    }

    public static func validateTrigger(_ trigger: WindowsDictationTrigger) throws {
        switch trigger {
        case .toggle(let recordSeconds):
            guard recordSeconds.isFinite,
                  recordSeconds >= RomaWindowsAgentConfiguration.minimumRecordSeconds,
                  recordSeconds <= RomaWindowsAgentConfiguration.maximumRecordSeconds else {
                throw WindowsDictationRuntimeError.invalidRecordDuration(recordSeconds)
            }
        case .hold(let timeoutMilliseconds):
            guard timeoutMilliseconds > 0 else {
                throw WindowsDictationRuntimeError.invalidHoldTimeoutMilliseconds(timeoutMilliseconds)
            }
        }
    }

    public static func validateRequest(_ request: WindowsDictationRuntimeRequest) throws {
        try validateTrigger(request.trigger)
        if request.shouldPaste {
            try validateClipboardRestoreConfiguration(request.clipboardRestoreConfiguration)
        }
    }

    public static func validateClipboardRestoreConfiguration(
        _ configuration: WindowsClipboardRestoreConfiguration
    ) throws {
        guard configuration.restoreClipboard else {
            return
        }
        let delaySeconds = configuration.restoreDelaySeconds
        guard WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(fromSeconds: delaySeconds) != nil else {
            throw WindowsDictationRuntimeError.invalidClipboardRestoreDelay(delaySeconds)
        }
    }

    fileprivate static func sleep(recordSeconds: TimeInterval) async throws {
        let nanoseconds = try RomaWindowsAgentConfiguration.recordDurationNanoseconds(
            fromSeconds: recordSeconds
        )
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

#if os(Windows)
private final class WindowsDictationRuntimeSession: @unchecked Sendable {
    private let recorder = MiniaudioCaptureRecorder()
    private let transcriptionService: any TranscriptionService
    private let onEvent: @Sendable (WindowsDictationRuntimeEvent) -> Void

    init(
        transcriptionService: TranscriptionService,
        onEvent: @escaping @Sendable (WindowsDictationRuntimeEvent) -> Void
    ) {
        self.transcriptionService = transcriptionService
        self.onEvent = onEvent
    }

    func startPreRollBuffering() async throws {
        try await recorder.startPreRollBuffering()
        onEvent(.preRollBuffering)
    }

    func run(
        _ request: WindowsDictationRuntimeRequest,
        captureLifecycle: DictationPipelineCaptureLifecycle
    ) async throws -> DictationPipelineResult {
        let pipeline = DictationPipeline(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textInsertion: request.shouldPaste
                ? WindowsClipboardTextInsertion(
                    restoreConfiguration: request.clipboardRestoreConfiguration
                )
                : nil
        )
        let pipelineRequest = DictationPipelineRequest(
            outputURL: request.outputURL,
            model: request.model,
            language: request.language,
            prompt: request.prompt,
            shouldInsertTranscription: request.shouldPaste,
            textProcessing: request.textProcessing
        )

        switch request.trigger {
        case .toggle(let recordSeconds):
            let hotKey = WindowsHotKey.proofToggle
            onEvent(.waitingForToggle(displayName: hotKey.displayName))
            try WindowsRegisterHotKeyProof.waitForSingleTrigger(hotKey: hotKey)
            onEvent(.toggleReceived)

            return try await pipeline.runRecordingWindow(
                pipelineRequest,
                captureLifecycle: captureLifecycle
            ) {
                try await WindowsDictationRuntime.sleep(recordSeconds: recordSeconds)
            }
        case .hold(let timeoutMilliseconds):
            let chord = WindowsLowLevelKeyboardHookChord.proofHold
            let holdWindow = WindowsHoldWindowSignal()
            onEvent(.waitingForHoldKeyDown(displayName: chord.displayName))
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try WindowsLowLevelKeyboardHookProof.waitForHoldWindow(
                        chord: chord,
                        timeoutMilliseconds: timeoutMilliseconds
                    ) {
                        holdWindow.signalKeyDown()
                    }
                    holdWindow.finish(.success(result))
                } catch {
                    holdWindow.finish(.failure(error))
                }
            }
            try await holdWindow.waitForKeyDown()
            onEvent(.holdKeyDown)

            return try await pipeline.runRecordingWindow(
                pipelineRequest,
                captureLifecycle: captureLifecycle
            ) {
                _ = try await holdWindow.waitForKeyUp()
                onEvent(.holdKeyUp)
            }
        }
    }

    func stopCapture() async {
        await recorder.stopCapture()
    }
}
#endif

private final class WindowsHoldWindowSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var didSignalKeyDown = false
    private var completion: Result<WindowsLowLevelKeyboardHookResult, Error>?
    private var keyDownContinuation: CheckedContinuation<Void, Error>?
    private var keyUpContinuation: CheckedContinuation<WindowsLowLevelKeyboardHookResult, Error>?

    func signalKeyDown() {
        let continuation: CheckedContinuation<Void, Error>?
        lock.lock()
        if didSignalKeyDown {
            continuation = nil
        } else {
            didSignalKeyDown = true
            continuation = keyDownContinuation
            keyDownContinuation = nil
        }
        lock.unlock()

        continuation?.resume()
    }

    func finish(_ result: Result<WindowsLowLevelKeyboardHookResult, Error>) {
        let keyDownContinuation: CheckedContinuation<Void, Error>?
        let keyDownError: Error?
        let keyUpContinuation: CheckedContinuation<WindowsLowLevelKeyboardHookResult, Error>?

        lock.lock()
        completion = result
        if didSignalKeyDown {
            keyDownContinuation = nil
            keyDownError = nil
        } else {
            keyDownContinuation = self.keyDownContinuation
            self.keyDownContinuation = nil
            keyDownError = Self.keyDownError(from: result)
        }
        keyUpContinuation = self.keyUpContinuation
        self.keyUpContinuation = nil
        lock.unlock()

        if let keyDownContinuation, let keyDownError {
            keyDownContinuation.resume(throwing: keyDownError)
        }
        if let keyUpContinuation {
            switch result {
            case .success(let hookResult):
                keyUpContinuation.resume(returning: hookResult)
            case .failure(let error):
                keyUpContinuation.resume(throwing: error)
            }
        }
    }

    func waitForKeyDown() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let shouldResume: Bool
            let resumeError: Error?

            lock.lock()
            if didSignalKeyDown {
                shouldResume = true
                resumeError = nil
            } else if let completion {
                shouldResume = true
                resumeError = Self.keyDownError(from: completion)
            } else {
                shouldResume = false
                resumeError = nil
                keyDownContinuation = continuation
            }
            lock.unlock()

            if shouldResume {
                if let resumeError {
                    continuation.resume(throwing: resumeError)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func waitForKeyUp() async throws -> WindowsLowLevelKeyboardHookResult {
        try await withCheckedThrowingContinuation { continuation in
            let completion: Result<WindowsLowLevelKeyboardHookResult, Error>?

            lock.lock()
            completion = self.completion
            if completion == nil {
                keyUpContinuation = continuation
            }
            lock.unlock()

            if let completion {
                switch completion {
                case .success(let hookResult):
                    continuation.resume(returning: hookResult)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func keyDownError(
        from result: Result<WindowsLowLevelKeyboardHookResult, Error>
    ) -> Error {
        switch result {
        case .success(let hookResult):
            return WindowsLowLevelKeyboardHookError.invalidResult(observedEvents: hookResult.observedEvents)
        case .failure(let error):
            return error
        }
    }
}
