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

private enum AudioProofVariant: String, CaseIterable {
    case lowVolume = "low_volume"
    case noisy
    case lowVolumeNoisy = "low_volume_noisy"
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
        for variant in AudioProofVariant.allCases {
            let variantPCMData = proofVariantLittleEndianData(
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

    private static func proofVariantLittleEndianData(
        _ data: Data,
        variant: AudioProofVariant
    ) -> Data {
        switch variant {
        case .lowVolume:
            return scaledLittleEndianData(data, gain: 0.25)
        case .noisy:
            return dataWithAlternatingNoise(data, amplitude: 256)
        case .lowVolumeNoisy:
            return dataWithAlternatingNoise(
                scaledLittleEndianData(data, gain: 0.25),
                amplitude: 256
            )
        }
    }

    private static func scaledLittleEndianData(_ data: Data, gain: Float) -> Data {
        transformLittleEndianData(data) { sample, _ in
            pcm16SampleFromScaledInt16(sample, gain: gain)
        }
    }

    private static func dataWithAlternatingNoise(_ data: Data, amplitude: Int16) -> Data {
        transformLittleEndianData(data) { sample, index in
            let noise = index.isMultiple(of: 2) ? amplitude : -amplitude
            let mixed = Int(sample) + Int(noise)
            return Int16(max(Int(Int16.min), min(Int(Int16.max), mixed)))
        }
    }

    private static func transformLittleEndianData(
        _ data: Data,
        transform: (_ sample: Int16, _ sampleIndex: Int) -> Int16
    ) -> Data {
        let sampleByteCount = data.count - (data.count % VoiceInkPCM16Audio.bytesPerSample)
        guard sampleByteCount >= VoiceInkPCM16Audio.bytesPerSample else { return data }

        var output = Data()
        output.reserveCapacity(data.count)
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }

            var sampleIndex = 0
            for byteIndex in stride(from: 0, to: sampleByteCount, by: VoiceInkPCM16Audio.bytesPerSample) {
                let sample = littleEndianPCM16Sample(bytes: bytes, byteIndex: byteIndex)
                let transformed = transform(sample, sampleIndex)
                let littleEndian = transformed.littleEndian
                output.append(UInt8(truncatingIfNeeded: littleEndian))
                output.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
                sampleIndex += 1
            }
        }

        if sampleByteCount < data.count {
            output.append(data.subdata(in: sampleByteCount..<data.count))
        }

        return output
    }

    private static func littleEndianPCM16Sample(bytes: UnsafePointer<UInt8>, byteIndex: Int) -> Int16 {
        let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
        return Int16(bitPattern: rawValue)
    }

    private static func pcm16SampleFromScaledInt16(_ sample: Int16, gain: Float) -> Int16 {
        let scaled = (Float(sample) * gain).rounded()
        let clipped = max(-32768.0, min(32767.0, scaled))
        return Int16(clipped)
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
