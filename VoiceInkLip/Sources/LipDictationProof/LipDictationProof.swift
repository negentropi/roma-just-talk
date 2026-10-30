import CryptoKit
import Darwin
import Foundation
import VoiceInkLip

private struct Options {
    let command: String
    let modelDirectory: URL?
    let video: URL?
    let receipt: URL?
    let mouthDump: URL?

    static let usage = """
    LipDictationProof install --model-directory PATH [--receipt PATH]
    LipDictationProof infer --model-directory PATH --video PATH [--receipt PATH] [--mouth-dump PATH]
    LipDictationProof preprocess --video PATH --mouth-dump PATH [--receipt PATH]

    install downloads and verifies the original publisher checkpoint through LipRuntime.
    infer reads only video and uses the installed model. No reference text is accepted.
    Mouth dumps contain little-endian float32 in [1,T,88,88] order, with shape/hash in the receipt.
    """

    init(_ arguments: [String]) throws {
        guard let command = arguments.first, ["install", "infer", "preprocess"].contains(command) else {
            throw ProofError.arguments(Self.usage)
        }
        var values: [String: String] = [:]
        var index = 1
        let allowed = ["--model-directory", "--video", "--receipt", "--mouth-dump"]
        while index < arguments.count {
            let option = arguments[index]
            guard allowed.contains(option), index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--"), values[option] == nil else {
                throw ProofError.arguments("Invalid or duplicate option \(option).\n\(Self.usage)")
            }
            values[option] = arguments[index + 1]
            index += 2
        }
        func url(_ option: String) -> URL? {
            values[option].map { URL(fileURLWithPath: $0).standardizedFileURL }
        }
        self.command = command
        modelDirectory = url("--model-directory")
        video = url("--video")
        receipt = url("--receipt")
        mouthDump = url("--mouth-dump")
        guard command == "preprocess" || modelDirectory != nil,
              command == "install" || video != nil,
              command != "preprocess" || mouthDump != nil,
              command != "install" || (video == nil && mouthDump == nil) else {
            throw ProofError.arguments(Self.usage)
        }
    }
}

private enum ProofError: LocalizedError {
    case arguments(String)
    var errorDescription: String? {
        switch self { case .arguments(let message): return message }
    }
}

private struct Receipt: Encodable {
    let schemaVersion = 1
    let startedAt = Date()
    let command: String
    let modelDisplayName = LipRuntime.modelDisplayName
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    var status = "running"
    var modelDirectory: String?
    var videoPath: String?
    var videoSHA256: String?
    var durationSeconds: Double?
    var frameCount: Int?
    var tensorShape: [Int]?
    var mouthDumpPath: String?
    var mouthDumpSHA256: String?
    var mouthDumpEncoding: String?
    var text: String?
    var downloadBytes: Int64?
    var installedBytes: Int64?
    var requiredTemporaryFreeBytes: Int64?
    var timingsSeconds: [String: Double] = [:]
    var errorType: String?
    var errorCode: String?
    var errorMessage: String?
    var errorDetails: String?
    var errorFrame: Int?
    var errorPresentationTime: Double?
}

@main private struct LipDictationProof {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print(Options.usage)
            return
        }
        do {
            let options = try Options(arguments)
            let succeeded = try await execute(options)
            if !succeeded { exit(1) }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(2)
        }
    }

    private static func execute(_ options: Options) async throws -> Bool {
        var receipt = Receipt(command: options.command)
        receipt.modelDirectory = options.modelDirectory?.path
        receipt.videoPath = options.video?.path
        let start = ProcessInfo.processInfo.systemUptime
        do {
            if options.command == "install", let directory = options.modelDirectory {
                let runtime = LipRuntime(directory: directory)
                let bytes = try await runtime.installationBytes()
                receipt.downloadBytes = bytes.download
                receipt.installedBytes = bytes.installed
                receipt.requiredTemporaryFreeBytes = bytes.temporaryFreeSpace
                let installStart = ProcessInfo.processInfo.systemUptime
                try await runtime.install()
                receipt.timingsSeconds["install"] = elapsed(since: installStart)
            } else if let video = options.video {
                receipt.videoSHA256 = try hash(video)
                let preprocessStart = ProcessInfo.processInfo.systemUptime
                let mouth = try await MouthVideoProcessor.process(videoURL: video)
                receipt.timingsSeconds["nativePreprocessing"] = elapsed(since: preprocessStart)
                receipt.durationSeconds = mouth.duration
                receipt.frameCount = mouth.frameCount
                receipt.tensorShape = [1, mouth.frameCount, 88, 88]
                if let dump = options.mouthDump {
                    let data = mouth.values.withUnsafeBytes { Data($0) }
                    try createParent(of: dump)
                    try data.write(to: dump, options: .atomic)
                    receipt.mouthDumpPath = dump.path
                    receipt.mouthDumpSHA256 = hexadecimal(SHA256.hash(data: data))
                    receipt.mouthDumpEncoding = "float32-le"
                }
                if options.command == "infer", let directory = options.modelDirectory {
                    let inferenceStart = ProcessInfo.processInfo.systemUptime
                    receipt.text = try await LipRuntime(directory: directory).transcribe(mouth: mouth)
                    receipt.timingsSeconds["verifiedModelAndNativeInference"] = elapsed(since: inferenceStart)
                }
            }
            receipt.status = "success"
        } catch {
            receipt.status = error is CancellationError ? "cancelled" : "error"
            receipt.errorType = String(reflecting: type(of: error))
            receipt.errorCode = errorCode(for: error)
            receipt.errorMessage = error.localizedDescription
            receipt.errorDetails = String(reflecting: error)
            if let error = error as? MouthVideoProcessingError {
                switch error {
                case .missingFace(let frame, let presentationTime):
                    receipt.errorFrame = frame
                    receipt.errorPresentationTime = presentationTime
                case .multipleFaces(let frame): receipt.errorFrame = frame
                default: break
                }
            }
        }
        receipt.timingsSeconds["total"] = elapsed(since: start)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(receipt)
        data.append(0x0a)
        if let destination = options.receipt {
            try createParent(of: destination)
            try data.write(to: destination, options: .atomic)
        }
        FileHandle.standardOutput.write(data)
        return receipt.status == "success"
    }

    private static func elapsed(since start: TimeInterval) -> Double {
        ProcessInfo.processInfo.systemUptime - start
    }

    private static func errorCode(for error: Error) -> String? {
        if let error = error as? MouthVideoProcessingError {
            switch error {
            case .missingFace: return "mouthVideo.missingFace"
            case .multipleFaces: return "mouthVideo.multipleFaces"
            default: return "mouthVideo.processingFailure"
            }
        }
        guard let error = error as? LipRuntimeError else { return nil }
        switch error {
        case .alreadyRecognizing: return "lipRuntime.alreadyRecognizing"
        case .noSpeech: return "lipRuntime.noSpeech"
        case .unclearSpeech: return "lipRuntime.unclearSpeech"
        case .missingVocabulary: return "lipRuntime.missingVocabulary"
        }
    }

    private static func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return hexadecimal(hash.finalize())
    }

    private static func hexadecimal<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
