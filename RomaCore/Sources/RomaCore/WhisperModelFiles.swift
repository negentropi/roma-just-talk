import Foundation

public enum RomaVADModelFiles {
    public static let sileroResourceName = "ggml-silero-v5.1.2"
    public static let sileroFileExtension = "bin"
    public static let sileroFilename = "\(sileroResourceName).\(sileroFileExtension)"

    public static func sileroURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: sileroResourceName, withExtension: sileroFileExtension)
    }

    public static func sileroPath(in bundle: Bundle = .main) -> String? {
        sileroURL(in: bundle)?.path
    }
}

public struct RomaWhisperModelFileSpec: Codable, Equatable, Identifiable, Sendable {
    public let modelName: String
    public let displayName: String
    public let filename: String
    public let size: String
    public let description: String
    public let isMultilingual: Bool
    public let speed: Double
    public let accuracy: Double
    public let ramUsage: Double

    public var id: String { modelName }

    public init(
        modelName: String,
        displayName: String,
        filename: String,
        size: String,
        description: String,
        isMultilingual: Bool = true,
        speed: Double = 0,
        accuracy: Double = 0,
        ramUsage: Double = 0
    ) {
        self.modelName = modelName
        self.displayName = displayName
        self.filename = filename
        self.size = size
        self.description = description
        self.isMultilingual = isMultilingual
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
    }

    public var downloadURL: URL {
        RomaWhisperModelFiles.downloadURL(forFilename: filename)
    }

    public func fileURL(in modelsDirectory: URL) -> URL {
        RomaWhisperModelFiles.fileURL(forFilename: filename, in: modelsDirectory)
    }

    public func isDownloaded(in modelsDirectory: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: fileURL(in: modelsDirectory).path)
    }

    public func deleteDownloadedFiles(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try RomaWhisperModelFiles.deleteModelFiles(
            forModelName: modelName,
            modelFileURL: fileURL(in: modelsDirectory),
            in: modelsDirectory,
            fileManager: fileManager
        )
    }
}

public struct RomaWhisperLocalModelFile: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public var coreMLEncoderURL: URL?

    public var isCoreMLDownloaded: Bool {
        coreMLEncoderURL != nil
    }

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        coreMLEncoderURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.coreMLEncoderURL = coreMLEncoderURL
    }
}

public struct RomaWhisperLocalModelImportPlan: Equatable, Sendable {
    public let sourceURL: URL
    public let modelName: String
    public let modelFilename: String
    public let destinationURL: URL
    public let localModelFile: RomaWhisperLocalModelFile
    public let isDuplicate: Bool

    public init(
        sourceURL: URL,
        modelName: String,
        modelFilename: String,
        destinationURL: URL,
        localModelFile: RomaWhisperLocalModelFile,
        isDuplicate: Bool
    ) {
        self.sourceURL = sourceURL
        self.modelName = modelName
        self.modelFilename = modelFilename
        self.destinationURL = destinationURL
        self.localModelFile = localModelFile
        self.isDuplicate = isDuplicate
    }
}

public enum RomaWhisperModelDownloadResponsePolicy {
    public enum Completion: Equatable, Sendable {
        case ready(URL)
        case serverError
        case missingTemporaryFile
    }

    public static func isSuccessfulStatusCode(_ statusCode: Int) -> Bool {
        (200...299).contains(statusCode)
    }

    public static func isSuccessfulResponse(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse else {
            return false
        }

        return isSuccessfulStatusCode(response.statusCode)
    }

    public static func completion(
        temporaryURL: URL?,
        response: URLResponse?
    ) -> Completion {
        guard isSuccessfulResponse(response) else {
            return .serverError
        }

        guard let temporaryURL else {
            return .missingTemporaryFile
        }

        return .ready(temporaryURL)
    }
}

public enum RomaWhisperModelFiles {
    public static let modelsDirectoryName = "WhisperModels"
    public static let modelFileExtension = "bin"

    public static func modelsDirectory(in baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(modelsDirectoryName)
    }

