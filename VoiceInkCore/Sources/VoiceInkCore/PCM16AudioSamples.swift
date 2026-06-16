import Foundation

public enum VoiceInkPCM16Audio {
    public static let wavHeaderByteCount = 44

    public static func floatSamples(fromLittleEndianData data: Data, startingAt startByteOffset: Int = 0) -> [Float] {
        guard startByteOffset >= 0 else { return [] }
        let readableByteCount = data.count - startByteOffset
        guard readableByteCount >= MemoryLayout<Int16>.size else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return [] }

            let sampleCount = readableByteCount / MemoryLayout<Int16>.size
            var samples: [Float] = []
            samples.reserveCapacity(sampleCount)

            for sampleIndex in 0..<sampleCount {
                let byteIndex = startByteOffset + sampleIndex * MemoryLayout<Int16>.size
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                let sample = Int16(bitPattern: rawValue)
                samples.append(max(-1.0, min(Float(sample) / 32767.0, 1.0)))
            }

            return samples
        }
    }

    public static func floatSamples(fromWAVData data: Data) -> [Float]? {
        guard data.count > wavHeaderByteCount else { return nil }
        return floatSamples(fromLittleEndianData: data, startingAt: wavHeaderByteCount)
    }
}
