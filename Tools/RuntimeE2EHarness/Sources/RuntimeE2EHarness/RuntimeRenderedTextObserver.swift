import CoreGraphics
import CoreVideo
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
    let discardedVisibilitySamples: Int
    let error: String?
}

struct RuntimeReferenceTextFrame: Codable {
    let pngPath: String
    let pngSHA256: String
    let rgbaSHA256: String
    let imageWidth: Int
    let imageHeight: Int
    let rgbaWidth: Int
    let rgbaHeight: Int
    let capturedAtSystemUptime: TimeInterval
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
    let reference: RuntimeReferenceTextFrame
    let referenceMatched: Bool
    let visibilityComparedPixels: Int
    let visibilityDifferingPixels: Int
    let displayCaptureMilliseconds: Double
    let referenceCaptureMilliseconds: Double
}

final class RuntimeRenderedTextObserver {
    static func captureScreenForPreflight() throws -> CGImage {
        try RuntimeScreenshotCaptureSession(captureRect: CGDisplayBounds(CGMainDisplayID())).captureImage()
    }

    private let captureSession: RuntimeScreenshotCaptureSession
    private let acceptedFrameURL: URL
    private let referenceFrameURL: URL
    private let mismatchDisplayURL: URL
    private let mismatchReferenceURL: URL
    private let mismatchReceiptURL: URL
    let editableFrame: CGRect
    let captureRect: CGRect
    private var baseline: [UInt8]?
    private var baselineError: String?
    private(set) var invalidationError: String?
    private var latencyTracker: RuntimeRenderedTextAssociationTracker?
    private var lastSample: RuntimeRenderedTextStabilitySample?
    private typealias AssociatedCapture = (frame: RuntimeCapturedTextFrame,
                                           association: RuntimeTargetCaptureAssociation,
                                           before: TimeInterval, after: TimeInterval)
    private var acceptedCapture: AssociatedCapture?
    private var lastMismatch: AssociatedCapture?
    private var acceptedChangeAtSystemUptime: TimeInterval?
    private(set) var discardedVisibilitySamples = 0
    private var didFlushMismatch = false

