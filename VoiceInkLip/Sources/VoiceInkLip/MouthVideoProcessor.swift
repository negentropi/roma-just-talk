import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

public struct MouthVideoFrames: Sendable {
    /// Contiguous Float32 values in [1, T, 88, 88] order at 25 frames per second.
    public let values: [Float]
    public let frameCount: Int
    public let duration: TimeInterval
}

public enum MouthVideoProcessingError: LocalizedError {
    case noVideo, emptyVideo, unsupportedVideo, invalidTiming, decodingFailed
    case clipTooLong, missingAlignmentResource
    case missingFace(frame: Int, presentationTime: TimeInterval)
    case multipleFaces(frame: Int)
    case landmarksUnavailable(frame: Int), invalidAlignment(frame: Int)

    public var errorDescription: String? {
        switch self {
        case .noVideo, .emptyVideo:
            return "No camera video was recorded. Try recording again."
        case .unsupportedVideo, .invalidTiming, .decodingFailed:
            return "The camera video could not be processed. Try recording again."
        case .clipTooLong:
            return "Lip dictation supports recordings up to 60 seconds. Record a shorter phrase."
        case .missingAlignmentResource:
            return "The lip dictation alignment resource is missing or invalid. Reinstall the app."
        case .missingFace:
            return "Keep your face visible to the camera throughout lip dictation."
        case .multipleFaces:
            return "Lip dictation needs exactly one face in the camera view."
        case .landmarksUnavailable, .invalidAlignment:
            return "The camera could not locate your mouth reliably. Face the camera in good light and try again."
        }
    }
}

public enum MouthVideoProcessor {
    /// Reads only the video track. Vision is a different detector from RAVEn's
    /// reference detector; matching crop geometry does not establish model parity.
    public static func process(videoURL: URL) async throws -> MouthVideoFrames {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else {
            throw MouthVideoProcessingError.noVideo
        }
        let (preferredTransform, timeRange) = try await (
            track.load(.preferredTransform), track.load(.timeRange)
        )
        let reference = try AlignmentReference.load()
        let firstPass = try VideoFrameReader(asset: asset, track: track)
        defer { firstPass.cancel() }
        guard var previous = try firstPass.next() else { throw MouthVideoProcessingError.emptyVideo }
        let geometry = try VideoGeometry(
            width: CVPixelBufferGetWidth(previous.pixels),
            height: CVPixelBufferGetHeight(previous.pixels), transform: preferredTransform
        )
        let duration = CMTimeGetSeconds(CMTimeRangeGetEnd(timeRange)) - previous.time
        var schedule = try MouthFrameSchedule(start: previous.time, duration: duration)
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        faceRequest.preferBackgroundProcessing = true
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        request.constellation = .constellation76Points
        request.preferBackgroundProcessing = true

        var observations: [MouthObservation] = []
        observations.reserveCapacity(schedule.frameCount)
        var lastObservation: MouthObservation?
        func append(_ sample: VideoFrame) throws {
            try Task.checkCancellation()
            if lastObservation?.sourceFrame != sample.index {
                lastObservation = try autoreleasepool {
                    try detect(sample, geometry: geometry, faceRequest: faceRequest, request: request)
                }
            }
            observations.append(lastObservation!)
        }

        while let next = try firstPass.next() {
            for sourceIndex in try schedule.consume(
                previousIndex: previous.index, previousTime: previous.time,
                nextIndex: next.index, nextTime: next.time
            ) {
                try append(sourceIndex == previous.index ? previous : next)
            }
            previous = next
        }
        for _ in schedule.finish(lastIndex: previous.index) { try append(previous) }

        let secondPass = try VideoFrameReader(asset: asset, track: track)
        defer { secondPass.cancel() }
        var values: [Float] = []
        values.reserveCapacity(observations.count * MouthGeometry.outputSize * MouthGeometry.outputSize)
        var outputIndex = 0
        while outputIndex < observations.count, let sample = try secondPass.next() {
            while outputIndex < observations.count, observations[outputIndex].sourceFrame == sample.index {
                try Task.checkCancellation()
                guard abs(sample.time - observations[outputIndex].time) < 0.000_001,
                      CVPixelBufferGetWidth(sample.pixels) == geometry.rawWidth,
                      CVPixelBufferGetHeight(sample.pixels) == geometry.rawHeight else {
                    throw MouthVideoProcessingError.decodingFailed
                }
                let smoothed = MouthGeometry.smoothed(observations, at: outputIndex)
                let alignment: MouthSimilarity
                do {
                    alignment = try MouthGeometry.align(smoothed.anchors, to: reference.anchors)
                } catch {
                    throw MouthVideoProcessingError.invalidAlignment(frame: outputIndex)
                }
                guard CVPixelBufferLockBaseAddress(sample.pixels, .readOnly) == kCVReturnSuccess else {
                    throw MouthVideoProcessingError.decodingFailed
                }
                defer { CVPixelBufferUnlockBaseAddress(sample.pixels, .readOnly) }
                guard let address = CVPixelBufferGetBaseAddress(sample.pixels) else {
                    throw MouthVideoProcessingError.decodingFailed
                }
                values.append(contentsOf: MouthGeometry.normalizedCrop(
                    bgra: address.assumingMemoryBound(to: UInt8.self),
                    width: geometry.rawWidth, height: geometry.rawHeight,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(sample.pixels),
                    geometry: geometry, alignment: alignment, mouthCenter: smoothed.mouthCenter
                ))
                outputIndex += 1
            }
        }
        guard outputIndex == observations.count else { throw MouthVideoProcessingError.decodingFailed }
        try Task.checkCancellation()
        return MouthVideoFrames(values: values, frameCount: observations.count, duration: duration)
    }