    @discardableResult
    public static func createModelsDirectory(
        in baseDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = modelsDirectory(in: baseDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static let baseModel = RomaWhisperModelFileSpec(
        modelName: RomaTranscriptionModelCatalog.localBaseModel,
        displayName: "Whisper Base Model",
        filename: "ggml-base.bin",
        size: "142 MB",
        description: "Multilingual model with good balance of speed and accuracy",
        isMultilingual: true,
        speed: 0.85,
        accuracy: 0.72,
        ramUsage: 0.5
    )

    public static let bootstrapModels = [baseModel]

    public static func availableBootstrapModelFileURL(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        availableModelFileURL(
            forRuntimeModelName: RomaTranscriptionModelCatalog.localBaseModel,
            in: modelsDirectory,
            fileManager: fileManager
        )
    }

    public static let downloadableModels = [
        RomaWhisperModelFileSpec(
            modelName: "ggml-tiny",
            displayName: "Tiny",
            filename: filename(forModelName: "ggml-tiny"),
            size: "75 MB",
            description: "Tiny model, fastest, least accurate",
            isMultilingual: true,
            speed: 0.95,
            accuracy: 0.6,
            ramUsage: 0.3
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-tiny.en",
            displayName: "Tiny (English)",
            filename: filename(forModelName: "ggml-tiny.en"),
            size: "75 MB",
            description: "Tiny model optimized for English, fastest, least accurate",
            isMultilingual: false,
            speed: 0.95,
            accuracy: 0.65,
            ramUsage: 0.3
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-base",
            displayName: "Base",
            filename: filename(forModelName: "ggml-base"),
            size: "142 MB",
            description: "Base model, good balance between speed and accuracy, supports multiple languages",
            isMultilingual: true,
            speed: 0.85,
            accuracy: 0.72,
            ramUsage: 0.5
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-base.en",
            displayName: "Base (English)",
            filename: filename(forModelName: "ggml-base.en"),
            size: "142 MB",
            description: "Base model optimized for English, good balance between speed and accuracy",
            isMultilingual: false,
            speed: 0.85,
            accuracy: 0.75,
            ramUsage: 0.5
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-large-v2",
            displayName: "Large v2",
            filename: filename(forModelName: "ggml-large-v2"),
            size: "2.9 GB",
            description: "Large model v2, slower than Medium but more accurate",
            isMultilingual: true,
            speed: 0.3,
            accuracy: 0.96,
            ramUsage: 3.8
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-large-v3",
            displayName: "Large v3",
            filename: filename(forModelName: "ggml-large-v3"),
            size: "2.9 GB",
            description: "Large model v3, very slow but most accurate",
            isMultilingual: true,
            speed: 0.3,
            accuracy: 0.98,
            ramUsage: 3.9
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-large-v3-turbo",
            displayName: "Large v3 Turbo",
            filename: filename(forModelName: "ggml-large-v3-turbo"),
            size: "1.5 GB",
            description: "Large model v3 Turbo, faster than v3 with similar accuracy",
            isMultilingual: true,
            speed: 0.75,
            accuracy: 0.97,
            ramUsage: 1.8
        ),
        RomaWhisperModelFileSpec(
            modelName: "ggml-large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo (Quantized)",
            filename: filename(forModelName: "ggml-large-v3-turbo-q5_0"),
            size: "547 MB",
            description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
            isMultilingual: true,
            speed: 0.75,
            accuracy: 0.95,
            ramUsage: 1.0
        )
    ]

    public static func downloadURL(forFilename filename: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main")!
            .appendingPathComponent(filename)
    }

    public static func filename(forModelName modelName: String) -> String {
        "\(modelName).\(modelFileExtension)"
    }

    public static func isModelFile(_ url: URL) -> Bool {
        url.pathExtension == modelFileExtension
    }

    public static func isImportableModelFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == modelFileExtension
    }

    public static func localModelImportPlan(
        from sourceURL: URL,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> RomaWhisperLocalModelImportPlan? {
        guard isImportableModelFile(sourceURL) else { return nil }

        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let modelFilename = filename(forModelName: modelName)
        let destinationURL = fileURL(forFilename: modelFilename, in: modelsDirectory)
        return RomaWhisperLocalModelImportPlan(
            sourceURL: sourceURL,
            modelName: modelName,
            modelFilename: modelFilename,
            destinationURL: destinationURL,
            localModelFile: RomaWhisperLocalModelFile(name: modelName, url: destinationURL),
            isDuplicate: fileManager.fileExists(atPath: destinationURL.path)
        )
    }

    public static func localModelFile(from fileURL: URL) -> RomaWhisperLocalModelFile? {
        guard isModelFile(fileURL) else { return nil }
        return RomaWhisperLocalModelFile(
            name: fileURL.deletingPathExtension().lastPathComponent,
            url: fileURL
        )
    }

    public static func localModelFiles(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [RomaWhisperLocalModelFile] {
        try fileManager
            .contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            .compactMap { localModelFile(from: $0) }
    }

    public static func importedLocalModelNamesToAdd(
        downloadedLocalModels: [RomaWhisperLocalModelFile],
        existingModelNames: [String]
    ) -> [String] {
        var existingNames = Set(existingModelNames)
        var namesToAdd: [String] = []

        for model in downloadedLocalModels where !existingNames.contains(model.name) {
            namesToAdd.append(model.name)
            existingNames.insert(model.name)
        }

        return namesToAdd
    }

    public static func downloadedLocalModelFile(
        forModelName modelName: String,
        in localModels: [RomaWhisperLocalModelFile]
    ) -> RomaWhisperLocalModelFile? {
        localModels.first { $0.name == modelName }
    }

    public static func availableLocalModelFileURL(
        forModelName modelName: String,
        in localModels: [RomaWhisperLocalModelFile],
        fileManager: FileManager = .default
    ) -> URL? {
        guard let model = downloadedLocalModelFile(forModelName: modelName, in: localModels),
              fileManager.fileExists(atPath: model.url.path) else {
            return nil
        }

        return model.url
    }

    public static func fileURL(forFilename filename: String, in modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent(filename)
    }

    public static func fileURL(forModelName modelName: String, in modelsDirectory: URL) -> URL {
        fileURL(forFilename: filename(forModelName: modelName), in: modelsDirectory)
    }

    public static func fileURL(
        forRuntimeModelName modelName: String,
        in modelsDirectory: URL
    ) -> URL {
        let normalizedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedName == RomaTranscriptionModelCatalog.localBaseModel {
            return baseModel.fileURL(in: modelsDirectory)
        }
        return fileURL(forModelName: normalizedName, in: modelsDirectory)
    }

    public static func availableModelFileURL(
        forRuntimeModelName modelName: String,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let url = fileURL(forRuntimeModelName: modelName, in: modelsDirectory)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public static func downloadURL(forModelName modelName: String) -> URL {
        downloadURL(forFilename: filename(forModelName: modelName))
    }

    @discardableResult
    public static func installDownloadedModelFile(
        _ model: RomaWhisperModelFileSpec,
        fromTemporaryFile temporaryURL: URL,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try installDownloadedModelFile(
            fromTemporaryFile: temporaryURL,
            to: model.fileURL(in: modelsDirectory),
            in: modelsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func installDownloadedModelFile(
        fromTemporaryFile temporaryURL: URL,
        to finalURL: URL,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        return finalURL
    }

    @discardableResult
    public static func writeDownloadedModelData(
        _ data: Data,
        forModelName modelName: String,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destinationURL = fileURL(forModelName: modelName, in: modelsDirectory)
        try data.write(to: destinationURL)
        return destinationURL
    }

    @discardableResult
    public static func writeDownloadedLocalModelData(
        _ data: Data,
        forModelName modelName: String,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> RomaWhisperLocalModelFile {
        let destinationURL = try writeDownloadedModelData(
            data,
            forModelName: modelName,
            in: modelsDirectory,
            fileManager: fileManager
        )
        return RomaWhisperLocalModelFile(name: modelName, url: destinationURL)
    }

    public static func supportsCoreML(forModelName modelName: String) -> Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }

    public static func coreMLZipFilename(forModelName modelName: String) -> String? {
        guard supportsCoreML(forModelName: modelName) else { return nil }
        return "\(modelName)-encoder.mlmodelc.zip"
    }

    public static func coreMLZipFileURL(forModelName modelName: String, in modelsDirectory: URL) -> URL? {
        guard let filename = coreMLZipFilename(forModelName: modelName) else { return nil }
        return fileURL(forFilename: filename, in: modelsDirectory)
    }

    public static func coreMLZipDownloadURL(forModelName modelName: String) -> URL? {
        guard let filename = coreMLZipFilename(forModelName: modelName) else { return nil }
        return downloadURL(forFilename: filename)
    }

    public static func coreMLEncoderDirectoryName(forModelName modelName: String) -> String? {
        guard supportsCoreML(forModelName: modelName) else { return nil }
        return "\(modelName)-encoder.mlmodelc"
    }

    public static func coreMLEncoderDirectoryURL(forModelName modelName: String, in modelsDirectory: URL) -> URL? {
        guard let directoryName = coreMLEncoderDirectoryName(forModelName: modelName) else { return nil }
        return modelsDirectory.appendingPathComponent(directoryName)
    }

    public static func deleteModelFiles(
        forModelName modelName: String,
        modelFileURL: URL,
        coreMLEncoderURL: URL? = nil,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.removeItem(at: modelFileURL)

        if let coreMLEncoderURL {
            try? fileManager.removeItem(at: coreMLEncoderURL)
            return
        }

        if let coreMLDirectory = coreMLEncoderDirectoryURL(forModelName: modelName, in: modelsDirectory) {
            try? fileManager.removeItem(at: coreMLDirectory)
        }
    }
}

public enum RomaWhisperModelManagementDiagnostics {
    public static func alreadyDownloadingMessage(modelName: String) -> String {
        "Model \(modelName) is already being downloaded."
    }

    public static func startingDownloadMessage(modelName: String, downloadURL: URL) -> String {
        "Starting download of \(modelName) from \(downloadURL.absoluteString)."
    }

    public static func downloadFailedMessage(modelName: String, alertMessage: String) -> String {
        "Download failed for \(modelName): \(alertMessage)"
    }

    public static func downloadCancelledMessage(modelName: String) -> String {
        "Download cancelled for \(modelName)."
    }

    public static func downloadedMessage(modelName: String, finalPath: String) -> String {
        "Successfully downloaded \(modelName) to \(finalPath)."
    }

    public static func saveFailedMessage(modelName: String, localizedDescription: String) -> String {
        "Failed to save \(modelName): \(localizedDescription)"
    }

    public static func notDownloadedMessage(modelName: String) -> String {
        "Model \(modelName) is not downloaded."
    }

    public static func deletedMessage(modelName: String) -> String {
        "Successfully deleted model \(modelName)."
    }

    public static func deleteFailedMessage(modelName: String, localizedDescription: String) -> String {
        "Failed to delete model \(modelName): \(localizedDescription)"
    }
}

public struct RomaWhisperModelOperationAlertPresentation: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String

    public init(
        id: String,
        title: String = "Download Error",
        message: String,
        primaryButtonTitle: String = "OK"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
    }

    public static var unknownDownloadFailure: RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "unknownDownloadFailure",
            message: "An unknown error occurred."
        )
    }

    public static func downloadFailed(
        localizedDescription: String
    ) -> RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "downloadFailed-\(localizedDescription)",
            message: "Download failed: \(localizedDescription)"
        )
    }

    public static func downloadFailed(for error: Error) -> RomaWhisperModelOperationAlertPresentation {
        downloadFailed(localizedDescription: error.localizedDescription)
    }

    public static var serverErrorDuringDownload: RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "serverErrorDuringDownload",
            message: "Server error during download"
        )
    }

    public static var noFileReceived: RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "noFileReceived",
            message: "No file received"
        )
    }

    public static func saveFailed(
        localizedDescription: String
    ) -> RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "saveFailed-\(localizedDescription)",
            message: "Failed to save model: \(localizedDescription)"
        )
    }

    public static func saveFailed(for error: Error) -> RomaWhisperModelOperationAlertPresentation {
        saveFailed(localizedDescription: error.localizedDescription)
    }

    public static func deleteFailed(
        localizedDescription: String
    ) -> RomaWhisperModelOperationAlertPresentation {
        RomaWhisperModelOperationAlertPresentation(
            id: "deleteFailed-\(localizedDescription)",
            message: "Failed to delete model: \(localizedDescription)"
        )
    }

    public static func deleteFailed(for error: Error) -> RomaWhisperModelOperationAlertPresentation {
        deleteFailed(localizedDescription: error.localizedDescription)
    }
}

