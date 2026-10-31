import CoreGraphics
import XCTest
@testable import VoiceInkLip

final class MouthGeometryTests: XCTestCase {
    func testSimilarityRecoversRotationScaleAndTranslation() throws {
        let source = points([(0, 0), (2, 0), (0, 2), (2, 2), (1, 0), (0, 1), (3, 2), (2, 3)])
        let reference = points([(10, 20), (10, 24), (6, 20), (6, 24), (10, 22), (8, 20), (6, 26), (4, 24)])
        let transform = try MouthGeometry.align(source, to: reference)

        XCTAssertEqual(transform.a, 0, accuracy: 1e-10)
        XCTAssertEqual(transform.b, 2, accuracy: 1e-10)
        XCTAssertEqual(transform.tx, 10, accuracy: 1e-10)
        XCTAssertEqual(transform.ty, 20, accuracy: 1e-10)
        assertPoint(transform.applying(CGPoint(x: 3, y: 4)), x: 2, y: 26)
        assertPoint(transform.inverse(CGPoint(x: 2, y: 26)), x: 3, y: 4)
    }

    func testLeastMedianFitRejectsOneMisplacedAnchor() throws {
        let source = points([(0, 0), (2, 0), (0, 2), (2, 2), (1, 0), (0, 1), (3, 2), (2, 3)])
        let reference = points([(10, 20), (10, 24), (6, 20), (6, 24), (10, 22), (8, 20), (200, -300), (4, 24)])
        let transform = try MouthGeometry.align(source, to: reference)

        assertPoint(transform.applying(CGPoint(x: 3, y: 4)), x: 2, y: 26)
        assertPoint(transform.applying(CGPoint(x: 3, y: 2)), x: 6, y: 26)
    }

    func testDegenerateAndNonfiniteAnchorsFail() {
        XCTAssertThrowsError(try MouthGeometry.align(
            points([(1, 1), (1, 1), (1, 1)]), to: points([(0, 0), (1, 0), (2, 0)])
        ))
        XCTAssertThrowsError(try MouthGeometry.align(
            [CGPoint(x: Double.nan, y: 0), CGPoint(x: 1, y: 1)], to: points([(0, 0), (1, 0)])
        ))
    }

    func testSmoothingRestoresCurrentTranslationAndShrinksAtEnds() {
        let observations = (0..<15).map { index in
            let square = Double(index * index)
            return MouthObservation(
                sourceFrame: index, time: Double(index) / 25,
                anchors: Array(repeating: CGPoint(x: 11 * square, y: 30), count: 8),
                mouthCenter: CGPoint(x: 12 * square, y: 120), centroid: CGPoint(x: 10 * square, y: 100)
            )
        }

        let middle = MouthGeometry.smoothed(observations, at: 7)
        assertPoint(middle.anchors[0], x: 553, y: 30)
        assertPoint(middle.mouthCenter, x: 616, y: 120)
        assertPoint(middle.centroid, x: 490, y: 100)
        assertPoint(MouthGeometry.smoothed(observations, at: 1).anchors[0], x: 35.0 / 3, y: 30)
        assertPoint(MouthGeometry.smoothed(observations, at: 0).mouthCenter, x: 0, y: 120)
        assertPoint(MouthGeometry.smoothed(observations, at: 14).mouthCenter, x: 2352, y: 120)
    }