    private static func detect(
        _ sample: VideoFrame, geometry: VideoGeometry,
        faceRequest: VNDetectFaceRectanglesRequest, request: VNDetectFaceLandmarksRequest
    ) throws -> MouthObservation {
        guard CVPixelBufferGetWidth(sample.pixels) == geometry.rawWidth,
              CVPixelBufferGetHeight(sample.pixels) == geometry.rawHeight else {
            throw MouthVideoProcessingError.unsupportedVideo
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: sample.pixels, orientation: geometry.orientation)
        try handler.perform([faceRequest])
        try Task.checkCancellation()
        let faces = faceRequest.results ?? []
        guard !faces.isEmpty else {
            throw MouthVideoProcessingError.missingFace(frame: sample.index, presentationTime: sample.time)
        }
        guard faces.count == 1 else { throw MouthVideoProcessingError.multipleFaces(frame: sample.index) }
        // Rectangle observations contain no old landmarks, so Vision must compute this frame's points.
        request.inputFaceObservations = faces
        defer { request.inputFaceObservations = nil }
        try handler.perform([request])
        try Task.checkCancellation()
        guard let face = request.results?.first, request.results?.count == 1,
              face.confidence >= 0.5, let landmarks = face.landmarks else {
            throw MouthVideoProcessingError.landmarksUnavailable(frame: sample.index)
        }
        func points(_ region: VNFaceLandmarkRegion2D?, minimum: Int) throws -> [CGPoint] {
            guard let region, region.pointCount >= minimum else {
                throw MouthVideoProcessingError.landmarksUnavailable(frame: sample.index)
            }
            let points = region.normalizedPoints.map { point in
                CGPoint(
                    x: (face.boundingBox.minX + point.x * face.boundingBox.width) * CGFloat(geometry.width),
                    y: (1 - face.boundingBox.minY - point.y * face.boundingBox.height) * CGFloat(geometry.height)
                )
            }
            guard points.allSatisfy({
                $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
                    && $0.x < CGFloat(geometry.width) && $0.y < CGFloat(geometry.height)
            }) else { throw MouthVideoProcessingError.landmarksUnavailable(frame: sample.index) }
            return points
        }
        let all = try points(landmarks.allPoints, minimum: 60)
        let eyes = try [points(landmarks.leftEye, minimum: 4), points(landmarks.rightEye, minimum: 4)]
            .sorted { MouthGeometry.mean($0).x < MouthGeometry.mean($1).x }
        let crest = try points(landmarks.noseCrest, minimum: 3).sorted { $0.y < $1.y }
        let nose = try points(landmarks.nose, minimum: 3)
        let outer = try points(landmarks.outerLips, minimum: 8)
        let inner = try points(landmarks.innerLips, minimum: 4)
        func left(_ points: [CGPoint]) -> CGPoint { points.min { $0.x < $1.x }! }
        func right(_ points: [CGPoint]) -> CGPoint { points.max { $0.x < $1.x }! }
        guard right(eyes[0]).x - left(eyes[0]).x >= 3,
              right(eyes[1]).x - left(eyes[1]).x >= 3,
              right(outer).x - left(outer).x >= 4 else {
            throw MouthVideoProcessingError.landmarksUnavailable(frame: sample.index)
        }
        // Vision's crest and lip topology differ from the 68-point training detector.
        let bridgePosition = Double(crest.count - 1) / 3
        let bridgeIndex = Int(bridgePosition)
        let bridge = MouthGeometry.interpolate(
            crest[bridgeIndex], crest[min(bridgeIndex + 1, crest.count - 1)], fraction: bridgePosition - Double(bridgeIndex)
        )
        return MouthObservation(
            sourceFrame: sample.index, time: sample.time,
            anchors: [bridge, nose.max { $0.y < $1.y }!, left(eyes[0]), right(eyes[0]),
                      left(eyes[1]), right(eyes[1]), left(outer), right(outer)],
            mouthCenter: MouthGeometry.mean(outer + inner), centroid: MouthGeometry.mean(all)
        )
    }
}