private enum RomaWhisperModelSimpleDownloadCompletionAction: Equatable, Sendable {
    case installTemporaryFile(URL)
    case presentFailure(RomaWhisperModelOperationAlertPresentation)
    case ignoreCancellation
}

public struct RomaWhisperModelSimpleDownloadCompletionPlan: Equatable, Sendable {
    private let action: RomaWhisperModelSimpleDownloadCompletionAction

    private init(action: RomaWhisperModelSimpleDownloadCompletionAction) {
        self.action = action
    }

    public static func completion(
        temporaryURL: URL?,
        response: URLResponse?,
        error: Error?
    ) -> Self {
        if let error {
            if isCancellation(error) {
                return Self(action: .ignoreCancellation)
            }

            return Self(action: .presentFailure(.downloadFailed(for: error)))
        }

        switch RomaWhisperModelDownloadResponsePolicy.completion(
            temporaryURL: temporaryURL,
            response: response
        ) {
        case .ready(let temporaryURL):
            return Self(action: .installTemporaryFile(temporaryURL))
        case .serverError:
            return Self(action: .presentFailure(.serverErrorDuringDownload))
        case .missingTemporaryFile:
            return Self(action: .presentFailure(.noFileReceived))
        }
    }

    public func applyRuntimeState(
        installTemporaryFile: (URL) -> Void,
        presentFailure: (RomaWhisperModelOperationAlertPresentation) -> Void,
        ignoreCancellation: () -> Void
    ) {
        switch action {
        case .installTemporaryFile(let temporaryURL):
            installTemporaryFile(temporaryURL)
        case .presentFailure(let alert):
            presentFailure(alert)
        case .ignoreCancellation:
            ignoreCancellation()
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

public struct RomaWhisperModelOperationConfirmationPresentation: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String

    public init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String = "Cancel"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
    }

    public static func download(for model: RomaWhisperModelFileSpec) -> Self {
        RomaWhisperModelOperationConfirmationPresentation(
            id: "download-\(model.id)",
            title: "Download Model",
            message: "To enable offline transcription, a \(model.size) model needs to be downloaded. This may incur data charges if you are not on Wi-Fi.",
            primaryButtonTitle: "Download"
        )
    }

    public static func delete(for model: RomaWhisperModelFileSpec) -> Self {
        RomaWhisperModelOperationConfirmationPresentation(
            id: "delete-\(model.id)",
            title: "Delete Model",
            message: "Delete \(model.displayName)? This will remove the model from your device.",
            primaryButtonTitle: "Delete"
        )
    }
}

public enum RomaWhisperModelDownloadPhase: Equatable, Sendable {
    case idle
    case downloadingMainModel(modelName: String)
    case downloadingCoreMLModel(modelName: String)
    case optimizingModelForDevice