    func testLowFrameRateDuplicatesNearestFramesWithNonzeroStart() throws {
        var schedule = try MouthFrameSchedule(start: 10, duration: 0.3)
        var selected = try schedule.consume(previousIndex: 0, previousTime: 10, nextIndex: 1, nextTime: 10.1)
        selected += try schedule.consume(previousIndex: 1, previousTime: 10.1, nextIndex: 2, nextTime: 10.2)
        selected += schedule.finish(lastIndex: 2)

        XCTAssertEqual(selected, [0, 0, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(schedule.frameCount, 8)
        XCTAssertEqual(schedule.finish(lastIndex: 2), [])
    }

    func testSixtyFPSDropsFramesByPresentationTime() throws {
        var schedule = try MouthFrameSchedule(start: 0, duration: 0.12)
        let timestamps = [0.0, 1.0 / 60, 2.0 / 60, 3.0 / 60, 4.0 / 60, 5.0 / 60, 6.0 / 60]
        var selected: [Int] = []
        for index in 1..<timestamps.count {
            selected += try schedule.consume(
                previousIndex: index - 1, previousTime: timestamps[index - 1], nextIndex: index, nextTime: timestamps[index]
            )
        }
        selected += schedule.finish(lastIndex: 6)
        XCTAssertEqual(selected, [0, 2, 5])
    }

    func testEquidistantTimestampChoosesEarlierFrame() throws {
        var schedule = try MouthFrameSchedule(start: 0, duration: 0.08)
        var selected = try schedule.consume(previousIndex: 0, previousTime: 0, nextIndex: 1, nextTime: 0.02)
        selected += try schedule.consume(previousIndex: 1, previousTime: 0.02, nextIndex: 2, nextTime: 0.06)
        selected += schedule.finish(lastIndex: 2)
        XCTAssertEqual(selected, [0, 1])
    }

    func testDurationBoundaryAndAllocationLimit() throws {
        XCTAssertEqual(try MouthGeometry.targetTimes(duration: 0.08), [0, 0.04])
        XCTAssertEqual(try MouthGeometry.targetTimes(duration: 0.081), [0, 0.04, 0.08])
        let maximum = try MouthGeometry.targetTimes(duration: 60)
        XCTAssertEqual(maximum.count, 1500)
        XCTAssertEqual(maximum.last, 59.96)
        XCTAssertThrowsError(try MouthGeometry.targetTimes(duration: 60.001)) { error in
            guard case MouthVideoProcessingError.clipTooLong = error else { return XCTFail("Expected duration error") }
        }
        XCTAssertThrowsError(try MouthGeometry.targetTimes(duration: 0))
        XCTAssertThrowsError(try MouthGeometry.targetTimes(duration: .nan))
        var schedule = try MouthFrameSchedule(start: 0, duration: 1)
        XCTAssertThrowsError(try schedule.consume(previousIndex: 0, previousTime: 0.1, nextIndex: 1, nextTime: 0.1))
    }

    func testCropUses96PixelMouthPatchThenFourPixelTrimAndRGBWeights() throws {
        var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
        setPixel(&pixels, width: 100, x: 4, y: 4, red: 255)
        setPixel(&pixels, width: 100, x: 5, y: 4, blue: 255)
        setPixel(&pixels, width: 100, x: 6, y: 4, red: 255, green: 255, blue: 255)
        setPixel(&pixels, width: 100, x: 91, y: 91, green: 255)
        setPixel(&pixels, width: 100, x: 3, y: 4, green: 255)
        let geometry = try VideoGeometry(width: 100, height: 100, transform: .identity)
        let crop = crop(pixels, width: 100, height: 100, geometry: geometry)

        XCTAssertEqual(crop.count, 7744)
        XCTAssertEqual(crop[0], -0.74, accuracy: 0.000_002)
        XCTAssertEqual(crop[1], -1.86060606, accuracy: 0.000_002)
        XCTAssertEqual(crop[2], 3.50848485, accuracy: 0.000_002)
        XCTAssertEqual(crop[3], -2.55151515, accuracy: 0.000_002)
        XCTAssertEqual(crop[7743], 1.00606061, accuracy: 0.000_002)

        var padded = [UInt8](repeating: 0, count: 416 * 100)
        padded[4 * 416 + 4 * 4 + 2] = 255
        let paddedResult = padded.withUnsafeBufferPointer { buffer in
            MouthGeometry.normalizedCrop(
                bgra: buffer.baseAddress!, width: 100, height: 100, bytesPerRow: 416,
                geometry: geometry, alignment: MouthSimilarity(a: 1, b: 0, tx: 0, ty: 0),
                mouthCenter: CGPoint(x: 48, y: 48)
            )
        }
        XCTAssertEqual(paddedResult[0], -0.74, accuracy: 0.000_002)
    }

    func testBilinearWarpRoundsChannelsBeforeGrayscale() throws {
        var pixels = [UInt8](repeating: 0, count: 6 * 6 * 4)
        setPixel(&pixels, width: 6, x: 3, y: 3, red: 255)
        setPixel(&pixels, width: 6, x: 4, y: 3, green: 255)
        setPixel(&pixels, width: 6, x: 3, y: 4, blue: 255)
        setPixel(&pixels, width: 6, x: 4, y: 4, red: 255, green: 255, blue: 255)
        let geometry = try VideoGeometry(width: 6, height: 6, transform: .identity)
        let result = crop(
            pixels, width: 6, height: 6, geometry: geometry,
            alignment: MouthSimilarity(a: 1, b: 0, tx: 0.5, ty: 0.5), mouthCenter: CGPoint(x: 47.5, y: 47.5)
        )

        XCTAssertEqual(result[0], 0.4903672014, accuracy: 0.000_002)
        XCTAssertEqual(result[7743], -2.55151515, accuracy: 0.000_002)
    }

    func testPreferredTransformRotatesActualSourcePixels() throws {
        let geometry = try VideoGeometry(
            width: 3, height: 2, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 2, ty: 0)
        )
        XCTAssertEqual(geometry.width, 2)
        XCTAssertEqual(geometry.height, 3)
        assertPoint(geometry.rawPoint(for: .zero), x: 0, y: 1)
        assertPoint(geometry.rawPoint(for: CGPoint(x: 1, y: 2)), x: 2, y: 0)

        var pixels = [UInt8](repeating: 0, count: 3 * 2 * 4)
        setPixel(&pixels, width: 3, x: 0, y: 1, blue: 255)
        let result = crop(
            pixels, width: 3, height: 2, geometry: geometry,
            alignment: MouthSimilarity(a: 1, b: 0, tx: 4, ty: 4), mouthCenter: CGPoint(x: 44, y: 44)
        )
        XCTAssertEqual(result[0], -1.86060606, accuracy: 0.000_002)
    }

    func testMirroredAndUpsideDownVideoPixelCenters() throws {
        let cases: [(CGAffineTransform, CGPoint)] = [
            (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 3, ty: 2), CGPoint(x: 2, y: 1)),
            (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 3), CGPoint(x: 2, y: 0)),
            (CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 3, ty: 0), CGPoint(x: 2, y: 0)),
            (CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2), CGPoint(x: 0, y: 1)),
            (CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0), CGPoint(x: 0, y: 0)),
            (CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 2, ty: 3), CGPoint(x: 2, y: 1))
        ]
        for (transform, expected) in cases {
            let geometry = try VideoGeometry(width: 3, height: 2, transform: transform)
            XCTAssertEqual(geometry.rawPoint(for: .zero), expected)
        }
        XCTAssertThrowsError(try VideoGeometry(width: 3, height: 2, transform: CGAffineTransform(scaleX: 2, y: 2)))
        XCTAssertThrowsError(try VideoGeometry(width: 4096, height: 4096, transform: .identity))
        XCTAssertThrowsError(try VideoGeometry(
            width: 3, height: 2,
            transform: CGAffineTransform(a: .greatestFiniteMagnitude, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        ))
    }

    private func points(_ values: [(Double, Double)]) -> [CGPoint] { values.map { CGPoint(x: $0.0, y: $0.1) } }

    private func assertPoint(_ point: CGPoint, x: Double, y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 1e-8, file: file, line: line)
    }

    private func setPixel(
        _ pixels: inout [UInt8], width: Int, x: Int, y: Int, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
    ) {
        let index = (y * width + x) * 4
        pixels[index] = blue
        pixels[index + 1] = green
        pixels[index + 2] = red
        pixels[index + 3] = 255
    }

    private func crop(
        _ pixels: [UInt8], width: Int, height: Int, geometry: VideoGeometry,
        alignment: MouthSimilarity = MouthSimilarity(a: 1, b: 0, tx: 0, ty: 0),
        mouthCenter: CGPoint = CGPoint(x: 48, y: 48)
    ) -> [Float] {
        pixels.withUnsafeBufferPointer { buffer in
            MouthGeometry.normalizedCrop(
                bgra: buffer.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                geometry: geometry, alignment: alignment, mouthCenter: mouthCenter
            )
        }
    }
}