private struct AlignmentReference: Decodable {
    let points: [[Double]]
    let stablePoints: [Int]
    enum CodingKeys: String, CodingKey { case points; case stablePoints = "stable_points" }

    var anchors: [CGPoint] { stablePoints.map { CGPoint(x: points[$0][0], y: points[$0][1]) } }

    static func load() throws -> AlignmentReference {
        guard let url = Bundle.module.url(forResource: "face-alignment", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let reference = try? JSONDecoder().decode(Self.self, from: data),
              reference.stablePoints == [28, 33, 36, 39, 42, 45, 48, 54],
              reference.points.count == 68,
              reference.points.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 256 } }) else {
            throw MouthVideoProcessingError.missingAlignmentResource
        }
        return reference
    }
}

private struct VideoFrame {
    let index: Int
    let time: Double
    let pixels: CVPixelBuffer
}

private final class VideoFrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var nextIndex = 0

    init(asset: AVAsset, track: AVAssetTrack) throws {
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MouthVideoProcessingError.unsupportedVideo }
        reader.add(output)
        guard reader.startReading() else { throw MouthVideoProcessingError.decodingFailed }
    }

    func next() throws -> VideoFrame? {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let sample = output.copyNextSampleBuffer() else {
                guard reader.status == .completed else { throw MouthVideoProcessingError.decodingFailed }
                return nil
            }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            guard time.isFinite, let pixels = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
                  nextIndex < 18_000 else { throw MouthVideoProcessingError.unsupportedVideo }
            defer { nextIndex += 1 }
            return VideoFrame(index: nextIndex, time: time, pixels: pixels)
        }
    }

    func cancel() { reader.cancelReading() }
}

struct VideoGeometry {
    let rawWidth: Int
    let rawHeight: Int
    let width: Int
    let height: Int
    let orientation: CGImagePropertyOrientation
    private let displayToRaw: CGAffineTransform

    init(width: Int, height: Int, transform: CGAffineTransform) throws {
        guard width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 4096 * 2160,
              [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite) else {
            throw MouthVideoProcessingError.unsupportedVideo
        }
        let components = [transform.a, transform.b, transform.c, transform.d]
        guard components.allSatisfy({ abs($0) <= 1.000_1 }) else {
            throw MouthVideoProcessingError.unsupportedVideo
        }
        let axes = components.map { Int($0.rounded()) }
        guard zip([transform.a, transform.b, transform.c, transform.d], axes)
            .allSatisfy({ abs($0.0 - CGFloat($0.1)) < 0.000_1 }) else {
            throw MouthVideoProcessingError.unsupportedVideo
        }
        switch axes {
        case [1, 0, 0, 1]: orientation = .up
        case [-1, 0, 0, -1]: orientation = .down
        case [0, 1, -1, 0]: orientation = .right
        case [0, -1, 1, 0]: orientation = .left
        case [-1, 0, 0, 1]: orientation = .upMirrored
        case [1, 0, 0, -1]: orientation = .downMirrored
        case [0, 1, 1, 0]: orientation = .leftMirrored
        case [0, -1, -1, 0]: orientation = .rightMirrored
        default: throw MouthVideoProcessingError.unsupportedVideo
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)
        rawWidth = width
        rawHeight = height
        self.width = Int(bounds.width.rounded())
        self.height = Int(bounds.height.rounded())
        // Track transforms act on image edges; warp coordinates denote pixel centers.
        let pixelTransform = CGAffineTransform(
            a: transform.a, b: transform.b, c: transform.c, d: transform.d,
            tx: transform.tx - bounds.minX + (transform.a + transform.c) / 2 - 0.5,
            ty: transform.ty - bounds.minY + (transform.b + transform.d) / 2 - 0.5
        )
        displayToRaw = pixelTransform.inverted()
    }