    public var displayText: String {
        switch self {
        case .idle:
            return ""
        case .downloadingMainModel(let modelName):
            return "Downloading \(modelName) Model"
        case .downloadingCoreMLModel(let modelName):
            return "Downloading Core ML Model for \(modelName)"
        case .optimizingModelForDevice:
            return "Optimizing model for your device"
        }
    }
}

public struct RomaWhisperModelDownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let phase: RomaWhisperModelDownloadPhase

    public init(fraction: Double, phase: RomaWhisperModelDownloadPhase) {
        self.fraction = Self.clampedFraction(fraction)
        self.phase = phase
    }

    public var isActive: Bool {
        phase != .idle
    }

    public var percentText: String {
        "\(Int(fraction * 100))%"
    }

    public var compactStatusText: String {
        isActive ? Self.compactDownloadingStatusText : ""
    }

    public var phaseText: String {
        phase.displayText
    }

    public static let compactDownloadingStatusText = "Downloading..."

    public static func simple(
        modelName: String,
        isDownloading: Bool,
        progress: Double?
    ) -> RomaWhisperModelDownloadProgress {
        guard isDownloading else {
            return RomaWhisperModelDownloadProgress(fraction: 0, phase: .idle)
        }

        return RomaWhisperModelDownloadProgress(
            fraction: progress ?? 0,
            phase: .downloadingMainModel(modelName: modelName)
        )
    }

