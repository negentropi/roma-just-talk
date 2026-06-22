import Foundation

public struct VoiceInkWhisperModelOperationAlertPresentation: Equatable, Identifiable, Sendable {
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

    public static var unknownDownloadFailure: VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "unknownDownloadFailure",
            message: "An unknown error occurred."
        )
    }

    public static func downloadFailed(
        localizedDescription: String
    ) -> VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "downloadFailed-\(localizedDescription)",
            message: "Download failed: \(localizedDescription)"
        )
    }

    public static func downloadFailed(for error: Error) -> VoiceInkWhisperModelOperationAlertPresentation {
        downloadFailed(localizedDescription: error.localizedDescription)
    }

    public static var serverErrorDuringDownload: VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "serverErrorDuringDownload",
            message: "Server error during download"
        )
    }

    public static var noFileReceived: VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "noFileReceived",
            message: "No file received"
        )
    }

    public static func saveFailed(
        localizedDescription: String
    ) -> VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "saveFailed-\(localizedDescription)",
            message: "Failed to save model: \(localizedDescription)"
        )
    }

    public static func saveFailed(for error: Error) -> VoiceInkWhisperModelOperationAlertPresentation {
        saveFailed(localizedDescription: error.localizedDescription)
    }

    public static func deleteFailed(
        localizedDescription: String
    ) -> VoiceInkWhisperModelOperationAlertPresentation {
        VoiceInkWhisperModelOperationAlertPresentation(
            id: "deleteFailed-\(localizedDescription)",
            message: "Failed to delete model: \(localizedDescription)"
        )
    }

    public static func deleteFailed(for error: Error) -> VoiceInkWhisperModelOperationAlertPresentation {
        deleteFailed(localizedDescription: error.localizedDescription)
    }
}

public enum VoiceInkWhisperModelSimpleDownloadCompletionPlan: Equatable, Sendable {
    case installTemporaryFile(URL)
    case presentFailure(VoiceInkWhisperModelOperationAlertPresentation)
    case ignoreCancellation