    func rawPoint(for displayPoint: CGPoint) -> CGPoint { displayPoint.applying(displayToRaw) }
}

struct MouthObservation {
    let sourceFrame: Int
    let time: Double
    let anchors: [CGPoint]
    let mouthCenter: CGPoint
    let centroid: CGPoint
}

struct MouthFrameSchedule {
    private let times: [Double]
    private var cursor = 0
    var frameCount: Int { times.count }

    init(start: Double, duration: Double) throws {
        guard start.isFinite else { throw MouthVideoProcessingError.invalidTiming }
        times = try MouthGeometry.targetTimes(duration: duration).map { $0 + start }
    }

    mutating func consume(
        previousIndex: Int, previousTime: Double, nextIndex: Int, nextTime: Double
    ) throws -> [Int] {
        guard previousTime.isFinite, nextTime.isFinite, nextTime > previousTime else {
            throw MouthVideoProcessingError.invalidTiming
        }
        var selections: [Int] = []
        while cursor < times.count, times[cursor] <= nextTime {
            selections.append(MouthGeometry.chooseEarlier(previous: previousTime, next: nextTime, target: times[cursor])
                ? previousIndex : nextIndex)
            cursor += 1
        }
        return selections
    }

    mutating func finish(lastIndex: Int) -> [Int] {
        defer { cursor = times.count }
        return Array(repeating: lastIndex, count: times.count - cursor)
    }
}

struct MouthSimilarity {
    let a: Double
    let b: Double
    let tx: Double
    let ty: Double

    func applying(_ point: CGPoint) -> CGPoint {
        CGPoint(x: a * point.x - b * point.y + tx, y: b * point.x + a * point.y + ty)
    }

    func inverse(_ point: CGPoint) -> CGPoint {
        let x = point.x - tx, y = point.y - ty, denominator = a * a + b * b
        return CGPoint(x: (a * x + b * y) / denominator, y: (-b * x + a * y) / denominator)
    }
}

enum MouthGeometry {
    static let outputSize = 88

    static func targetTimes(duration: Double) throws -> [Double] {
        guard duration.isFinite, duration > 0 else { throw MouthVideoProcessingError.invalidTiming }
        guard duration <= 60 else { throw MouthVideoProcessingError.clipTooLong }
        let count = Int(ceil(duration * 25 - 0.000_000_1))
        guard count > 0, count <= 1500 else { throw MouthVideoProcessingError.invalidTiming }
        return (0..<count).map { Double($0) / 25 }
    }

    static func chooseEarlier(previous: Double, next: Double, target: Double) -> Bool {
        target - previous <= next - target + 0.000_000_001
    }

