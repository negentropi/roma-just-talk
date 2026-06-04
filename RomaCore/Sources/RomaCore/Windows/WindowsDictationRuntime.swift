import Foundation

public enum WindowsDictationTrigger: Equatable, Hashable, Sendable {
    case toggle(recordSeconds: TimeInterval)
    case hold(timeoutMilliseconds: UInt32)
}

public enum WindowsDictationRuntimeEvent: Equatable, Hashable, Sendable {
    case preRollBuffering
    case waitingForToggle(displayName: String)
    case toggleReceived
    case waitingForHoldKeyDown(displayName: String)
    case holdKeyDown
    case holdKeyUp
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
    case invalidClipboardRestoreDelay(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Windows dictation runtime is only available on Windows."
        case .invalidRecordDuration(let seconds):
            return "Windows toggle record duration must be finite and between \(RomaWindowsAgentConfiguration.minimumRecordSeconds) and \(RomaWindowsAgentConfiguration.maximumRecordSeconds) seconds; got \(seconds)."
        case .invalidHoldTimeoutMilliseconds(let milliseconds):
            return "Windows hold timeout must be positive; got \(milliseconds) milliseconds."
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
        let recorder = MiniaudioCaptureRecorder()
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

        do {
            try await recorder.startPreRollBuffering()
            onEvent(.preRollBuffering)

            switch request.trigger {
            case .toggle(let recordSeconds):
                let hotKey = WindowsHotKey.proofToggle
                onEvent(.waitingForToggle(displayName: hotKey.displayName))
                try WindowsRegisterHotKeyProof.waitForSingleTrigger(hotKey: hotKey)
                onEvent(.toggleReceived)

                return try await pipeline.runRecordingWindow(pipelineRequest) {
                    try await sleep(recordSeconds: recordSeconds)
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

                return try await pipeline.runRecordingWindow(pipelineRequest) {
                    _ = try await holdWindow.waitForKeyUp()
                    onEvent(.holdKeyUp)
                }
            }
        } catch {
            await recorder.stopCapture()
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

    private static func sleep(recordSeconds: TimeInterval) async throws {
        let nanoseconds = try RomaWindowsAgentConfiguration.recordDurationNanoseconds(
            fromSeconds: recordSeconds
        )
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

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