    public static func macOS(
        modelName: String,
        downloadProgress: [String: Double],
        isOptimizing: Bool = false
    ) -> RomaWhisperModelDownloadProgress {
        if isOptimizing {
            return RomaWhisperModelDownloadProgress(
                fraction: 1,
                phase: .optimizingModelForDevice
            )
        }

        let mainKey = mainProgressKey(forModelName: modelName)
        let coreMLKey = coreMLProgressKey(forModelName: modelName)
        let isDownloadingMainModel = downloadProgress[mainKey] != nil
        let mainProgress = clampedFraction(downloadProgress[mainKey] ?? 0)
        let coreMLProgress = clampedFraction(downloadProgress[coreMLKey] ?? 0)

        if RomaWhisperModelFiles.supportsCoreML(forModelName: modelName),
           downloadProgress[coreMLKey] != nil {
            return RomaWhisperModelDownloadProgress(
                fraction: (mainProgress * 0.5) + (coreMLProgress * 0.5),
                phase: .downloadingCoreMLModel(modelName: modelName)
            )
        }

        return RomaWhisperModelDownloadProgress(
            fraction: mainProgress,
            phase: isDownloadingMainModel ? .downloadingMainModel(modelName: modelName) : .idle
        )
    }

    public static func isMacOSDownloading(
        modelName: String,
        downloadProgress: [String: Double]
    ) -> Bool {
        downloadProgress.keys.contains(mainProgressKey(forModelName: modelName)) ||
        downloadProgress.keys.contains(coreMLProgressKey(forModelName: modelName))
    }

    public static func mainProgressKey(forModelName modelName: String) -> String {
        "\(modelName)_main"
    }

    public static func coreMLProgressKey(forModelName modelName: String) -> String {
        "\(modelName)_coreml"
    }

    public static func downloadActionTitle(for model: RomaWhisperModelFileSpec) -> String {
        "Download Model (\(model.size))"
    }

