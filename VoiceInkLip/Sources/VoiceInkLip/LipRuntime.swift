import CryptoKit
import Foundation
import OSLog

public enum LipRuntimeError: LocalizedError, Sendable {
    case alreadyRecognizing
    case noSpeech
    case unclearSpeech
    case missingVocabulary

    public var errorDescription: String? {
        switch self {
        case .alreadyRecognizing: return "Finish the current dictation before starting another."
        case .noSpeech: return "No lip speech was recognized. Face the camera and try again."
        case .unclearSpeech: return "The lip reading was unclear. Try a shorter phrase."
        case .missingVocabulary: return "The lip reading resources are damaged. Reinstall the app."
        }
    }
}

public actor LipRuntime {
    public static let modelDisplayName = "BRAVEn Lip Reading"

    private struct Recognition {
        let id = UUID()
        let task: Task<String, Error>
    }

    private let store: LipModelStore
    private var recognition: Recognition?
    private let logger = Logger(subsystem: "com.negentropi.RomaJustTalk", category: "LipRuntime")

    public init(directory: URL) {
        store = LipModelStore(directory: directory)
    }

    public func isInstalled() async -> Bool { await store.isInstalled() }

    public func installationBytes() async throws -> (download: Int64, installed: Int64, temporaryFreeSpace: Int64) {
        try await store.installationBytes()
    }

    public func install() async throws { _ = try await store.install() }

    public func cancelInstallation() async { await store.cancelInstallation() }

    public func transcribe(videoURL: URL) async throws -> String {
        try await transcribe {
            try await MouthVideoProcessor.process(videoURL: videoURL)
        }
    }

    public func transcribe(mouth: MouthVideoFrames) async throws -> String {
        try await transcribe { mouth }
    }

    private func transcribe(
        prepare: @escaping @Sendable () async throws -> MouthVideoFrames
    ) async throws -> String {
        guard recognition == nil else { throw LipRuntimeError.alreadyRecognizing }
        try Task.checkCancellation()
        let store = store
        let operation = Recognition(task: Task.detached(priority: .userInitiated) {
            let modelURL = try await store.modelURL()
            try Task.checkCancellation()
            let mouth = try await prepare()
            try Task.checkCancellation()
            let tokens = try Self.loadTokens()
            let text = try await CTCRecognizer().recognize(
                modelURL: modelURL, frames: mouth.values,
                frameCount: mouth.frameCount, tokens: tokens
            )
            guard !text.isEmpty else { throw LipRuntimeError.noSpeech }
            guard !text.contains("<unk>") else { throw LipRuntimeError.unclearSpeech }
            return text
        })
        recognition = operation
        logger.notice("recognition.start id=\(operation.id.uuidString, privacy: .public)")
        defer {
            if recognition?.id == operation.id { recognition = nil }
            logger.notice("recognition.drained id=\(operation.id.uuidString, privacy: .public)")
        }
        return try await withTaskCancellationHandler {
            let text = try await operation.task.value
            try Task.checkCancellation()
            return text
        } onCancel: {
            operation.task.cancel()
        }
    }

    private static func loadTokens() throws -> [String] {
        guard let tokensURL = Bundle.module.url(forResource: "tokens", withExtension: "json", subdirectory: "Resources"),
              let manifestURL = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Resources"),
              let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
              let expectedHash = manifest["tokens_sha256"] as? String else {
            throw LipRuntimeError.missingVocabulary
        }
        let data = try Data(contentsOf: tokensURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == expectedHash else { throw LipRuntimeError.missingVocabulary }
        return try JSONDecoder().decode([String].self, from: data)
    }
}
