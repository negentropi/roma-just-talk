import Darwin
import Foundation
import VoiceInkCore

struct AudioProofOptions {
    var inputURLs: [URL] = []
    var outputDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("voiceink-audio-proof", isDirectory: true)
    var targetPeak: Int16 = 12_000
    var noiseFloorPeak: Int16 = 32
    var maxGain: Float = 16
}

struct AudioMetrics {
    let samples: Int
    let peak: Int
    let rmsDecibels: Double

    var duration: TimeInterval {
        TimeInterval(samples) / VoiceInkPCM16Audio.mono16kSampleRate
    }
}

@main
enum VoiceInkAudioProof {
    static func main() {
        do {
            let options = try parseOptions()
            guard !options.inputURLs.isEmpty else {
                printUsage()
                exit(2)
            }

            try FileManager.default.createDirectory(
                at: options.outputDirectory,
                withIntermediateDirectories: true
            )

            print("variant\tpath\tduration_seconds\tpeak\trms_dbfs\toutput")
            for inputURL in options.inputURLs {
                try analyze(inputURL, options: options)
            }
        } catch {
            fputs("VoiceInkAudioProof: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions() throws -> AudioProofOptions {
        var options = AudioProofOptions()
        var arguments = Array(CommandLine.arguments.dropFirst())

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--output-dir":
                options.outputDirectory = URL(fileURLWithPath: try takeValue(after: argument, from: &arguments), isDirectory: true)
            case "--target-peak":
                options.targetPeak = try int16Option(argument, from: &arguments)
            case "--noise-floor":
                options.noiseFloorPeak = try int16Option(argument, from: &arguments)
            case "--max-gain":
                options.maxGain = try floatOption(argument, from: &arguments)
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                options.inputURLs.append(URL(fileURLWithPath: argument))
            }
        }

        return options
    }

    private static func takeValue(after option: String, from arguments: inout [String]) throws -> String {
        guard !arguments.isEmpty else {
            throw AudioProofError.missingOptionValue(option)
        }
        return arguments.removeFirst()
    }

    private static func int16Option(_ option: String, from arguments: inout [String]) throws -> Int16 {
        let value = try takeValue(after: option, from: &arguments)
        guard let parsed = Int(value), parsed >= 0, parsed <= Int(Int16.max) else {
            throw AudioProofError.invalidOptionValue(option, value)
        }
        return Int16(parsed)
    }

    private static func floatOption(_ option: String, from arguments: inout [String]) throws -> Float {
        let value = try takeValue(after: option, from: &arguments)
        guard let parsed = Float(value), parsed.isFinite, parsed > 0 else {
            throw AudioProofError.invalidOptionValue(option, value)
        }
        return parsed
    }

    private static func analyze(_ inputURL: URL, options: AudioProofOptions) throws {
        let inputData = try Data(contentsOf: inputURL)
        guard inputData.count > VoiceInkPCM16Audio.wavHeaderByteCount else {
            throw AudioProofError.invalidWAV(inputURL.path)
        }

        let header = inputData.prefix(VoiceInkPCM16Audio.wavHeaderByteCount)
        let rawPCMData = Data(inputData.dropFirst(VoiceInkPCM16Audio.wavHeaderByteCount))
        let rawMetrics = metrics(forLittleEndianPCM16Data: rawPCMData)
        printRow(
            variant: "raw",
            path: inputURL.path,
            metrics: rawMetrics,
            outputPath: ""
        )

        var levelCandidates: [(variant: String, pcmData: Data)] = [("raw", rawPCMData)]
        for variant in VoiceInkPCM16AudioProofVariant.allCases {
            let variantPCMData = VoiceInkPCM16Audio.proofVariantLittleEndianData(
                rawPCMData,
                variant: variant
            )
            let variantURL = outputURL(for: inputURL, suffix: variant.rawValue, options: options)
            try writeWAV(header: header, pcmData: variantPCMData, to: variantURL)
            levelCandidates.append((variant.rawValue, variantPCMData))
            printRow(
                variant: variant.rawValue,
                path: inputURL.path,
                metrics: metrics(forLittleEndianPCM16Data: variantPCMData),
                outputPath: variantURL.path
            )
        }

        for candidate in levelCandidates {
            let leveledPCMData = VoiceInkPCM16Audio.leveledLittleEndianData(
                candidate.pcmData,
                targetPeak: options.targetPeak,
                noiseFloorPeak: options.noiseFloorPeak,
                maxGain: options.maxGain
            )

            let suffix = candidate.variant == "raw"
                ? "leveled"
                : candidate.variant + ".leveled"
            let leveledURL = outputURL(for: inputURL, suffix: suffix, options: options)
            try writeWAV(header: header, pcmData: leveledPCMData, to: leveledURL)
            printRow(
                variant: suffix,
                path: inputURL.path,
                metrics: metrics(forLittleEndianPCM16Data: leveledPCMData),
                outputPath: leveledURL.path
            )
        }
    }

    private static func outputURL(
        for inputURL: URL,
        suffix: String,
        options: AudioProofOptions
    ) -> URL {
        options.outputDirectory
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "." + suffix + ".wav")
    }

    private static func writeWAV(header: Data.SubSequence, pcmData: Data, to url: URL) throws {
        var wavData = Data(header)
        wavData.append(pcmData)
        try wavData.write(to: url, options: .atomic)
    }

    private static func metrics(forLittleEndianPCM16Data data: Data) -> AudioMetrics {
        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)
        guard !samples.isEmpty else {
            return AudioMetrics(samples: 0, peak: 0, rmsDecibels: -Double.infinity)
        }

        var peak: Float = 0
        var sumSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            peak = max(peak, magnitude)
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(samples.count))
        let rmsDecibels = 20 * log10(Double(max(rms, 0.000_001)))
        return AudioMetrics(samples: samples.count, peak: Int((peak * Float(Int16.max)).rounded()), rmsDecibels: rmsDecibels)
    }

    private static func printRow(
        variant: String,
        path: String,
        metrics: AudioMetrics,
        outputPath: String
    ) {
        print(
            [
                variant,
                path,
                String(format: "%.3f", metrics.duration),
                String(metrics.peak),
                String(format: "%.2f", metrics.rmsDecibels),
                outputPath
            ].joined(separator: "\t")
        )
    }

    private static func printUsage() {
        print("""
        Usage: VoiceInkAudioProof [options] <voiceink-wav> [...]

        Options:
          --output-dir <path>    Directory for derived WAV variants.
          --target-peak <int>    PCM16 peak target for the leveled variant. Default: 12000.
          --noise-floor <int>    PCM16 peak below which audio is left unchanged. Default: 32.
          --max-gain <float>     Maximum boost multiplier. Default: 16.
        """)
    }
}

enum AudioProofError: Error, CustomStringConvertible {
    case missingOptionValue(String)
    case invalidOptionValue(String, String)
    case invalidWAV(String)

    var description: String {
        switch self {
        case .missingOptionValue(let option):
            return "missing value for \(option)"
        case .invalidOptionValue(let option, let value):
            return "invalid value for \(option): \(value)"
        case .invalidWAV(let path):
            return "expected a WAV with at least a 44-byte header: \(path)"
        }
    }
}