    public static func downloadConfirmationMessage(for model: RomaWhisperModelFileSpec) -> String {
        RomaWhisperModelOperationConfirmationPresentation.download(for: model).message
    }

    private static func clampedFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

enum RomaWhisperModelDownloadRowAction: Equatable, Sendable {
    case download
    case downloading
    case downloaded

    func runtimeAction(
        requestDownload: @escaping () -> Void,
        cancelDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        switch self {
        case .download:
            return requestDownload
        case .downloading:
            return cancelDownload
        case .downloaded:
            return nil
        }
    }
}

public enum RomaWhisperModelDownloadRowActionTint: Equatable, Sendable {
    case primary
    case destructive
    case success
}

public struct RomaWhisperModelDownloadRowPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    let action: RomaWhisperModelDownloadRowAction
    public let downloadButtonTitle: String
    public let progress: RomaWhisperModelDownloadProgress

    public var actionSystemImageName: String {
        switch action {
        case .download:
            return "icloud.and.arrow.down"
        case .downloading:
            return "xmark.circle.fill"
        case .downloaded:
            return "checkmark.circle.fill"
        }
    }

    public var actionTint: RomaWhisperModelDownloadRowActionTint {
        switch action {
        case .download:
            return .primary
        case .downloading:
            return .destructive
        case .downloaded:
            return .success
        }
    }

    public var shouldShowCircularProgressAccessory: Bool {
        action == .downloading
    }

    public var downloadButtonSystemImageName: String {
        "arrow.down.circle.fill"
    }

    public var shouldShowProgress: Bool {
        progress.isActive
    }

    public func runtimeAction(
        requestDownload: @escaping () -> Void,
        cancelDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        action.runtimeAction(
            requestDownload: requestDownload,
            cancelDownload: cancelDownload
        )
    }
}

public struct RomaWhisperModelDownloadState: Equatable, Sendable {
    public let isDownloaded: Bool
    public let progress: RomaWhisperModelDownloadProgress

    public var isDownloading: Bool {
        progress.isActive
    }

    public func rowPresentation(
        for model: RomaWhisperModelFileSpec
    ) -> RomaWhisperModelDownloadRowPresentation {
        let action: RomaWhisperModelDownloadRowAction

        if isDownloaded {
            action = .downloaded
        } else if isDownloading {
            action = .downloading
        } else {
            action = .download
        }

        return RomaWhisperModelDownloadRowPresentation(
            title: model.displayName,
            subtitle: model.description,
            action: action,
            downloadButtonTitle: RomaWhisperModelDownloadProgress.downloadActionTitle(for: model),
            progress: progress
        )
    }

    public init(
        isDownloaded: Bool,
        progress: RomaWhisperModelDownloadProgress
    ) {
        self.isDownloaded = isDownloaded
        self.progress = progress
    }

    public static func simple(
        model: RomaWhisperModelFileSpec,
        modelsDirectory: URL,
        isDownloadingByModelID: [String: Bool],
        downloadProgressByModelID: [String: Double],
        fileManager: FileManager = .default
    ) -> RomaWhisperModelDownloadState {
        let isDownloading = isDownloadingByModelID[model.id] == true
        return RomaWhisperModelDownloadState(
            isDownloaded: model.isDownloaded(in: modelsDirectory, fileManager: fileManager),
            progress: RomaWhisperModelDownloadProgress.simple(
                modelName: model.modelName,
                isDownloading: isDownloading,
                progress: downloadProgressByModelID[model.id]
            )
        )
    }
}

private enum RomaWhisperModelDeletionAction: Equatable, Sendable {
    case skipMissingFile
    case deleteDownloadedFiles
}

public struct RomaWhisperModelDeletionPlan: Equatable, Sendable {
    private let action: RomaWhisperModelDeletionAction

    fileprivate init(action: RomaWhisperModelDeletionAction) {
        self.action = action
    }

    public func applyRuntimeState(
        skipMissingFile: () -> Void,
        deleteDownloadedFiles: () throws -> Void,
        refreshAfterSuccessfulDelete: () -> Void,
        handleDeleteFailure: (Error) -> Void
    ) {
        switch action {
        case .skipMissingFile:
            skipMissingFile()
        case .deleteDownloadedFiles:
            do {
                try deleteDownloadedFiles()
                refreshAfterSuccessfulDelete()
            } catch {
                handleDeleteFailure(error)
            }
        }
    }
}

