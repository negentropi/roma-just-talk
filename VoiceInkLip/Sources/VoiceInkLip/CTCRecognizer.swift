import CLipInference
import Foundation

public enum LipInferenceError: Error, LocalizedError, Equatable, Sendable {
    case invalidInput(String)
    case invalidOutput(String)
    case runtime(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .invalidOutput(let message), .runtime(let message):
            return message
        }
    }
}

public struct CTCRecognizer: Sendable {
    // Serial native work prevents overlapping recognizers from multiplying ORT thread pools.
    private static let queue = DispatchQueue(label: "VoiceInkLip.inference", qos: .userInitiated)

    public init() {}

    public func recognize(
        modelURL: URL,
        frames: [Float],
        frameCount: Int,
        tokens: [String]
    ) async throws -> String {
        try Task.checkCancellation()
        guard modelURL.isFileURL, !modelURL.path.utf8.contains(0) else {
            throw LipInferenceError.invalidInput("The visual CTC model must be a local file.")
        }
        guard frameCount > 0, frameCount <= Int.max / (88 * 88),
              frames.count == frameCount * 88 * 88 else {
            throw LipInferenceError.invalidInput("Expected a mouth tensor with shape [1,T,88,88].")
        }
        guard tokens.count == CTCDecoder.vocabularySize else {
            throw LipInferenceError.invalidInput("The visual CTC vocabulary must contain 1049 tokens.")
        }
        let run = try NativeInferenceRun()
        return try await withTaskCancellationHandler {
            let output: NativeInferenceOutput = try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    continuation.resume(with: Result {
                        try run.recognize(modelURL: modelURL, frames: frames, frameCount: frameCount)
                    })
                }
            }
            // The continuation resumes only after native tensors, the session and its workers drain.
            try Task.checkCancellation()
            let text = try CTCDecoder.decode(
                logProbabilities: output.scores,
                shape: [1, output.timeSteps, output.vocabularySize],
                tokens: tokens
            )
            try Task.checkCancellation()
            return text
        } onCancel: {
            run.cancel()
        }
    }
}

public enum CTCDecoder {
    public static let vocabularySize = 1049

    public static func decode(logProbabilities: [Float], shape: [Int], tokens: [String]) throws -> String {
        guard shape.count == 3, shape[0] == 1, shape[1] > 0,
              shape[2] == vocabularySize, shape[1] <= Int.max / vocabularySize,
              logProbabilities.count == shape[1] * vocabularySize else {
            throw LipInferenceError.invalidOutput("Expected visual CTC scores with shape [1,T,1049].")
        }
        guard tokens.count == vocabularySize else {
            throw LipInferenceError.invalidInput("The visual CTC vocabulary must contain 1049 tokens.")
        }
        var pieces: [String] = []
        var previous: Int?
        for time in 0..<shape[1] {
            let start = time * vocabularySize
            var best = 0
            var bestScore = -Float.infinity
            for token in 0..<vocabularySize {
                let score = logProbabilities[start + token]
                guard score.isFinite else {
                    throw LipInferenceError.invalidOutput("The visual CTC scores contain a non-finite value.")
                }
                if score > bestScore {
                    best = token
                    bestScore = score
                }
            }
            // Preserve blank in the repeat history so A, blank, A decodes to AA.
            if best != previous, best != 0, best != 1048 {
                pieces.append(tokens[best])
            }
            previous = best
        }
        return pieces.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NativeInferenceOutput: Sendable {
    let scores: [Float]
    let timeSteps: Int
    let vocabularySize: Int
}

// The native handle remains owned until both the worker and cancellation handler release this object.
private final class NativeInferenceRun: @unchecked Sendable {
    private let handle: OpaquePointer

    init() throws {
        var error = [CChar](repeating: 0, count: 2048)
        guard let handle = LipInferenceCreate(&error, error.count) else {
            throw LipInferenceError.runtime(Self.message(from: error))
        }
        self.handle = handle
    }

    deinit {
        LipInferenceDestroy(handle)
    }

    func cancel() {
        LipInferenceCancel(handle)
    }

    func recognize(modelURL: URL, frames: [Float], frameCount: Int) throws -> NativeInferenceOutput {
        var error = [CChar](repeating: 0, count: 2048)
        var output = LipInferenceOutput()
        defer { LipInferenceFreeOutput(&output) }
        let outcome = modelURL.path.withCString { path in
            frames.withUnsafeBufferPointer { buffer in
                LipInferenceRecognize(
                    handle, path, buffer.baseAddress, frameCount, buffer.count,
                    &output, &error, error.count
                )
            }
        }
        if outcome == LIP_INFERENCE_CANCELLED || LipInferenceIsCancelled(handle) {
            throw CancellationError()
        }
        guard outcome == LIP_INFERENCE_OK, let values = output.values else {
            throw LipInferenceError.runtime(Self.message(from: error))
        }
        return NativeInferenceOutput(
            scores: Array(UnsafeBufferPointer(start: values, count: output.value_count)),
            timeSteps: output.time_steps,
            vocabularySize: output.vocabulary_size
        )
    }

    private static func message(from buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
