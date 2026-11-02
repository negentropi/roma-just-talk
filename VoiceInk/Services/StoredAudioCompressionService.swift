import Foundation
import SwiftData
import OSLog
import VoiceInkCore

/// Every producer of stored audio (dictation, file import, re-transcription) posts
/// `.transcriptionCreated` after its last use of the WAV, so that is when it turns into Opus.
/// WAVs saved before Opus storage are converted once at launch.
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

    /// Recordings saved before Opus storage still hold WAVs. Rows created before this launch
    /// are not in flight, so convert them one at a time; rerunning skips rows already converted.
    @discardableResult
    func compressExistingRecordings(in modelContext: ModelContext, createdBefore launchDate: Date) async -> Int {
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.timestamp < launchDate && $0.audioFileURL != nil }
        )
        let candidates: [Transcription]
        do {
            candidates = try modelContext.fetch(descriptor).filter {
                $0.resolvedAudioFileURL().map(VoiceInkStoredAudioCodec.isWAV) ?? false
            }
        } catch {
            logger.error("Skipping existing WAV conversion; fetch failed: \(String(describing: error), privacy: .public)")
            return 0
        }
        guard !candidates.isEmpty else { return 0 }

        var converted = 0
        var failed = 0
        for transcription in candidates {
            do {
                if try await VoiceInkStoredAudioCompression.compressStoredWAV(
                    of: transcription,
                    isLive: { !$0.isDeleted && $0.modelContext != nil },
                    save: { try modelContext.save() }
                ) != nil {
                    converted += 1
                }
            } catch {
                failed += 1
                logger.error("Keeping WAV; Opus conversion failed: \(String(describing: error), privacy: .public)")
            }
        }
        logger.notice("Converted existing WAV recordings to Opus: converted=\(converted, privacy: .public) failed=\(failed, privacy: .public) candidates=\(candidates.count, privacy: .public)")
        return converted
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