public enum RomaWhisperModelDeletionPolicy {
    public static func plan(
        for model: RomaWhisperModelFileSpec,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> RomaWhisperModelDeletionPlan {
        plan(isDownloaded: model.isDownloaded(in: modelsDirectory, fileManager: fileManager))
    }

    public static func plan(isDownloaded: Bool) -> RomaWhisperModelDeletionPlan {
        if isDownloaded {
            return RomaWhisperModelDeletionPlan(action: .deleteDownloadedFiles)
        }

        return RomaWhisperModelDeletionPlan(action: .skipMissingFile)
    }
}

public struct RomaWhisperModelManagementRow: Equatable, Identifiable, Sendable {
    public let model: RomaWhisperModelFileSpec
    public let presentation: RomaWhisperModelDownloadRowPresentation
    public let downloadConfirmation: RomaWhisperModelOperationConfirmationPresentation
    public let deleteConfirmation: RomaWhisperModelOperationConfirmationPresentation

    public var id: String { model.id }
    private var shouldShowDeleteAction: Bool { presentation.action == .downloaded }

    public func deleteRequestRuntimeAction(
        requestDelete: @escaping () -> Void
    ) -> (() -> Void)? {
        shouldShowDeleteAction ? requestDelete : nil
    }

    public func confirmedDeleteRuntimeAction(
        delete: @escaping () -> Void
    ) -> (() -> Void)? {
        shouldShowDeleteAction ? delete : nil
    }

    public func confirmedDownloadRuntimeAction(
        startDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        presentation.action == .download ? startDownload : nil
    }

    public init(
        model: RomaWhisperModelFileSpec,
        presentation: RomaWhisperModelDownloadRowPresentation,
        downloadConfirmation: RomaWhisperModelOperationConfirmationPresentation,
        deleteConfirmation: RomaWhisperModelOperationConfirmationPresentation
    ) {
        self.model = model
        self.presentation = presentation
        self.downloadConfirmation = downloadConfirmation
        self.deleteConfirmation = deleteConfirmation
    }
}

public enum RomaWhisperModelManagementList {
    public static func row(
        for model: RomaWhisperModelFileSpec,
        downloadState: RomaWhisperModelDownloadState
    ) -> RomaWhisperModelManagementRow {
        RomaWhisperModelManagementRow(
            model: model,
            presentation: downloadState.rowPresentation(for: model),
            downloadConfirmation: .download(for: model),
            deleteConfirmation: .delete(for: model)
        )
    }

    public static func rows(
        for models: [RomaWhisperModelFileSpec] = RomaWhisperModelFiles.bootstrapModels,
        downloadStateForModel: (RomaWhisperModelFileSpec) -> RomaWhisperModelDownloadState
    ) -> [RomaWhisperModelManagementRow] {
        models.map { model in
            row(
                for: model,
                downloadState: downloadStateForModel(model)
            )
        }
    }
}

public struct RomaWhisperModelSimpleDownloadTrackingState: Equatable, Sendable {
    private var isDownloadingByModelID: [String: Bool]
    private var downloadProgressByModelID: [String: Double]

    public init(
        isDownloadingByModelID: [String: Bool] = [:],
        downloadProgressByModelID: [String: Double] = [:]
    ) {
        self.isDownloadingByModelID = isDownloadingByModelID
        self.downloadProgressByModelID = downloadProgressByModelID
    }

    public func isDownloading(_ model: RomaWhisperModelFileSpec) -> Bool {
        isDownloadingByModelID[model.id, default: false]
    }

    @discardableResult
    public mutating func startDownload(for model: RomaWhisperModelFileSpec) -> Bool {
        guard !isDownloading(model) else {
            return false
        }

        isDownloadingByModelID[model.id] = true
        downloadProgressByModelID[model.id] = 0
        return true
    }

    public mutating func updateProgress(_ progress: Double, for model: RomaWhisperModelFileSpec) {
        guard isDownloading(model) else {
            return
        }

        downloadProgressByModelID[model.id] = progress
    }

    public mutating func finishDownload(for model: RomaWhisperModelFileSpec) {
        isDownloadingByModelID[model.id] = nil
        downloadProgressByModelID[model.id] = nil
    }

    public mutating func cancelDownload(for model: RomaWhisperModelFileSpec) {
        finishDownload(for: model)
    }

