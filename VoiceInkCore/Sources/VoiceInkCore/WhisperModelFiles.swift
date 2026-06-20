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

public struct VoiceInkWhisperLocalModelFile: Equatable, Identifiable, Sendable {
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

public struct VoiceInkWhisperLocalModelImportPlan: Equatable, Sendable {
    public let sourceURL: URL
    public let modelName: String
    public let modelFilename: String
    public let destinationURL: URL
    public let localModelFile: VoiceInkWhisperLocalModelFile
    public let isDuplicate: Bool

    public init(
        sourceURL: URL,
        modelName: String,
        modelFilename: String,
        destinationURL: URL,
        localModelFile: VoiceInkWhisperLocalModelFile,
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

public enum VoiceInkWhisperModelDownloadResponsePolicy {
    public static func isSuccessfulStatusCode(_ statusCode: Int) -> Bool {
        (200...299).contains(statusCode)
    }

    public static func isSuccessfulResponse(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse else {
            return false
        }

        return isSuccessfulStatusCode(response.statusCode)
    }
}

public enum VoiceInkWhisperModelFiles {
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
        availableModelFileURL(
            forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
            in: modelsDirectory,
            fileManager: fileManager
        )
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
    ) -> VoiceInkWhisperLocalModelImportPlan? {
        guard isImportableModelFile(sourceURL) else { return nil }

        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let modelFilename = filename(forModelName: modelName)
        let destinationURL = fileURL(forFilename: modelFilename, in: modelsDirectory)
        return VoiceInkWhisperLocalModelImportPlan(
            sourceURL: sourceURL,
            modelName: modelName,
            modelFilename: modelFilename,
            destinationURL: destinationURL,
            localModelFile: VoiceInkWhisperLocalModelFile(name: modelName, url: destinationURL),
            isDuplicate: fileManager.fileExists(atPath: destinationURL.path)
        )
    }

    public static func localModelFile(from fileURL: URL) -> VoiceInkWhisperLocalModelFile? {
        guard isModelFile(fileURL) else { return nil }
        return VoiceInkWhisperLocalModelFile(
            name: fileURL.deletingPathExtension().lastPathComponent,
            url: fileURL
        )
    }

    public static func localModelFiles(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [VoiceInkWhisperLocalModelFile] {
        try fileManager
            .contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            .compactMap { localModelFile(from: $0) }
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
        if normalizedName == VoiceInkTranscriptionModelCatalog.localBaseModel {
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
        _ model: VoiceInkWhisperModelFileSpec,
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
    ) throws -> VoiceInkWhisperLocalModelFile {
        let destinationURL = try writeDownloadedModelData(
            data,
            forModelName: modelName,
            in: modelsDirectory,
            fileManager: fileManager
        )
        return VoiceInkWhisperLocalModelFile(name: modelName, url: destinationURL)
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
