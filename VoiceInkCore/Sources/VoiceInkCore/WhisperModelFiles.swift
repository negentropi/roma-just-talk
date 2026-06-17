import Foundation

public struct VoiceInkWhisperModelFileSpec: Codable, Equatable, Identifiable, Sendable {
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
        VoiceInkWhisperModelFiles.downloadURL(forFilename: filename)
    }

    public func fileURL(in modelsDirectory: URL) -> URL {
        VoiceInkWhisperModelFiles.fileURL(forFilename: filename, in: modelsDirectory)
    }

    public func isDownloaded(in modelsDirectory: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: fileURL(in: modelsDirectory).path)
    }

    public func deleteDownloadedFiles(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try VoiceInkWhisperModelFiles.deleteModelFiles(
            forModelName: modelName,
            modelFileURL: fileURL(in: modelsDirectory),
            in: modelsDirectory,
            fileManager: fileManager
        )
    }
}

public enum VoiceInkWhisperModelFiles {
    public static let modelsDirectoryName = "WhisperModels"

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

    public static let baseModel = VoiceInkWhisperModelFileSpec(
        modelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
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
        bootstrapModels.first {
            $0.isDownloaded(in: modelsDirectory, fileManager: fileManager)
        }?.fileURL(in: modelsDirectory)
    }

    public static let downloadableModels = [
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        VoiceInkWhisperModelFileSpec(
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
        "\(modelName).bin"
    }

    public static func isModelFile(_ url: URL) -> Bool {
        url.pathExtension == "bin"
    }

    public static func fileURL(forFilename filename: String, in modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent(filename)
    }

    public static func fileURL(forModelName modelName: String, in modelsDirectory: URL) -> URL {
        fileURL(forFilename: filename(forModelName: modelName), in: modelsDirectory)
    }

    public static func downloadURL(forModelName modelName: String) -> URL {
        downloadURL(forFilename: filename(forModelName: modelName))
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