    init(editableFrame: CGRect, acceptedFrameURL: URL) throws {
        let horizontalInset = min(12, editableFrame.width / 4)
        let verticalInset = min(4, editableFrame.height / 4)
        let captureRect = editableFrame.insetBy(dx: horizontalInset, dy: verticalInset).integral
        guard captureRect.width >= 8, captureRect.height >= 8 else {
            throw RuntimeRenderedTextObserverError.invalidCaptureRect
        }
        self.acceptedFrameURL = acceptedFrameURL
        let stem = acceptedFrameURL.deletingPathExtension().path
        referenceFrameURL = URL(fileURLWithPath: stem + "-reference.png")
        mismatchDisplayURL = URL(fileURLWithPath: stem + "-mismatch-display.png")
        mismatchReferenceURL = URL(fileURLWithPath: stem + "-mismatch-reference.png")
        mismatchReceiptURL = URL(fileURLWithPath: stem + "-mismatch.json")
        guard ![acceptedFrameURL, referenceFrameURL, mismatchDisplayURL,
                mismatchReferenceURL, mismatchReceiptURL].contains(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { throw RuntimeRenderedTextObserverError.acceptedFrameAlreadyExists }
        captureSession = try RuntimeScreenshotCaptureSession(captureRect: captureRect)
        self.editableFrame = editableFrame
        self.captureRect = captureRect
    }

    func establishBaseline(_ frame: RuntimeCapturedTextFrame, precedingText: String?, followingText: String?) throws {
        if let invalidationError { throw RuntimeRenderedTextObserverError.baselineUnavailable(invalidationError) }
        guard let precedingText, let followingText, precedingText == followingText,
              followingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable(
                "Pre-insertion capture requires matching readable empty AX text before and after capture"
            )
        }
        guard frame.visibilityMatches else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable("Display pixels did not match the owned window")
        }
        lastMismatch = nil
        // Repeated preparation checks validate the same baseline; never replace an established one.
        guard baseline == nil else { return }
        baseline = frame.bytes
        baselineError = nil
        var tracker = RuntimeRenderedTextAssociationTracker(baseline: frame.bytes)
        _ = tracker.observe(current: frame.bytes, atSystemUptime: frame.atSystemUptime,
                            accessibilityText: followingText, precedingAccessibilityText: precedingText)
        latencyTracker = tracker
    }

    func beginObservation() -> String? {
        guard baseline != nil, latencyTracker != nil else {
            return baselineError ?? "Rendered-text baseline is unavailable"
        }
        lastSample = nil
        return nil
    }

    var associationError: String? { latencyTracker?.associationError }
    var hasPendingVisibilityMismatch: Bool { lastMismatch != nil }

    func invalidateAssociation(_ error: String) {
        invalidationError = error
        baseline = nil
        latencyTracker = nil
        lastSample = nil
        acceptedCapture = nil
        acceptedChangeAtSystemUptime = nil
        baselineError = error
    }

    func captureFrame(association: RuntimeTargetCaptureAssociation) throws -> RuntimeCapturedTextFrame {
        try captureSession.capturePair(association: association)
    }

    func discardVisibilitySample(_ frame: RuntimeCapturedTextFrame,
                                 association: RuntimeTargetCaptureAssociation,
                                 before: TimeInterval, after: TimeInterval) {
        discardedVisibilitySamples += 1
        lastMismatch = (frame, association, before, after)
        latencyTracker?.discardUnassociatedFrame()
        lastSample = nil
        acceptedCapture = nil
        acceptedChangeAtSystemUptime = nil
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
        if current.visibilityMatches { lastMismatch = nil }
        guard var latencyTracker else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable(
                baselineError ?? "Rendered-text baseline is unavailable"
            )
        }
        let latencySample = latencyTracker.observe(
            current: current.bytes, atSystemUptime: current.atSystemUptime,
            accessibilityText: accessibilityText, precedingAccessibilityText: precedingAccessibilityText
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
              let firstPersistentChangeAtSystemUptime = latencySample.firstPersistentChangeAtSystemUptime else {
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
            keyUpToRenderedTextMilliseconds: max(0, firstPersistentChangeAtSystemUptime - keyUpAtSystemUptime) * 1_000,
            changedPixels: sample.baselineDifference.changedPixels,
            comparedPixels: sample.baselineDifference.comparedPixels,
            requiredChangedPixels: sample.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: sample.interFrameChangedPixels,
            acceptedFrame: nil, discardedVisibilitySamples: discardedVisibilitySamples, error: nil
        )
    }

    func retainAcceptedFrame() throws -> RuntimeAcceptedTextFrame {
        guard let acceptedCapture else { throw RuntimeRenderedTextObserverError.acceptedFrameUnavailable }
        return try retainPair(acceptedCapture, displayURL: acceptedFrameURL, referenceURL: referenceFrameURL)
    }

    // Called before failed preparation/observation cleanup; never capture a later desktop as evidence.
    func flushMismatchEvidence() -> String? {
        guard !didFlushMismatch, let lastMismatch else { return nil }
        didFlushMismatch = true
        do {
            let receipt = try retainPair(lastMismatch, displayURL: mismatchDisplayURL, referenceURL: mismatchReferenceURL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: mismatchReceiptURL, options: .withoutOverwriting)
            return "Mismatched capture evidence: \(mismatchReceiptURL.path)"
        } catch { return "Could not retain mismatched capture pair: \(error)" }
    }

    private func retainPair(_ capture: AssociatedCapture, displayURL: URL, referenceURL: URL) throws -> RuntimeAcceptedTextFrame {
        let frame = capture.frame
        let displayHash = try Self.writePNG(frame.image, to: displayURL)
        let referenceHash = try Self.writePNG(frame.reference.image, to: referenceURL)
        return RuntimeAcceptedTextFrame(
            pngPath: displayURL.path, pngSHA256: displayHash, rgbaSHA256: Self.hash(frame.bytes),
            imageWidth: frame.image.width, imageHeight: frame.image.height,
            rgbaWidth: frame.rgbaWidth, rgbaHeight: frame.rgbaHeight,
            capturedAtSystemUptime: frame.atSystemUptime,
            captureBracketStartedAtSystemUptime: capture.before,
            captureBracketFinishedAtSystemUptime: capture.after, association: capture.association,
            reference: RuntimeReferenceTextFrame(
                pngPath: referenceURL.path, pngSHA256: referenceHash, rgbaSHA256: Self.hash(frame.reference.bytes),
                imageWidth: frame.reference.image.width, imageHeight: frame.reference.image.height,
                rgbaWidth: frame.reference.width, rgbaHeight: frame.reference.height,
                capturedAtSystemUptime: frame.reference.atSystemUptime
            ), referenceMatched: frame.visibilityMatches,
            visibilityComparedPixels: frame.visibilityComparison.comparedPixels,
            visibilityDifferingPixels: frame.visibilityComparison.differingPixels,
            displayCaptureMilliseconds: frame.displayCaptureMilliseconds,
            referenceCaptureMilliseconds: frame.referenceCaptureMilliseconds
        )
    }

    private static func hash(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws -> String {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeRenderedTextObserverError.acceptedFrameAlreadyExists
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RuntimeRenderedTextObserverError.acceptedFrameWriteFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RuntimeRenderedTextObserverError.acceptedFrameWriteFailed }
        try (data as Data).write(to: url, options: .withoutOverwriting)
        return SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
    }

    func failureResult(error: String) -> RuntimeRenderedTextChangeResult {
        RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: nil,
            changedPixels: lastSample?.baselineDifference.changedPixels,
            comparedPixels: lastSample?.baselineDifference.comparedPixels,
            requiredChangedPixels: lastSample?.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: lastSample?.interFrameChangedPixels,
            acceptedFrame: nil, discardedVisibilitySamples: discardedVisibilitySamples, error: error
        )
    }
}