    static func mean(_ points: [CGPoint]) -> CGPoint {
        let total = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: total.x / Double(points.count), y: total.y / Double(points.count))
    }

    static func interpolate(_ from: CGPoint, _ to: CGPoint, fraction: Double) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }

    static func smoothed(_ observations: [MouthObservation], at index: Int) -> MouthObservation {
        let radius = min(6, index, observations.count - 1 - index)
        let window = observations[(index - radius)...(index + radius)]
        let current = observations[index]
        let centroid = mean(window.map(\.centroid))
        let correction = CGPoint(x: current.centroid.x - centroid.x, y: current.centroid.y - centroid.y)
        func corrected(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + correction.x, y: point.y + correction.y)
        }
        return MouthObservation(
            sourceFrame: current.sourceFrame, time: current.time,
            anchors: current.anchors.indices.map { point in corrected(mean(window.map { $0.anchors[point] })) },
            mouthCenter: corrected(mean(window.map(\.mouthCenter))), centroid: current.centroid
        )
    }

    static func align(_ source: [CGPoint], to destination: [CGPoint]) throws -> MouthSimilarity {
        guard source.count == destination.count, source.count >= 2,
              (source + destination).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw MouthVideoProcessingError.invalidAlignment(frame: 0)
        }
        func fit(_ indices: [Int]) -> MouthSimilarity? {
            let from = mean(indices.map { source[$0] }), to = mean(indices.map { destination[$0] })
            var denominator = 0.0, dot = 0.0, cross = 0.0
            for index in indices {
                let x = source[index].x - from.x, y = source[index].y - from.y
                let u = destination[index].x - to.x, v = destination[index].y - to.y
                denominator += x * x + y * y
                dot += x * u + y * v
                cross += x * v - y * u
            }
            guard denominator > 0.000_001 else { return nil }
            let a = dot / denominator, b = cross / denominator
            guard a.isFinite, b.isFinite, a * a + b * b > 0.000_001 else { return nil }
            return MouthSimilarity(a: a, b: b, tx: to.x - a * from.x + b * from.y, ty: to.y - b * from.x - a * from.y)
        }
        func errors(_ transform: MouthSimilarity) -> [Double] {
            source.indices.map { index in
                let mapped = transform.applying(source[index])
                return pow(mapped.x - destination[index].x, 2) + pow(mapped.y - destination[index].y, 2)
            }
        }
        // Exhaustive minimal pairs avoid random-state dependence for eight anchors.
        var best: MouthSimilarity?, bestMedian = Double.infinity
        for first in 0..<(source.count - 1) {
            for second in (first + 1)..<source.count {
                guard let candidate = fit([first, second]) else { continue }
                let median = errors(candidate).sorted()[source.count / 2]
                if median < bestMedian { best = candidate; bestMedian = median }
            }
        }
        guard let best else { throw MouthVideoProcessingError.invalidAlignment(frame: 0) }
        let sigma = max(0.001, 2.5 * 1.4826 * (1 + 5 / Double(max(1, source.count - 2))) * sqrt(bestMedian))
        let residuals = errors(best)
        let inliers = source.indices.filter { residuals[$0] <= sigma * sigma }
        guard inliers.count >= max(2, source.count / 2 + 1), let refined = fit(inliers) else {
            throw MouthVideoProcessingError.invalidAlignment(frame: 0)
        }
        return refined
    }

    static func normalizedCrop(
        bgra: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
        geometry: VideoGeometry, alignment: MouthSimilarity, mouthCenter: CGPoint
    ) -> [Float] {
        let center = alignment.applying(mouthCenter)
        let originX = Int(min(208, max(48, center.x)).rounded(.toNearestOrEven)) - 44
        let originY = Int(min(208, max(48, center.y)).rounded(.toNearestOrEven)) - 44
        func channel(_ x: Int, _ y: Int, _ channel: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return Double(bgra[y * bytesPerRow + x * 4 + channel])
        }
        var result = [Float](repeating: 0, count: outputSize * outputSize)
        for y in 0..<outputSize {
            for x in 0..<outputSize {
                let displayPoint = alignment.inverse(CGPoint(x: originX + x, y: originY + y))
                let raw = geometry.rawPoint(for: displayPoint)
                // OpenCV INTER_LINEAR uses a 1/32-pixel interpolation table.
                let sx = (raw.x * 32).rounded(.toNearestOrEven) / 32
                let sy = (raw.y * 32).rounded(.toNearestOrEven) / 32
                let left = Int(floor(sx)), top = Int(floor(sy))
                let dx = sx - Double(left), dy = sy - Double(top)
                func interpolated(_ c: Int) -> Float {
                    let value = channel(left, top, c) * (1 - dx) * (1 - dy)
                        + channel(left + 1, top, c) * dx * (1 - dy)
                        + channel(left, top + 1, c) * (1 - dx) * dy
                        + channel(left + 1, top + 1, c) * dx * dy
                    return Float(floor(value + 0.5)) / 255
                }
                let gray = 0.2989 * interpolated(2) + 0.587 * interpolated(1) + 0.114 * interpolated(0)
                result[y * outputSize + x] = (gray - 0.421) / 0.165
            }
        }
        return result
    }
}
