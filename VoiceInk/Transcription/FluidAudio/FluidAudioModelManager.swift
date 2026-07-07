import Foundation
import FluidAudio
import AppKit
import os
import VoiceInkCore

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published private var downloadStatuses: [String: VoiceInkFluidAudioDownloadStatus] = [:]
    private var activeDownloadIDs: [String: UUID] = [:]
    private var lastLoggedDownloadPercents: [String: Int] = [:]
    private var lastLoggedDownloadMessages: [String: String] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "FluidAudioModelManager")

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        AsrModelVersion(
            VoiceInkTranscriptionModelCatalog.fluidAudioModelVersion(forModelName: modelName)
        )
    }

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        VoiceInkTranscriptionModelCatalog
            .fluidAudioLanguageHintCode(from: languageCode, forModelName: modelName)
            .flatMap(Language.init(rawValue:))
    }

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        let version = FluidAudioModelManager.asrVersion(for: modelName)
        return AsrModels.modelsExist(at: cacheDirectory(for: version), version: version)
    }

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        downloadStatuses[model.name] != nil
    }

    func downloadStatus(for model: FluidAudioModel) -> VoiceInkFluidAudioDownloadStatus? {
        downloadStatuses[model.name]
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloaded(model) {
            logger.notice("FluidAudio download skipped; model already downloaded: \(model.name, privacy: .public)")
            return
        }

        if isFluidAudioModelDownloading(model) {
            logger.notice("FluidAudio download skipped; download already active: \(model.name, privacy: .public)")
            return
        }

        let modelName = model.name
        let downloadID = UUID()
        logger.notice("FluidAudio download starting: \(modelName, privacy: .public)")
        activeDownloadIDs[modelName] = downloadID
        let initialStatus = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.0,
            phase: .preparingDownload
        )
        downloadStatuses[modelName] = initialStatus
        logDownloadProgressIfNeeded(initialStatus, for: modelName)
        defer {
            clearDownloadStatus(for: modelName, downloadID: downloadID)
            onModelsChanged?()
        }

        let version = FluidAudioModelManager.asrVersion(for: modelName)
        let progressHandler: DownloadUtils.ProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(progress, for: modelName, downloadID: downloadID)
            }
        }

        do {
            _ = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: progressHandler
            )
            logger.notice(
                "FluidAudio download finished: \(modelName, privacy: .public), downloaded=\(self.isFluidAudioModelDownloaded(named: modelName), privacy: .public)"
            )
        } catch {
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        } catch {
            // Silently ignore removal errors
        }

        // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
        onModelDeleted?(model.name)
    }

    // MARK: - Finder

    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: - Private helpers

    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        cacheDirectory(for: FluidAudioModelManager.asrVersion(for: model.name))
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    private func clearDownloadStatus(for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }
        activeDownloadIDs[modelName] = nil
        downloadStatuses[modelName] = nil
        lastLoggedDownloadPercents[modelName] = nil
        lastLoggedDownloadMessages[modelName] = nil
    }

    private func updateDownloadProgress(_ progress: DownloadUtils.DownloadProgress, for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }

        let status = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: progress.fractionCompleted,
            phase: FluidAudioModelManager.downloadPhase(for: progress)
        )
        downloadStatuses[modelName] = status
        logDownloadProgressIfNeeded(status, for: modelName)
    }

    private func logDownloadProgressIfNeeded(_ status: VoiceInkFluidAudioDownloadStatus, for modelName: String) {
        let percent = status.percent
        let previousPercent = lastLoggedDownloadPercents[modelName]
        let previousMessage = lastLoggedDownloadMessages[modelName]
        let shouldLog = previousPercent == nil
            || previousMessage != status.message
            || percent >= (previousPercent ?? 0) + 5
            || percent == 100

        guard shouldLog else { return }

        lastLoggedDownloadPercents[modelName] = percent
        lastLoggedDownloadMessages[modelName] = status.message
        logger.notice(
            "FluidAudio download progress: \(modelName, privacy: .public), percent=\(percent, privacy: .public), message=\(status.message, privacy: .public)"
        )
    }

    private static func downloadPhase(for progress: DownloadUtils.DownloadProgress) -> VoiceInkFluidAudioDownloadPhase {
        switch progress.phase {
        case .listing:
            return .listingFiles
        case .downloading(let completedFiles, let totalFiles):
            guard totalFiles > 0 else {
                return .checkingCachedModels
            }
            return .downloadingFiles(completedFiles: completedFiles, totalFiles: totalFiles)
        case .compiling(let modelName):
            guard !modelName.isEmpty else {
                return .finalizingModels
            }
            return .compiling(modelComponentName: modelName)
        }
    }
}

private extension AsrModelVersion {
    init(_ version: VoiceInkFluidAudioModelVersion) {
        switch version {
        case .v2:
            self = .v2
        case .v3:
            self = .v3
        }
    }
}