    public static func completion(
        temporaryURL: URL?,
        response: URLResponse?,
        error: Error?
    ) -> Self {
        if let error {
            if isCancellation(error) {
                return .ignoreCancellation
            }

            return .presentFailure(.downloadFailed(for: error))
        }

        switch VoiceInkWhisperModelDownloadResponsePolicy.completion(
            temporaryURL: temporaryURL,
            response: response
        ) {
        case .ready(let temporaryURL):
            return .installTemporaryFile(temporaryURL)
        case .serverError:
            return .presentFailure(.serverErrorDuringDownload)
        case .missingTemporaryFile:
            return .presentFailure(.noFileReceived)
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

public struct VoiceInkWhisperModelOperationConfirmationPresentation: Equatable, Identifiable, Sendable {
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

    public static func download(for model: VoiceInkWhisperModelFileSpec) -> Self {
        VoiceInkWhisperModelOperationConfirmationPresentation(
            id: "download-\(model.id)",
            title: "Download Model",
            message: "To enable offline transcription, a \(model.size) model needs to be downloaded. This may incur data charges if you are not on Wi-Fi.",
            primaryButtonTitle: "Download"
        )
    }

    public static func delete(for model: VoiceInkWhisperModelFileSpec) -> Self {
        VoiceInkWhisperModelOperationConfirmationPresentation(
            id: "delete-\(model.id)",
            title: "Delete Model",
            message: "Delete \(model.displayName)? This will remove the model from your device.",
            primaryButtonTitle: "Delete"
        )
    }
}

public enum VoiceInkWhisperModelDownloadPhase: Equatable, Sendable {
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

public struct VoiceInkWhisperModelDownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let phase: VoiceInkWhisperModelDownloadPhase

    public init(fraction: Double, phase: VoiceInkWhisperModelDownloadPhase) {
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
    ) -> VoiceInkWhisperModelDownloadProgress {
        guard isDownloading else {
            return VoiceInkWhisperModelDownloadProgress(fraction: 0, phase: .idle)
        }

        return VoiceInkWhisperModelDownloadProgress(
            fraction: progress ?? 0,
            phase: .downloadingMainModel(modelName: modelName)
        )
    }

    public static func macOS(
        modelName: String,
        downloadProgress: [String: Double],
        isOptimizing: Bool = false
    ) -> VoiceInkWhisperModelDownloadProgress {
        if isOptimizing {
            return VoiceInkWhisperModelDownloadProgress(
                fraction: 1,
                phase: .optimizingModelForDevice
            )
        }

        let mainKey = mainProgressKey(forModelName: modelName)
        let coreMLKey = coreMLProgressKey(forModelName: modelName)
        let isDownloadingMainModel = downloadProgress[mainKey] != nil
        let mainProgress = clampedFraction(downloadProgress[mainKey] ?? 0)
        let coreMLProgress = clampedFraction(downloadProgress[coreMLKey] ?? 0)

        if VoiceInkWhisperModelFiles.supportsCoreML(forModelName: modelName),
           downloadProgress[coreMLKey] != nil {
            return VoiceInkWhisperModelDownloadProgress(
                fraction: (mainProgress * 0.5) + (coreMLProgress * 0.5),
                phase: .downloadingCoreMLModel(modelName: modelName)
            )
        }

        return VoiceInkWhisperModelDownloadProgress(
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

    public static func downloadActionTitle(for model: VoiceInkWhisperModelFileSpec) -> String {
        "Download Model (\(model.size))"
    }

    public static func downloadConfirmationMessage(for model: VoiceInkWhisperModelFileSpec) -> String {
        VoiceInkWhisperModelOperationConfirmationPresentation.download(for: model).message
    }

    private static func clampedFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public enum VoiceInkWhisperModelDownloadRowAction: Equatable, Sendable {
    case download
    case downloading
    case downloaded
}

public struct VoiceInkWhisperModelDownloadRowPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let action: VoiceInkWhisperModelDownloadRowAction
    public let downloadButtonTitle: String
    public let progress: VoiceInkWhisperModelDownloadProgress

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

    public var downloadButtonSystemImageName: String {
        "arrow.down.circle.fill"
    }

    public var shouldShowProgress: Bool {
        progress.isActive
    }
}

public struct VoiceInkWhisperModelDownloadState: Equatable, Sendable {
    public let isDownloaded: Bool
    public let progress: VoiceInkWhisperModelDownloadProgress

    public var isDownloading: Bool {
        progress.isActive
    }

    public func rowPresentation(
        for model: VoiceInkWhisperModelFileSpec
    ) -> VoiceInkWhisperModelDownloadRowPresentation {
        let action: VoiceInkWhisperModelDownloadRowAction

        if isDownloaded {
            action = .downloaded
        } else if isDownloading {
            action = .downloading
        } else {
            action = .download
        }

        return VoiceInkWhisperModelDownloadRowPresentation(
            title: model.displayName,
            subtitle: model.description,
            action: action,
            downloadButtonTitle: VoiceInkWhisperModelDownloadProgress.downloadActionTitle(for: model),
            progress: progress
        )
    }

    public init(
        isDownloaded: Bool,
        progress: VoiceInkWhisperModelDownloadProgress
    ) {
        self.isDownloaded = isDownloaded
        self.progress = progress
    }

    public static func simple(
        model: VoiceInkWhisperModelFileSpec,
        modelsDirectory: URL,
        isDownloadingByModelID: [String: Bool],
        downloadProgressByModelID: [String: Double],
        fileManager: FileManager = .default
    ) -> VoiceInkWhisperModelDownloadState {
        let isDownloading = isDownloadingByModelID[model.id] == true
        return VoiceInkWhisperModelDownloadState(
            isDownloaded: model.isDownloaded(in: modelsDirectory, fileManager: fileManager),
            progress: VoiceInkWhisperModelDownloadProgress.simple(
                modelName: model.modelName,
                isDownloading: isDownloading,
                progress: downloadProgressByModelID[model.id]
            )
        )
    }
}

public enum VoiceInkWhisperModelDeletionAction: Equatable, Sendable {
    case skipMissingFile
    case deleteDownloadedFiles
}

public struct VoiceInkWhisperModelDeletionPlan: Equatable, Sendable {
    public let action: VoiceInkWhisperModelDeletionAction
    public let shouldRefreshAfterSuccessfulDelete: Bool

    public init(
        action: VoiceInkWhisperModelDeletionAction,
        shouldRefreshAfterSuccessfulDelete: Bool
    ) {
        self.action = action
        self.shouldRefreshAfterSuccessfulDelete = shouldRefreshAfterSuccessfulDelete
    }
}

public enum VoiceInkWhisperModelDeletionPolicy {
    public static func plan(
        for model: VoiceInkWhisperModelFileSpec,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> VoiceInkWhisperModelDeletionPlan {
        plan(isDownloaded: model.isDownloaded(in: modelsDirectory, fileManager: fileManager))
    }

    public static func plan(isDownloaded: Bool) -> VoiceInkWhisperModelDeletionPlan {
        if isDownloaded {
            return VoiceInkWhisperModelDeletionPlan(
                action: .deleteDownloadedFiles,
                shouldRefreshAfterSuccessfulDelete: true
            )
        }

        return VoiceInkWhisperModelDeletionPlan(
            action: .skipMissingFile,
            shouldRefreshAfterSuccessfulDelete: false
        )
    }
}

public struct VoiceInkWhisperModelManagementRow: Equatable, Identifiable, Sendable {
    public let model: VoiceInkWhisperModelFileSpec
    public let presentation: VoiceInkWhisperModelDownloadRowPresentation
    public let downloadConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation
    public let deleteConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation

    public var id: String { model.id }
    public var shouldShowDeleteAction: Bool { presentation.action == .downloaded }

    public init(
        model: VoiceInkWhisperModelFileSpec,
        presentation: VoiceInkWhisperModelDownloadRowPresentation,
        downloadConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation,
        deleteConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation
    ) {
        self.model = model
        self.presentation = presentation
        self.downloadConfirmation = downloadConfirmation
        self.deleteConfirmation = deleteConfirmation
    }
}

public enum VoiceInkWhisperModelManagementList {
    public static func row(
        for model: VoiceInkWhisperModelFileSpec,
        downloadState: VoiceInkWhisperModelDownloadState
    ) -> VoiceInkWhisperModelManagementRow {
        VoiceInkWhisperModelManagementRow(
            model: model,
            presentation: downloadState.rowPresentation(for: model),
            downloadConfirmation: .download(for: model),
            deleteConfirmation: .delete(for: model)
        )
    }

    public static func rows(
        for models: [VoiceInkWhisperModelFileSpec] = VoiceInkWhisperModelFiles.bootstrapModels,
        downloadStateForModel: (VoiceInkWhisperModelFileSpec) -> VoiceInkWhisperModelDownloadState
    ) -> [VoiceInkWhisperModelManagementRow] {
        models.map { model in
            row(
                for: model,
                downloadState: downloadStateForModel(model)
            )
        }
    }
}

public struct VoiceInkWhisperModelSimpleDownloadTrackingState: Equatable, Sendable {
    private var isDownloadingByModelID: [String: Bool]
    private var downloadProgressByModelID: [String: Double]

    public init(
        isDownloadingByModelID: [String: Bool] = [:],
        downloadProgressByModelID: [String: Double] = [:]
    ) {
        self.isDownloadingByModelID = isDownloadingByModelID
        self.downloadProgressByModelID = downloadProgressByModelID
    }

    public func isDownloading(_ model: VoiceInkWhisperModelFileSpec) -> Bool {
        isDownloadingByModelID[model.id, default: false]
    }

    @discardableResult
    public mutating func startDownload(for model: VoiceInkWhisperModelFileSpec) -> Bool {
        guard !isDownloading(model) else {
            return false
        }

        isDownloadingByModelID[model.id] = true
        downloadProgressByModelID[model.id] = 0
        return true
    }

    public mutating func updateProgress(_ progress: Double, for model: VoiceInkWhisperModelFileSpec) {
        guard isDownloading(model) else {
            return
        }

        downloadProgressByModelID[model.id] = progress
    }

    public mutating func finishDownload(for model: VoiceInkWhisperModelFileSpec) {
        isDownloadingByModelID[model.id] = false
        downloadProgressByModelID[model.id] = nil
    }

    public func downloadState(
        for model: VoiceInkWhisperModelFileSpec,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> VoiceInkWhisperModelDownloadState {
        VoiceInkWhisperModelDownloadState.simple(
            model: model,
            modelsDirectory: modelsDirectory,
            isDownloadingByModelID: isDownloadingByModelID,
            downloadProgressByModelID: downloadProgressByModelID,
            fileManager: fileManager
        )
    }
}