    public func downloadState(
        for model: RomaWhisperModelFileSpec,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> RomaWhisperModelDownloadState {
        RomaWhisperModelDownloadState.simple(
            model: model,
            modelsDirectory: modelsDirectory,
            isDownloadingByModelID: isDownloadingByModelID,
            downloadProgressByModelID: downloadProgressByModelID,
            fileManager: fileManager
        )
    }
}

public struct RomaWhisperModelSimpleDownloadSessionID: Equatable, Hashable, Sendable {
    private let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct RomaWhisperModelSimpleDownloadSessionState: Equatable, Sendable {
    public private(set) var downloadTrackingState: RomaWhisperModelSimpleDownloadTrackingState
    private var activeSessionIDsByModelID: [String: RomaWhisperModelSimpleDownloadSessionID]

    public init(
        downloadTrackingState: RomaWhisperModelSimpleDownloadTrackingState = RomaWhisperModelSimpleDownloadTrackingState()
    ) {
        self.downloadTrackingState = downloadTrackingState
        self.activeSessionIDsByModelID = [:]
    }

    public func isDownloading(_ model: RomaWhisperModelFileSpec) -> Bool {
        downloadTrackingState.isDownloading(model)
    }

    public func isCurrentDownload(
        for model: RomaWhisperModelFileSpec,
        sessionID: RomaWhisperModelSimpleDownloadSessionID
    ) -> Bool {
        activeSessionIDsByModelID[model.id] == sessionID
    }

    @discardableResult
    public mutating func startDownload(
        for model: RomaWhisperModelFileSpec
    ) -> RomaWhisperModelSimpleDownloadSessionID? {
        guard activeSessionIDsByModelID[model.id] == nil,
              downloadTrackingState.startDownload(for: model) else {
            return nil
        }

        let sessionID = RomaWhisperModelSimpleDownloadSessionID()
        activeSessionIDsByModelID[model.id] = sessionID
        return sessionID
    }

    @discardableResult
    public mutating func updateProgress(
        _ progress: Double,
        for model: RomaWhisperModelFileSpec,
        sessionID: RomaWhisperModelSimpleDownloadSessionID
    ) -> Bool {
        guard isCurrentDownload(for: model, sessionID: sessionID) else {
            return false
        }

        downloadTrackingState.updateProgress(progress, for: model)
        return true
    }

    @discardableResult
    public mutating func finishDownload(
        for model: RomaWhisperModelFileSpec,
        sessionID: RomaWhisperModelSimpleDownloadSessionID
    ) -> Bool {
        guard isCurrentDownload(for: model, sessionID: sessionID) else {
            return false
        }

        activeSessionIDsByModelID[model.id] = nil
        downloadTrackingState.finishDownload(for: model)
        return true
    }

    @discardableResult
    public mutating func cancelDownload(for model: RomaWhisperModelFileSpec) -> Bool {
        let hadActiveSession = activeSessionIDsByModelID[model.id] != nil
        activeSessionIDsByModelID[model.id] = nil
        downloadTrackingState.cancelDownload(for: model)
        return hadActiveSession
    }
}

public struct RomaWhisperModelManagementSnapshot: Equatable, Sendable {
    public let modelsDirectory: URL
    private let downloadTrackingState: RomaWhisperModelSimpleDownloadTrackingState
    private let models: [RomaWhisperModelFileSpec]

    public init(
        modelsDirectory: URL,
        downloadTrackingState: RomaWhisperModelSimpleDownloadTrackingState,
        models: [RomaWhisperModelFileSpec] = RomaWhisperModelFiles.bootstrapModels
    ) {
        self.modelsDirectory = modelsDirectory
        self.downloadTrackingState = downloadTrackingState
        self.models = models
    }

    public func hasAvailableModel(fileManager: FileManager = .default) -> Bool {
        RomaWhisperModelFiles.availableBootstrapModelFileURL(
            in: modelsDirectory,
            fileManager: fileManager
        ) != nil
    }

    public func modelPath(
        forRuntimeModelName runtimeModelName: String,
        fileManager: FileManager = .default
    ) -> String? {
        RomaWhisperModelFiles.availableModelFileURL(
            forRuntimeModelName: runtimeModelName,
            in: modelsDirectory,
            fileManager: fileManager
        )?.path
    }

    public func downloadState(
        for model: RomaWhisperModelFileSpec,
        fileManager: FileManager = .default
    ) -> RomaWhisperModelDownloadState {
        downloadTrackingState.downloadState(
            for: model,
            modelsDirectory: modelsDirectory,
            fileManager: fileManager
        )
    }

    public func managementRow(
        for model: RomaWhisperModelFileSpec,
        fileManager: FileManager = .default
    ) -> RomaWhisperModelManagementRow {
        RomaWhisperModelManagementList.row(
            for: model,
            downloadState: downloadState(for: model, fileManager: fileManager)
        )
    }

    public func managementRows(fileManager: FileManager = .default) -> [RomaWhisperModelManagementRow] {
        RomaWhisperModelManagementList.rows(for: models) { model in
            downloadState(for: model, fileManager: fileManager)
        }
    }
}
