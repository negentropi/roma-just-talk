import Combine
import Foundation
import SwiftData
import VoiceInkCore

struct VoiceInkIOSHistoryCleanupPreview: Equatable {
    let transcriptCount: Int
    let audioFileCount: Int
    let audioByteCount: Int64
    let orphanFileCount: Int

    static let empty = VoiceInkIOSHistoryCleanupPreview(
        transcriptCount: 0,
        audioFileCount: 0,
        audioByteCount: 0,
        orphanFileCount: 0
    )
}

struct VoiceInkIOSHistoryCleanupResult: Equatable {
    let deletedTranscriptCount: Int
    let deletedAudioFileCount: Int
    let deletedOrphanFileCount: Int
    let errorCount: Int
}

@MainActor
final class IOSHistoryCleanupManager: ObservableObject {
    static let shared = IOSHistoryCleanupManager()
    static let lastScheduledRunKey = "iOSLastHistoryCleanupDate"

    @Published private(set) var isWorking = false
    @Published private(set) var preview: VoiceInkIOSHistoryCleanupPreview = .empty
    @Published private(set) var lastResult: VoiceInkIOSHistoryCleanupResult?

    private init() {}

    func refreshPreview(
        notes: [Transcription],
        activeNoteIDs: Set<UUID>,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        preview = makePreview(
            notes: notes,
            activeNoteIDs: activeNoteIDs,
            now: now,
            fileManager: fileManager
        )
    }

    func runManualCleanup(
        notes: [Transcription],
        modelContext: ModelContext,
        activeNoteIDs: Set<UUID>,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        guard !isWorking else { return }
        isWorking = true
        lastResult = runCleanup(
            notes: notes,
            modelContext: modelContext,
            activeNoteIDs: activeNoteIDs,
            now: now,
            fileManager: fileManager
        )
        isWorking = false
        preview = .empty
    }

    func runScheduledCleanupIfNeeded(
        notes: [Transcription],
        modelContext: ModelContext,
        activeNoteIDs: Set<UUID>,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let lastRunDate = defaults.object(forKey: Self.lastScheduledRunKey) as? Date
        guard VoiceInkHistoryCleanupSchedulePolicy.shouldRun(
            lastRunDate: lastRunDate,
            currentDate: now
        ) else { return }

        let transcriptConfiguration = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)
        let audioConfiguration = VoiceInkAudioCleanupPreference.current(from: defaults)
        guard transcriptConfiguration.isEnabled || audioConfiguration.isEnabled else { return }

        runManualCleanup(
            notes: notes,
            modelContext: modelContext,
            activeNoteIDs: activeNoteIDs,
            now: now,
            fileManager: fileManager
        )
        defaults.set(now, forKey: Self.lastScheduledRunKey)
    }

    private func makePreview(
        notes: [Transcription],
        activeNoteIDs: Set<UUID>,
        now: Date,
        fileManager: FileManager
    ) -> VoiceInkIOSHistoryCleanupPreview {
        let transcriptConfiguration = VoiceInkTranscriptionAutoCleanupPreference.current()
        let audioConfiguration = VoiceInkAudioCleanupPreference.current()
        let transcriptCandidates = transcriptConfiguration.isEnabled
            ? candidates(
                notes: notes,
                cutoffDate: transcriptConfiguration.cutoffDate(from: now),
                activeNoteIDs: activeNoteIDs
            )
            : []
        let transcriptCandidateIDs = Set(transcriptCandidates.map(\.id))
        let audioCandidates = audioConfiguration.isEnabled
            ? candidates(
                notes: notes,
                cutoffDate: audioConfiguration.cutoffDate(from: now),
                activeNoteIDs: activeNoteIDs
            ).filter { !transcriptCandidateIDs.contains($0.id) }
            : []

        var audioFileCount = 0
        var audioByteCount: Int64 = 0
        for note in audioCandidates {
            guard let url = note.existingAudioFileURL(fileManager: fileManager) else { continue }
            audioFileCount += 1
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber {
                audioByteCount += size.int64Value
            }
        }

        return VoiceInkIOSHistoryCleanupPreview(
            transcriptCount: transcriptCandidates.count,
            audioFileCount: audioFileCount,
            audioByteCount: audioByteCount,
            orphanFileCount: orphanFiles(notes: notes, fileManager: fileManager).count
        )
    }

    private func runCleanup(
        notes: [Transcription],
        modelContext: ModelContext,
        activeNoteIDs: Set<UUID>,
        now: Date,
        fileManager: FileManager
    ) -> VoiceInkIOSHistoryCleanupResult {
        let transcriptConfiguration = VoiceInkTranscriptionAutoCleanupPreference.current()
        let audioConfiguration = VoiceInkAudioCleanupPreference.current()
        let transcriptCandidates = transcriptConfiguration.isEnabled
            ? candidates(
                notes: notes,
                cutoffDate: transcriptConfiguration.cutoffDate(from: now),
                activeNoteIDs: activeNoteIDs
            )
            : []
        let transcriptCandidateIDs = Set(transcriptCandidates.map(\.id))
        let audioCandidates = audioConfiguration.isEnabled
            ? candidates(
                notes: notes,
                cutoffDate: audioConfiguration.cutoffDate(from: now),
                activeNoteIDs: activeNoteIDs
            ).filter { !transcriptCandidateIDs.contains($0.id) }
            : []

        var deletedAudioFileCount = 0
        var errorCount = 0
        for note in transcriptCandidates {
            do {
                if try note.deleteExistingAudioFile(relativeTo: nil, fileManager: fileManager) != nil {
                    deletedAudioFileCount += 1
                }
            } catch {
                errorCount += 1
            }
            modelContext.delete(note)
        }

        for note in audioCandidates {
            do {
                if try note.deleteExistingAudioFileAndClearReference(fileManager: fileManager) != nil {
                    deletedAudioFileCount += 1
                }
            } catch {
                errorCount += 1
            }
        }

        let orphanCandidates = orphanFiles(
            notes: notes.filter { !transcriptCandidateIDs.contains($0.id) },
            fileManager: fileManager
        )
        var deletedOrphanFileCount = 0
        for url in orphanCandidates {
            do {
                try fileManager.removeItem(at: url)
                deletedOrphanFileCount += 1
            } catch {
                errorCount += 1
            }
        }

        do {
            try modelContext.save()
        } catch {
            errorCount += 1
        }

        return VoiceInkIOSHistoryCleanupResult(
            deletedTranscriptCount: transcriptCandidates.count,
            deletedAudioFileCount: deletedAudioFileCount,
            deletedOrphanFileCount: deletedOrphanFileCount,
            errorCount: errorCount
        )
    }

    private func candidates(
        notes: [Transcription],
        cutoffDate: Date,
        activeNoteIDs: Set<UUID>
    ) -> [Transcription] {
        VoiceInkHistoryCleanupCandidatePolicy.eligibleRecords(
            notes,
            cutoffDate: cutoffDate,
            activeIDs: activeNoteIDs,
            id: \.id,
            timestamp: \.timestamp
        )
    }

    private func orphanFiles(
        notes: [Transcription],
        fileManager: FileManager
    ) -> [URL] {
        let directory = VoiceInkIOSStorageDirectories.recordingsDirectory
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let referencedFiles = Set(notes.compactMap {
            $0.resolvedAudioFileURL()?.standardizedFileURL
        })
        return VoiceInkOrphanAudioFilePolicy.orphanFiles(
            files: files,
            referencedFiles: referencedFiles
        )
    }
}
