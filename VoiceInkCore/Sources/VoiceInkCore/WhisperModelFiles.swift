import Foundation

public struct VoiceInkWhisperModelFileSpec: Equatable, Sendable {
    public let modelName: String
    public let displayName: String
    public let filename: String
    public let size: String
    public let description: String

    public init(
        modelName: String,
        displayName: String,
        filename: String,
        size: String,
        description: String
    ) {
        self.modelName = modelName
        self.displayName = displayName
        self.filename = filename
        self.size = size
        self.description = description
    }

    public var downloadURL: URL {
        VoiceInkWhisperModelFiles.downloadURL(forFilename: filename)
    }

    public var downloadURLString: String {
        downloadURL.absoluteString
    }
}

public enum VoiceInkWhisperModelFiles {
    public static let modelsDirectoryName = "WhisperModels"

    public static let baseModel = VoiceInkWhisperModelFileSpec(
        modelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
        displayName: "Whisper Base Model",
        filename: "ggml-base.bin",
        size: "142 MB",
        description: "Multilingual model with good balance of speed and accuracy"
    )

    public static func downloadURL(forFilename filename: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main")!
            .appendingPathComponent(filename)
    }

    public static func downloadURLString(forFilename filename: String) -> String {
        downloadURL(forFilename: filename).absoluteString
    }

    public static func filename(forModelName modelName: String) -> String {
        "\(modelName).bin"
    }

    public static func downloadURL(forModelName modelName: String) -> URL {
        downloadURL(forFilename: filename(forModelName: modelName))
    }

    public static func downloadURLString(forModelName modelName: String) -> String {
        downloadURL(forModelName: modelName).absoluteString
    }

    public static func supportsCoreML(forModelName modelName: String) -> Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }

    public static func coreMLZipFilename(forModelName modelName: String) -> String? {
        guard supportsCoreML(forModelName: modelName) else { return nil }
        return "\(modelName)-encoder.mlmodelc.zip"
    }

    public static func coreMLZipDownloadURL(forModelName modelName: String) -> URL? {
        guard let filename = coreMLZipFilename(forModelName: modelName) else { return nil }
        return downloadURL(forFilename: filename)
    }

    public static func coreMLZipDownloadURLString(forModelName modelName: String) -> String? {
        coreMLZipDownloadURL(forModelName: modelName)?.absoluteString
    }

    public static func coreMLEncoderDirectoryName(forModelName modelName: String) -> String? {
        guard supportsCoreML(forModelName: modelName) else { return nil }
        return "\(modelName)-encoder.mlmodelc"
    }
}
