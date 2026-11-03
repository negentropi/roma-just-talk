import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import RuntimeE2ECore
import ScreenCaptureKit
import UniformTypeIdentifiers

struct RuntimeRenderedTextChangeResult: Codable {
    let keyUpToRenderedTextMilliseconds: Double?
    let changedPixels: Int?
    let comparedPixels: Int?
    let requiredChangedPixels: Int?
    let interFrameChangedPixels: Int?
    let acceptedFrame: RuntimeAcceptedTextFrame?
    let error: String?
}

struct RuntimeAcceptedTextFrame: Codable {
    let pngPath: String
    let pngSHA256: String
    let rgbaSHA256: String
    let imageWidth: Int
    let imageHeight: Int
    let rgbaWidth: Int
    let rgbaHeight: Int
    let capturedAtSystemUptime: TimeInterval
    let captureBracketStartedAtSystemUptime: TimeInterval
    let captureBracketFinishedAtSystemUptime: TimeInterval
    let association: RuntimeTargetCaptureAssociation
}

final class RuntimeRenderedTextObserver {
    static func captureScreenForPreflight() throws -> CGImage {
        try RuntimeScreenshotCaptureSession(captureRect: CGDisplayBounds(CGMainDisplayID())).captureImage()
    }

    private let captureSession: RuntimeScreenshotCaptureSession
    let editableFrame: CGRect
    let captureRect: CGRect
    private var baseline: RuntimeRGBAFrame?
    private var baselineError: String?
    private var latencyTracker: RuntimeRenderedTextAssociationTracker?
    private var lastSample: RuntimeRenderedTextStabilitySample?
    private var acceptedCapture: (frame: RuntimeCapturedTextFrame,
                                  association: RuntimeTargetCaptureAssociation,
                                  before: TimeInterval, after: TimeInterval)?
    private var acceptedChangeAtSystemUptime: TimeInterval?

    init(editableFrame: CGRect) throws {
        let horizontalInset = min(12, editableFrame.width / 4)
        let verticalInset = min(4, editableFrame.height / 4)
        let captureRect = editableFrame
            .insetBy(dx: horizontalInset, dy: verticalInset)
            .integral
        guard captureRect.width >= 8, captureRect.height >= 8 else {
            throw RuntimeRenderedTextObserverError.invalidCaptureRect
        }
        let captureSession = try RuntimeScreenshotCaptureSession(captureRect: captureRect)
        self.captureSession = captureSession
        self.editableFrame = editableFrame
        self.captureRect = captureRect
    }

    func refreshBaseline(accessibilityText: () -> String?) -> String? {
        do {
            let precedingText = accessibilityText()
            let frame = try captureSession.captureRGBA()
            let followingText = accessibilityText()
            guard let precedingText, let followingText, precedingText == followingText,
                  followingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RuntimeRenderedTextObserverError.baselineUnavailable(
                    "Pre-insertion capture requires matching readable empty AX text before and after capture"
                )
            }
            baseline = frame
            baselineError = nil
            var tracker = RuntimeRenderedTextAssociationTracker(baseline: frame.bytes)
            _ = tracker.observe(current: frame.bytes, atSystemUptime: ProcessInfo.processInfo.systemUptime,
                                accessibilityText: followingText, precedingAccessibilityText: precedingText)
            latencyTracker = tracker
            lastSample = nil
            acceptedCapture = nil
            acceptedChangeAtSystemUptime = nil
        } catch {
            baseline = nil
            latencyTracker = nil
            lastSample = nil
            acceptedCapture = nil
            acceptedChangeAtSystemUptime = nil
            baselineError = String(describing: error)
        }
        return baselineError
    }

    func beginObservation() -> String? {
        guard baseline != nil, latencyTracker != nil else {
            return baselineError ?? "Rendered-text baseline is unavailable"
        }
        lastSample = nil
        return nil
    }

    var associationError: String? { latencyTracker?.associationError }

    func invalidateAssociation(_ error: String) {
        baseline = nil
        latencyTracker = nil
        lastSample = nil
        acceptedCapture = nil
        acceptedChangeAtSystemUptime = nil
        baselineError = error
    }

    func captureFrame() throws -> RuntimeCapturedTextFrame {
        let frame = try captureSession.captureRGBA()
        return RuntimeCapturedTextFrame(bytes: frame.bytes, image: frame.image,
                                        rgbaWidth: frame.width, rgbaHeight: frame.height,
                                        atSystemUptime: ProcessInfo.processInfo.systemUptime)
    }

    func observeCapturedFrame(
        _ current: RuntimeCapturedTextFrame,
        accessibilityText: String?,
        precedingAccessibilityText: String?,
        keyUpAtSystemUptime: TimeInterval,
        association: RuntimeTargetCaptureAssociation,
        captureBracketStartedAtSystemUptime: TimeInterval,
        captureBracketFinishedAtSystemUptime: TimeInterval
    ) throws -> RuntimeRenderedTextChangeResult? {
        guard var latencyTracker else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable(
                baselineError ?? "Rendered-text baseline is unavailable"
            )
        }
        let latencySample = latencyTracker.observe(
            current: current.bytes,
            atSystemUptime: current.atSystemUptime,
            accessibilityText: accessibilityText,
            precedingAccessibilityText: precedingAccessibilityText
        )
        self.latencyTracker = latencyTracker
        guard let latencySample else {
            lastSample = nil
            acceptedCapture = nil
            acceptedChangeAtSystemUptime = nil
            return nil
        }
        let sample = latencySample.stabilitySample
        lastSample = sample
        guard sample.stable,
              let firstPersistentChangeAtSystemUptime =
                latencySample.firstPersistentChangeAtSystemUptime else {
            acceptedCapture = nil
            acceptedChangeAtSystemUptime = nil
            return nil
        }

        if acceptedChangeAtSystemUptime != firstPersistentChangeAtSystemUptime {
            acceptedCapture = (current, association, captureBracketStartedAtSystemUptime,
                               captureBracketFinishedAtSystemUptime)
            acceptedChangeAtSystemUptime = firstPersistentChangeAtSystemUptime
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
            acceptedFrame: nil,
            error: nil
        )
    }

    func retainAcceptedFrame(at url: URL) throws -> RuntimeAcceptedTextFrame {
        guard let acceptedCapture else { throw RuntimeRenderedTextObserverError.acceptedFrameUnavailable }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeRenderedTextObserverError.acceptedFrameAlreadyExists
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RuntimeRenderedTextObserverError.acceptedFrameWriteFailed
        }
        CGImageDestinationAddImage(destination, acceptedCapture.frame.image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RuntimeRenderedTextObserverError.acceptedFrameWriteFailed
        }
        let png = try Data(contentsOf: url)
        return RuntimeAcceptedTextFrame(
            pngPath: url.path,
            pngSHA256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            rgbaSHA256: SHA256.hash(data: Data(acceptedCapture.frame.bytes)).map { String(format: "%02x", $0) }.joined(),
            imageWidth: acceptedCapture.frame.image.width, imageHeight: acceptedCapture.frame.image.height,
            rgbaWidth: acceptedCapture.frame.rgbaWidth, rgbaHeight: acceptedCapture.frame.rgbaHeight,
            capturedAtSystemUptime: acceptedCapture.frame.atSystemUptime,
            captureBracketStartedAtSystemUptime: acceptedCapture.before,
            captureBracketFinishedAtSystemUptime: acceptedCapture.after,
            association: acceptedCapture.association
        )
    }

    func failureResult(error: String) -> RuntimeRenderedTextChangeResult {
        RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: nil,
            changedPixels: lastSample?.baselineDifference.changedPixels,
            comparedPixels: lastSample?.baselineDifference.comparedPixels,
            requiredChangedPixels: lastSample?.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: lastSample?.interFrameChangedPixels,
            acceptedFrame: nil,
            error: error
        )
    }

}

