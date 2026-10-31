import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO

// Public-fixture diagnostic only. Uses the processor's exact AVAssetReader output settings.
@main private enum LipVideoFrameProbe {
    private enum ProbeError: Error { case noSingleVideoTrack, unsupportedPixels, cannotRead, cannotEncodePNG }

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 || arguments.count == 3,
              let limit = arguments.count == 3 ? Int(arguments[2]) : 3, (1...5).contains(limit) else {
            FileHandle.standardError.write(Data("Usage: LipVideoFrameProbe <video-path> <output-directory> [frame-limit 1...5]\n".utf8))
            exit(64)
        }
        do {
            let video = URL(fileURLWithPath: arguments[0])
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let report = try await inspect(video, directory: directory, limit: limit)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("reader.json"), options: .atomic)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data((String(reflecting: error) + "\n" + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func inspect(_ video: URL, directory: URL, limit: Int) async throws -> [String: Any] {
        let asset = AVURLAsset(url: video)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else { throw ProbeError.noSingleVideoTrack }
        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let timeRange = try await track.load(.timeRange)
        let formats = try await track.load(.formatDescriptions)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let segments = try await track.load(.segments)
        let unbounded = try snapshots(asset: asset, track: track, range: nil, directory: directory, limit: limit)
        let mediaRanges = segments.filter { !$0.isEmpty }.map { $0.timeMapping.target }
        var bounded: [String: Any] = ["status": "noNonemptyMedia"]
        if let start = mediaRanges.map(\.start).min(by: { CMTimeCompare($0, $1) < 0 }),
           let end = mediaRanges.map({ CMTimeRangeGetEnd($0) }).max(by: { CMTimeCompare($0, $1) < 0 }) {
            let range = CMTimeRange(start: start, end: end)
            bounded = ["selectedTimeRange": rangeJSON(range), "outputDirectory": "bounded-media"]
            do {
                let target = directory.appendingPathComponent("bounded-media", isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let result = try snapshots(asset: asset, track: track, range: range, directory: target, limit: 1)
                bounded["status"] = "success"
                bounded["samples"] = result.samples
                bounded["readerStatusAfterSnapshots"] = result.status
            } catch {
                bounded["status"] = "error"
                bounded["errorDetails"] = String(reflecting: error)
            }
        }
        return [
            "schemaVersion": 1,
            "input": video.lastPathComponent,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "probe": "AVAssetReader BGRA snapshot before any Vision call; no audio tracks requested",
            "requestedPixelFormat": fourCC(kCVPixelFormatType_32BGRA),
            "alwaysCopiesSampleData": false,
            "naturalSize": [naturalSize.width, naturalSize.height],
            "preferredTransform": [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty],
            "nominalFrameRate": nominalFrameRate,
            "trackTimeRange": rangeJSON(timeRange),
            "segments": segments.map { ["isEmpty": $0.isEmpty, "source": rangeJSON($0.timeMapping.source),
                                        "target": rangeJSON($0.timeMapping.target)] },
            "formatDescriptions": formats.map { description -> [String: Any] in
                let size = CMVideoFormatDescriptionGetDimensions(description)
                return ["codec": fourCC(CMFormatDescriptionGetMediaSubType(description)),
                        "width": size.width, "height": size.height,
                        "extensions": jsonSafe(CMFormatDescriptionGetExtensions(description))]
            },
            "readerStatusAfterSnapshots": unbounded.status,
            "samples": unbounded.samples,
            "boundedMediaRead": bounded
        ]
    }

    private static func snapshots(
        asset: AVAsset, track: AVAssetTrack, range: CMTimeRange?, directory: URL, limit: Int
    ) throws -> (samples: [[String: Any]], status: Int) {
        let reader = try AVAssetReader(asset: asset)
        defer { reader.cancelReading() }
        if let range { reader.timeRange = range }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProbeError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProbeError.cannotRead }
        var samples: [[String: Any]] = []
        for index in 0..<limit {
            try Task.checkCancellation()
            guard let sample = output.copyNextSampleBuffer() else {
                guard reader.status == .completed else { throw reader.error ?? ProbeError.cannotRead }
                break
            }
            samples.append(try autoreleasepool { try snapshot(sample, index: index, directory: directory) })
        }
        return (samples, reader.status.rawValue)
    }

    private static func snapshot(_ sample: CMSampleBuffer, index: Int, directory: URL) throws -> [String: Any] {
        guard let pixels = CMSampleBufferGetImageBuffer(sample),
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else {
            throw ProbeError.unsupportedPixels
        }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        guard width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 4096 * 2160,
              stride >= width * 4,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else {
            throw ProbeError.unsupportedPixels
        }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else {
            throw ProbeError.unsupportedPixels
        }
        var packed = Data(capacity: width * height * 4)
        var minimum = [UInt8](repeating: 255, count: 4)
        var maximum = [UInt8](repeating: 0, count: 4)
        var totals = [UInt64](repeating: 0, count: 4)
        var nonBlackRGB = 0, zeroAlpha = 0
        for y in 0..<height {
            let row = base.advanced(by: y * stride)
            // Padding bytes are outside the image and can contain uninitialized memory.
            packed.append(row, count: width * 4)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                if pixel[0] != 0 || pixel[1] != 0 || pixel[2] != 0 { nonBlackRGB += 1 }
                if pixel[3] == 0 { zeroAlpha += 1 }
                for channel in 0..<4 {
                    minimum[channel] = min(minimum[channel], pixel[channel])
                    maximum[channel] = max(maximum[channel], pixel[channel])
                    totals[channel] += UInt64(pixel[channel])
                }
            }
        }
        let stem = String(format: "frame-%04d", index)
        try packed.write(to: directory.appendingPathComponent(stem + ".bgra"), options: .atomic)
        try png(packed, width: width, height: height, alpha: .premultipliedFirst,
                to: directory.appendingPathComponent(stem + "-alpha.png"))
        try png(packed, width: width, height: height, alpha: .noneSkipFirst,
                to: directory.appendingPathComponent(stem + "-opaque.png"))
        let landmarks = [("topLeft", 0, 0), ("topRight", width - 1, 0),
                         ("center", width / 2, height / 2), ("bottomLeft", 0, height - 1),
                         ("bottomRight", width - 1, height - 1)]
        var pixelSamples: [String: [UInt8]] = [:]
        for (name, x, y) in landmarks {
            let pixel = base.advanced(by: y * stride + x * 4)
            pixelSamples[name] = Array(UnsafeBufferPointer(start: pixel, count: 4))
        }
        return [
            "sourceFrame": index,
            "presentationTime": time(CMSampleBufferGetPresentationTimeStamp(sample)),
            "decodeTime": time(CMSampleBufferGetDecodeTimeStamp(sample)),
            "sampleDuration": time(CMSampleBufferGetDuration(sample)),
            "outputPresentationTime": time(CMSampleBufferGetOutputPresentationTimeStamp(sample)),
            "outputDecodeTime": time(CMSampleBufferGetOutputDecodeTimeStamp(sample)),
            "outputDuration": time(CMSampleBufferGetOutputDuration(sample)),
            "sampleCount": CMSampleBufferGetNumSamples(sample),
            "sampleIsValid": CMSampleBufferIsValid(sample),
            "sampleDataIsReady": CMSampleBufferDataIsReady(sample),
            "sampleAttachments": jsonSafe(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)),
            "propagatingSampleAttachments": jsonSafe(CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault, target: sample, attachmentMode: kCMAttachmentMode_ShouldPropagate)),
            "nonpropagatingSampleAttachments": jsonSafe(CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault, target: sample, attachmentMode: kCMAttachmentMode_ShouldNotPropagate)),
            "pixelAttachments": jsonSafe(CVBufferCopyAttachments(pixels, .shouldPropagate)),
            "pixelFormat": fourCC(CVPixelBufferGetPixelFormatType(pixels)),
            "width": width, "height": height, "nativeBytesPerRow": stride,
            "isPlanar": CVPixelBufferIsPlanar(pixels),
            "packedBytesPerRow": width * 4, "packedByteCount": packed.count,
            "packedBGRASHA256": SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined(),
            "channelOrder": ["B", "G", "R", "A"], "channelMin": minimum, "channelMax": maximum,
            "channelMean": totals.map { Double($0) / Double(width * height) },
            "nonBlackRGBPixels": nonBlackRGB, "zeroAlphaPixels": zeroAlpha,
            "pixelSamplesBGRA": pixelSamples,
            "packedBGRAFile": stem + ".bgra", "alphaPNG": stem + "-alpha.png", "opaquePNG": stem + "-opaque.png"
        ]
    }

    private static func png(_ data: Data, width: Int, height: Int, alpha: CGImageAlphaInfo, to url: URL) throws {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue).union(.byteOrder32Little),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ProbeError.cannotEncodePNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ProbeError.cannotEncodePNG }
    }

    private static func time(_ time: CMTime) -> [String: Any] {
        let seconds = CMTimeGetSeconds(time)
        return ["value": time.value, "timescale": time.timescale, "epoch": time.epoch,
                "flags": time.flags.rawValue, "seconds": seconds.isFinite ? seconds as Any : NSNull()]
    }

    private static func rangeJSON(_ range: CMTimeRange) -> [String: Any] {
        ["start": time(range.start), "duration": time(range.duration), "end": time(CMTimeRangeGetEnd(range))]
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
        return String(bytes: bytes, encoding: .ascii) ?? String(code)
    }

    private static func jsonSafe(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        if let dictionary = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, item) in dictionary { result[String(describing: key)] = jsonSafe(item) }
            return result
        }
        if let array = value as? NSArray { return array.map { jsonSafe($0) } }
        if let data = value as? Data { return ["base64": data.base64EncodedString(), "byteCount": data.count] }
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? number as Any : number.stringValue }
        if let string = value as? String { return string }
        if value is NSNull { return NSNull() }
        return String(describing: value).prefix(2048).description
    }
}
