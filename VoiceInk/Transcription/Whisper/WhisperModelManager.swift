import Foundation
import os
import Zip
import SwiftUI
import Atomics
import VoiceInkCore

// MARK: - WhisperModelManager

@MainActor
class WhisperModelManager: ObservableObject {
    @Published var availableModels: [VoiceInkWhisperLocalModelFile] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var whisperContext: WhisperContext?
    @Published var isModelLoaded = false
    @Published var loadedWhisperModel: VoiceInkWhisperLocalModelFile?
    @Published var isModelLoading = false

    let modelsDirectory: URL
    let whisperPrompt = WhisperPrompt()

    /// Called when a model is deleted, passing the model name.
    /// TranscriptionModelManager listens to clear currentTranscriptionModel if needed.
    var onModelDeleted: ((String) -> Void)?

    /// Called after a new model is added (downloaded or imported) so
    /// TranscriptionModelManager can rebuild allAvailableModels.
    var onModelsChanged: (() -> Void)?

    let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "WhisperModelManager")

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - Model Directory Management

    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating models directory", error)
        }
    }

    func loadAvailableModels() {
        do {
            availableModels = try VoiceInkWhisperModelFiles.localModelFiles(in: modelsDirectory)
        } catch {
            logError("Error loading available models", error)
        }
    }

    // MARK: - Model Loading

    func loadModel(_ model: VoiceInkWhisperLocalModelFile) async throws {
        guard whisperContext == nil else { return }

        isModelLoading = true
        defer { isModelLoading = false }

        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)

            isModelLoaded = true
            loadedWhisperModel = model
        } catch {
            throw VoiceInkEngineError.modelLoadFailed
        }
    }

    // MARK: - Model Download & Management

    private func downloadFileWithProgress(from url: URL, progressKey: String) async throws -> Data {
        let destinationURL = modelsDirectory.appendingPathComponent(UUID().uuidString)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let finished = ManagedAtomic(false)

            func finishOnce(_ result: Result<Data, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    finishOnce(.failure(error))
                    return
                }

                guard VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulResponse(response),
                      let tempURL = tempURL else {
                    finishOnce(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    let data = try Data(contentsOf: destinationURL, options: .mappedIfSafe)
                    finishOnce(.success(data))
                    try? FileManager.default.removeItem(at: destinationURL)
                } catch {
                    finishOnce(.failure(error))
                }
            }

            task.resume()

            var lastUpdateTime = Date()
            var lastProgressValue: Double = 0

            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let currentTime = Date()
                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
                let currentProgress = round(progress.fractionCompleted * 100) / 100

                if timeSinceLastUpdate >= 0.5 && abs(currentProgress - lastProgressValue) >= 0.01 {
                    lastUpdateTime = currentTime
                    lastProgressValue = currentProgress

                    DispatchQueue.main.async {
                        self.downloadProgress[progressKey] = currentProgress
                    }
                }
            }

            Task {
                await withTaskCancellationHandler {
                    observation.invalidate()
                    if finished.exchange(true, ordering: .acquiring) == false {
                        continuation.resume(throwing: CancellationError())
                    }
                } operation: {
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                }
            }
        }
    }

    func downloadModel(_ model: WhisperModel) async {
        await performModelDownload(
            model,
            VoiceInkWhisperModelFiles.downloadURL(forModelName: model.name)
        )
    }

    private func performModelDownload(_ model: WhisperModel, _ url: URL) async {
        do {
            var whisperModel = try await downloadMainModel(model, from: url)

            if let coreMLURL = VoiceInkWhisperModelFiles.coreMLZipDownloadURL(forModelName: whisperModel.name) {
                whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, from: coreMLURL)
            }

            availableModels.append(whisperModel)
            self.downloadProgress.removeValue(
                forKey: VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: model.name)
            )

            onModelsChanged?()

            if VoiceInkWhisperModelFiles.supportsCoreML(forModelName: model.name) {
                WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, whisperModelManager: self)
            }
        } catch {
            handleModelDownloadError(model, error)
        }
    }

    private func downloadMainModel(_ model: WhisperModel, from url: URL) async throws -> VoiceInkWhisperLocalModelFile {
        let progressKeyMain = VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: model.name)
        let data = try await downloadFileWithProgress(from: url, progressKey: progressKeyMain)

        return try VoiceInkWhisperModelFiles.writeDownloadedLocalModelData(
            data,
            forModelName: model.name,
            in: modelsDirectory
        )
    }

    private func downloadAndSetupCoreMLModel(for model: VoiceInkWhisperLocalModelFile, from url: URL) async throws -> VoiceInkWhisperLocalModelFile {
        let progressKeyCoreML = VoiceInkWhisperModelDownloadProgress.coreMLProgressKey(forModelName: model.name)
        let coreMLData = try await downloadFileWithProgress(from: url, progressKey: progressKeyCoreML)

        guard let coreMLZipPath = VoiceInkWhisperModelFiles.coreMLZipFileURL(
            forModelName: model.name,
            in: modelsDirectory
        ) else {
            return model
        }
        try coreMLData.write(to: coreMLZipPath)

        return try await unzipAndSetupCoreMLModel(for: model, zipPath: coreMLZipPath, progressKey: progressKeyCoreML)
    }

    private func unzipAndSetupCoreMLModel(for model: VoiceInkWhisperLocalModelFile, zipPath: URL, progressKey: String) async throws -> VoiceInkWhisperLocalModelFile {
        guard let coreMLDestination = VoiceInkWhisperModelFiles.coreMLEncoderDirectoryURL(
            forModelName: model.name,
            in: modelsDirectory
        ) else {
            throw VoiceInkEngineError.unzipFailed
        }

        try? FileManager.default.removeItem(at: coreMLDestination)
        try await unzipCoreMLFile(zipPath, to: modelsDirectory)
        return try verifyAndCleanupCoreMLFiles(model, coreMLDestination, zipPath, progressKey)
    }

    private func unzipCoreMLFile(_ zipPath: URL, to destination: URL) async throws {
        let finished = ManagedAtomic(false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Zip.unzipFile(zipPath, destination: destination, overwrite: true, password: nil)
                finishOnce(.success(()))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }

    private func verifyAndCleanupCoreMLFiles(_ model: VoiceInkWhisperLocalModelFile, _ destination: URL, _ zipPath: URL, _ progressKey: String) throws -> VoiceInkWhisperLocalModelFile {
        var model = model

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            try? FileManager.default.removeItem(at: zipPath)
            throw VoiceInkEngineError.unzipFailed
        }

        try? FileManager.default.removeItem(at: zipPath)
        model.coreMLEncoderURL = destination
        self.downloadProgress.removeValue(forKey: progressKey)

        return model
    }

    private func handleModelDownloadError(_ model: WhisperModel, _ error: Error) {
        self.downloadProgress.removeValue(
            forKey: VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: model.name)
        )
        self.downloadProgress.removeValue(
            forKey: VoiceInkWhisperModelDownloadProgress.coreMLProgressKey(forModelName: model.name)
        )
    }

    func deleteModel(_ model: VoiceInkWhisperLocalModelFile) async {
        do {
            try VoiceInkWhisperModelFiles.deleteModelFiles(
                forModelName: model.name,
                modelFileURL: model.url,
                coreMLEncoderURL: model.coreMLEncoderURL,
                in: modelsDirectory
            )

            availableModels.removeAll { $0.id == model.id }

            // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
            onModelDeleted?(model.name)
        } catch {
            logError("Error deleting model: \(model.name)", error)
        }
    }

    func unloadModel() {
        Task {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
        }
    }

    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try VoiceInkWhisperModelFiles.deleteModelFiles(
                    forModelName: model.name,
                    modelFileURL: model.url,
                    coreMLEncoderURL: model.coreMLEncoderURL,
                    in: modelsDirectory
                )
            } catch {
                logError("Error deleting model during cleanup", error)
            }
        }
        availableModels.removeAll()
    }

    // MARK: - Resource Management

    /// Releases the WhisperContext and resets model-loaded state.
    /// Does NOT call serviceRegistry.cleanup() — that is VoiceInkEngine's responsibility.
    func cleanupResources() async {
        logger.notice("WhisperModelManager.cleanupResources: releasing whisper context")
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
        logger.notice("WhisperModelManager.cleanupResources: completed")
    }

    // MARK: - Import Local Model

    func importWhisperModel(from sourceURL: URL) async {
        guard let importPlan = VoiceInkWhisperModelFiles.localModelImportPlan(
            from: sourceURL,
            in: modelsDirectory
        ) else { return }

        if importPlan.isDuplicate {
            await NotificationManager.shared.showNotification(
                title: VoiceInkModelManagementPresentation.importedLocalModelAlreadyExistsTitle(
                    modelFilename: importPlan.modelFilename
                ),
                type: .warning,
                duration: 4.0
            )
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: importPlan.sourceURL, to: importPlan.destinationURL)

            availableModels.append(importPlan.localModelFile)

            onModelsChanged?()

            await NotificationManager.shared.showNotification(
                title: VoiceInkModelManagementPresentation.importedLocalModelSuccessTitle(
                    filename: importPlan.modelFilename
                ),
                type: .success,
                duration: 3.0
            )
        } catch {
            logError("Failed to import local model", error)
            await NotificationManager.shared.showNotification(
                title: VoiceInkModelManagementPresentation.importedLocalModelFailureTitle(
                    errorDescription: error.localizedDescription
                ),
                type: .error,
                duration: 5.0
            )
        }
    }

    // MARK: - Helpers

    private func logError(_ message: String, _ error: Error) {
        logger.error("❌ \(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - WhisperModelProvider

extension WhisperModelManager: WhisperModelProvider {}

// MARK: - Download Progress View

struct DownloadProgressView: View {
    let modelName: String
    let downloadProgress: [String: Double]
    var isOptimizing = false

    @Environment(\.colorScheme) private var colorScheme

    private var progressPresentation: VoiceInkWhisperModelDownloadProgress {
        VoiceInkWhisperModelDownloadProgress.macOS(
            modelName: modelName,
            downloadProgress: downloadProgress,
            isOptimizing: isOptimizing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progressPresentation.phaseText)
                    .lineLimit(1)

                Spacer()

                Text(progressPresentation.percentText)
                    .fontDesign(.monospaced)
            }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.separatorColor).opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.controlAccentColor))
                        .frame(width: geometry.size.width * progressPresentation.fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: progressPresentation.fraction)
    }
}
