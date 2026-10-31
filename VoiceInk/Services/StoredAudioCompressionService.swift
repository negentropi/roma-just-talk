import Foundation
import SwiftData
import OSLog
import VoiceInkCore

/// Every producer of stored audio (dictation, file import, re-transcription) posts
/// `.transcriptionCreated` after its last use of the WAV, so that is when it turns into Opus.
@MainActor
final class StoredAudioCompressionService {
    static let shared = StoredAudioCompressionService()

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "StoredAudioCompression")
    private var observer: NSObjectProtocol?

    private init() {}

    func startMonitoring() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .transcriptionCreated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let transcription = notification.object as? Transcription else { return }
            MainActor.assumeIsolated {
                _ = self?.compress(transcription)
            }
        }
    }

    @discardableResult
    func compress(_ transcription: Transcription) -> Task<URL?, Never> {
        Task { @MainActor in
            do {
                return try await VoiceInkStoredAudioCompression.compressStoredWAV(
                    of: transcription,
                    isLive: { !$0.isDeleted && $0.modelContext != nil },
                    save: { try transcription.modelContext?.save() }
                )
            } catch {
                logger.error("Keeping WAV; Opus compression failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }
}
