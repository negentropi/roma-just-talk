import CoreGraphics
import Foundation
import RuntimeE2ECore
import ScreenCaptureKit

struct RuntimeRenderedTextChangeResult: Codable {
    let keyUpToRenderedTextMilliseconds: Double?
    let changedPixels: Int?
    let comparedPixels: Int?
    let requiredChangedPixels: Int?
    let interFrameChangedPixels: Int?
    let error: String?
}

final class RuntimeRenderedTextObserver {
    private let captureRect: CGRect
    private var baseline: RuntimeRGBAFrame?
    private var baselineError: String?
    private var latencyTracker: RuntimeRenderedTextLatencyTracker?
    private var lastSample: RuntimeRenderedTextStabilitySample?

    init(editableFrame: CGRect) throws {
        let horizontalInset = min(12, editableFrame.width / 4)
        let verticalInset = min(4, editableFrame.height / 4)
        let captureRect = editableFrame
            .insetBy(dx: horizontalInset, dy: verticalInset)
            .integral
        guard captureRect.width >= 8, captureRect.height >= 8 else {
            throw RuntimeRenderedTextObserverError.invalidCaptureRect
        }
        self.captureRect = captureRect
        let baseline = try Self.captureRGBA(in: captureRect)
        self.baseline = baseline
        latencyTracker = RuntimeRenderedTextLatencyTracker(baseline: baseline.bytes)
    }

    func refreshBaseline() -> String? {
        do {
            baseline = try Self.captureRGBA(in: captureRect)
            baselineError = nil
            latencyTracker = baseline.map {
                RuntimeRenderedTextLatencyTracker(baseline: $0.bytes)
            }
            lastSample = nil
        } catch {
            baseline = nil
            latencyTracker = nil
            lastSample = nil
            baselineError = String(describing: error)
        }
        return baselineError
    }

    func beginObservation() -> String? {
        guard let baseline else {
            return baselineError ?? "Rendered-text baseline is unavailable"
        }
        latencyTracker = RuntimeRenderedTextLatencyTracker(baseline: baseline.bytes)
        lastSample = nil
        return nil
    }

    func observeRenderedChange(
        keyUpAtSystemUptime: TimeInterval
    ) throws -> RuntimeRenderedTextChangeResult? {
        guard var latencyTracker else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable(
                baselineError ?? "Rendered-text baseline is unavailable"
            )
        }
        let current = try Self.captureRGBA(in: captureRect)
        let observedAtSystemUptime = ProcessInfo.processInfo.systemUptime
        guard let latencySample = latencyTracker.observe(
            current: current.bytes,
            atSystemUptime: observedAtSystemUptime
        ) else {
            throw RuntimeRenderedTextObserverError.incompatibleFrames
        }
        self.latencyTracker = latencyTracker
        let sample = latencySample.stabilitySample
        lastSample = sample
        guard sample.stable,
              let firstPersistentChangeAtSystemUptime =
                latencySample.firstPersistentChangeAtSystemUptime else {
            return nil
        }

        return RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: max(
                0,
                firstPersistentChangeAtSystemUptime - keyUpAtSystemUptime
            ) * 1_000,
            changedPixels: sample.baselineDifference.changedPixels,
            comparedPixels: sample.baselineDifference.comparedPixels,
            requiredChangedPixels: sample.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: sample.interFrameChangedPixels,
            error: nil
        )
    }

    func failureResult(error: String) -> RuntimeRenderedTextChangeResult {
        RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: nil,
            changedPixels: lastSample?.baselineDifference.changedPixels,
            comparedPixels: lastSample?.baselineDifference.comparedPixels,
            requiredChangedPixels: lastSample?.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: lastSample?.interFrameChangedPixels,
            error: error
        )
    }

    private static func captureRGBA(in rect: CGRect) throws -> RuntimeRGBAFrame {
        guard #available(macOS 15.2, *) else {
            throw RuntimeRenderedTextObserverError.unsupportedOS
        }
        let image = try captureImage(in: rect)
        let longestSide = max(image.width, image.height)
        let scale = min(1, 640 / Double(longestSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw RuntimeRenderedTextObserverError.pixelConversionFailed
        }
        return RuntimeRGBAFrame(bytes: bytes)
    }

    @available(macOS 15.2, *)
    private static func captureImage(in rect: CGRect) throws -> CGImage {
        let state = RuntimeScreenshotCaptureState()
        SCScreenshotManager.captureImage(in: rect) { image, error in
            state.complete(image: image, error: error)
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let result = state.result() {
                switch result {
                case .success(let image):
                    return image
                case .failure(let error):
                    throw RuntimeRenderedTextObserverError.captureFailed(error.localizedDescription)
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        throw RuntimeRenderedTextObserverError.captureTimedOut
    }
}

private struct RuntimeRGBAFrame {
    let bytes: [UInt8]
}

@available(macOS 15.2, *)
private final class RuntimeScreenshotCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<CGImage, Error>?

    func complete(image: CGImage?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if let image {
            value = .success(image)
        } else {
            value = .failure(error ?? RuntimeRenderedTextObserverError.missingImage)
        }
    }

    func result() -> Result<CGImage, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private enum RuntimeRenderedTextObserverError: Error, CustomStringConvertible {
    case invalidCaptureRect
    case baselineUnavailable(String)
    case unsupportedOS
    case captureTimedOut
    case captureFailed(String)
    case missingImage
    case pixelConversionFailed
    case incompatibleFrames

    var description: String {
        switch self {
        case .invalidCaptureRect:
            return "Editable AX element has no usable screen rectangle"
        case .baselineUnavailable(let message):
            return message
        case .unsupportedOS:
            return "Rendered-pixel measurement requires macOS 15.2 or newer"
        case .captureTimedOut:
            return "ScreenCaptureKit screenshot timed out"
        case .captureFailed(let message):
            return "ScreenCaptureKit screenshot failed: \(message)"
        case .missingImage:
            return "ScreenCaptureKit returned no image"
        case .pixelConversionFailed:
            return "Could not normalize screenshot pixels"
        case .incompatibleFrames:
            return "Rendered-text baseline and current screenshot dimensions differ"
        }
    }
}