struct RuntimeCapturedTextFrame {
    let bytes: [UInt8]
    let image: CGImage
    let rgbaWidth: Int
    let rgbaHeight: Int
    let atSystemUptime: TimeInterval
}

private final class RuntimeScreenshotCaptureSession {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration

    init(captureRect: CGRect) throws {
        let contentState = RuntimeShareableContentState()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                contentState.complete(content: content, error: nil)
            } catch {
                contentState.complete(content: nil, error: error)
            }
        }
        let content = try contentState.wait(timeoutSeconds: 3)
        guard let display = content.displays.max(by: {
            Self.intersectionArea($0.frame, captureRect)
                < Self.intersectionArea($1.frame, captureRect)
        }), display.frame.contains(captureRect) else {
            throw RuntimeRenderedTextObserverError.captureDisplayNotFound
        }

        filter = SCContentFilter(display: display, excludingWindows: [])
        configuration = SCStreamConfiguration()
        configuration.sourceRect = captureRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        configuration.width = max(1, Int(captureRect.width.rounded(.up)))
        configuration.height = max(1, Int(captureRect.height.rounded(.up)))
        configuration.showsCursor = false
    }

    func captureRGBA() throws -> RuntimeRGBAFrame {
        let image = try captureImage()
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
        return RuntimeRGBAFrame(bytes: bytes, image: image, width: width, height: height)
    }

    fileprivate func captureImage() throws -> CGImage {
        let state = RuntimeScreenshotCaptureState()
        SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) { image, error in
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

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

private struct RuntimeRGBAFrame {
    let bytes: [UInt8]
    let image: CGImage
    let width: Int
    let height: Int
}

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

private final class RuntimeShareableContentState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<SCShareableContent, Error>?

    func complete(content: SCShareableContent?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if let content {
            value = .success(content)
        } else {
            value = .failure(error ?? RuntimeRenderedTextObserverError.missingShareableContent)
        }
    }

    func wait(timeoutSeconds: TimeInterval) throws -> SCShareableContent {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            lock.lock()
            let result = value
            lock.unlock()
            if let result {
                return try result.get()
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        throw RuntimeRenderedTextObserverError.shareableContentTimedOut
    }
}

private enum RuntimeRenderedTextObserverError: Error, CustomStringConvertible {
    case invalidCaptureRect
    case baselineUnavailable(String)
    case captureDisplayNotFound
    case shareableContentTimedOut
    case missingShareableContent
    case captureTimedOut
    case captureFailed(String)
    case missingImage
    case pixelConversionFailed
    case incompatibleFrames
    case acceptedFrameUnavailable, acceptedFrameAlreadyExists, acceptedFrameWriteFailed

    var description: String {
        switch self {
        case .invalidCaptureRect:
            return "Editable AX element has no usable screen rectangle"
        case .baselineUnavailable(let message):
            return message
        case .captureDisplayNotFound:
            return "No ScreenCaptureKit display contains the target editor"
        case .shareableContentTimedOut:
            return "ScreenCaptureKit shareable-content discovery timed out"
        case .missingShareableContent:
            return "ScreenCaptureKit returned no shareable content"
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
        case .acceptedFrameUnavailable:
            return "No accepted target frame is available"
        case .acceptedFrameAlreadyExists:
            return "Accepted-frame evidence path already exists"
        case .acceptedFrameWriteFailed:
            return "Could not retain the accepted target frame"
        }
    }
}
