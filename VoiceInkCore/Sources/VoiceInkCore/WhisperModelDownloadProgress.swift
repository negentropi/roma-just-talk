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

    public var phaseText: String {
        phase.displayText
    }

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
        "To enable offline transcription, a \(model.size) model needs to be downloaded. This may incur data charges if you are not on Wi-Fi."
    }

    private static func clampedFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct VoiceInkWhisperModelDownloadState: Equatable, Sendable {
    public let isDownloaded: Bool
    public let progress: VoiceInkWhisperModelDownloadProgress

    public var isDownloading: Bool {
        progress.isActive
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