struct RuntimeCapturedTextFrame {
    let display: RuntimeRGBAFrame
    let reference: RuntimeRGBAFrame
    let visibilityComparison: RuntimeCapturePixelComparison
    let displayCaptureMilliseconds: Double
    let referenceCaptureMilliseconds: Double
    var bytes: [UInt8] { display.bytes }
    var image: CGImage { display.image }
    var rgbaWidth: Int { display.width }
    var rgbaHeight: Int { display.height }
    var atSystemUptime: TimeInterval { display.atSystemUptime }
    var visibilityMatches: Bool { visibilityComparison.matches }
}

private final class RuntimeScreenshotCaptureSession {
    private let filter: SCContentFilter
    private let display: SCDisplay
    private let windows: [SCWindow]
    private let configuration: SCStreamConfiguration
    private var referenceFilter: SCContentFilter?
    private var referenceAssociation: RuntimeTargetCaptureAssociation?

    init(captureRect: CGRect) throws {
        let contentState = RuntimeShareableContentState()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                contentState.complete(content: content, error: nil)
            } catch { contentState.complete(content: nil, error: error) }
        }
        let content = try contentState.wait(timeoutSeconds: 3)
        guard let display = content.displays.max(by: {
            Self.intersectionArea($0.frame, captureRect) < Self.intersectionArea($1.frame, captureRect)
        }), display.frame.contains(captureRect) else { throw RuntimeRenderedTextObserverError.captureDisplayNotFound }
        self.display = display
        windows = content.windows
        filter = SCContentFilter(display: display, excludingWindows: [])
        configuration = SCStreamConfiguration()
        configuration.sourceRect = captureRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = max(1, Int(captureRect.width.rounded(.up)))
        configuration.height = max(1, Int(captureRect.height.rounded(.up)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
    }

    func capturePair(association: RuntimeTargetCaptureAssociation) throws -> RuntimeCapturedTextFrame {
        if referenceFilter == nil {
            let matches = windows.filter {
                $0.windowID == association.windowID && $0.owningApplication?.processID == association.processIdentifier
                    && $0.frame == CGRect(x: association.windowFrame.x, y: association.windowFrame.y,
                                          width: association.windowFrame.width, height: association.windowFrame.height)
            }
            guard matches.count == 1, let window = matches.first else {
                throw RuntimeRenderedTextObserverError.captureWindowNotFound
            }
            referenceFilter = SCContentFilter(display: display, including: [window])
            referenceAssociation = association
        }
        guard referenceAssociation == association, let referenceFilter else {
            throw RuntimeRenderedTextObserverError.captureWindowNotFound
        }
        let displayStarted = ProcessInfo.processInfo.systemUptime
        let displayFrame = try normalize(captureImage())
        let displayFinished = ProcessInfo.processInfo.systemUptime
        let referenceFrame = try normalize(captureImage(filter: referenceFilter))
        let referenceFinished = ProcessInfo.processInfo.systemUptime
        guard displayFrame.width == referenceFrame.width, displayFrame.height == referenceFrame.height,
              let comparison = RuntimeCaptureVisibilityPolicy.compareRGBA(
                display: displayFrame.bytes, reference: referenceFrame.bytes
              ) else { throw RuntimeRenderedTextObserverError.incompatibleFrames }
        return RuntimeCapturedTextFrame(display: displayFrame, reference: referenceFrame,
                                        visibilityComparison: comparison,
                                        displayCaptureMilliseconds: (displayFinished - displayStarted) * 1_000,
                                        referenceCaptureMilliseconds: (referenceFinished - displayFinished) * 1_000)
    }

    private func normalize(_ image: CGImage) throws -> RuntimeRGBAFrame {
        // Full configured ROI: downsampling could erase a small opaque occluder.
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw RuntimeRenderedTextObserverError.pixelConversionFailed }
        return RuntimeRGBAFrame(bytes: bytes, image: image, width: width, height: height,
                                atSystemUptime: ProcessInfo.processInfo.systemUptime)
    }

    fileprivate func captureImage(filter override: SCContentFilter? = nil) throws -> CGImage {
        let state = RuntimeScreenshotCaptureState()
        SCScreenshotManager.captureImage(contentFilter: override ?? filter, configuration: configuration) { image, error in
            state.complete(image: image, error: error)
        }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let result = state.result() {
                switch result {
                case .success(let image): return image
                case .failure(let error): throw RuntimeRenderedTextObserverError.captureFailed(error.localizedDescription)
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        throw RuntimeRenderedTextObserverError.captureTimedOut
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

struct RuntimeRGBAFrame {
    let bytes: [UInt8]
    let image: CGImage
    let width: Int
    let height: Int
    let atSystemUptime: TimeInterval
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
    case captureDisplayNotFound, captureWindowNotFound
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
        case .captureWindowNotFound:
            return "No unique ScreenCaptureKit window matches the owned target association"
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
