import AppKit
import AVFoundation
import CoreImage
import CryptoKit
import Foundation

@main
final class CameraProbe: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let frameQueue = DispatchQueue(label: "LipCameraProbe.frames")
    private let lock = NSLock()
    private var frameCount = 0
    private var hashes = Set<String>()
    private var firstTime: Double?
    private var lastTime: Double?
    private var finished = false
    private var devices: [[String: String]] = []
    private var chosenDevice: String?
    private var errors: [String] = []
    private var reportDirectory = URL(fileURLWithPath: "/tmp/LipCameraProbe")

    static func main() {
        let delegate = CameraProbe()
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if arguments.count == 3 && arguments[1] == "--report-directory" {
            reportDirectory = URL(fileURLWithPath: arguments[2])
        }
        try? FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        enumerate()
        save(status: "pending", cameraClosed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.finish(reason: "permission_or_capture_deadline") }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.startCapture() }
                    else { self.finish(reason: "camera_permission_denied") }
                }
            }
        default: finish(reason: "camera_permission_denied")
        }
    }

    private func enumerate() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        )
        devices = discovery.devices.map {
            ["name": $0.localizedName, "uniqueID": $0.uniqueID, "deviceType": $0.deviceType.rawValue]
        }
    }

    private func startCapture() {
        guard !finished else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.localizedName.contains("OBS") }) else {
            finish(reason: "obs_device_absent")
            return
        }
        chosenDevice = device.localizedName
        do {
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw ProbeError.input }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: frameQueue)
            guard session.canAddOutput(output) else { throw ProbeError.output }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            guard session.isRunning else { throw ProbeError.start }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.finish(reason: "capture_completed") }
        } catch {
            errors.append(String(describing: error))
            finish(reason: "capture_failed")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(pixels) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        var sample = Data()
        for row in stride(from: 0, to: height, by: 16) {
            for column in stride(from: 0, to: width, by: 16) {
                sample.append(contentsOf: UnsafeBufferPointer(start: bytes + row * bytesPerRow + column * 4, count: 3))
            }
        }
        let digest = SHA256.hash(data: sample).map { String(format: "%02x", $0) }.joined()
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        lock.lock()
        frameCount += 1
        hashes.insert(digest)
        if firstTime == nil { firstTime = time }
        lastTime = time
        let shouldSave = frameCount == 1 || frameCount == 80
        let imageName = frameCount == 1 ? "first-frame.png" : "later-frame.png"
        lock.unlock()
        if shouldSave {
            let image = CIImage(cvPixelBuffer: pixels)
            if let cgImage = CIContext().createCGImage(image, from: image.extent),
               let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
                try? png.write(to: reportDirectory.appendingPathComponent(imageName))
            }
        }
    }

    private func finish(reason: String) {
        guard !finished else { return }
        finished = true
        if session.isRunning { session.stopRunning() }
        frameQueue.sync {}
        errors.append(reason)
        save(status: frameCount >= 25 && hashes.count >= 10 ? "supportedDeviceReady" : "blocked", cameraClosed: !session.isRunning)
        NSApplication.shared.terminate(nil)
    }

    private func save(status: String, cameraClosed: Bool) {
        lock.lock()
        let count = frameCount, distinct = hashes.count
        let elapsed = (lastTime ?? 0) - (firstTime ?? 0)
        lock.unlock()
        let audioInputs = session.inputs.flatMap(\.ports).filter { $0.mediaType == .audio }.count
        let report: [String: Any] = [
            "status": status, "devices": devices, "chosenDevice": chosenDevice ?? "",
            "authorization": AVCaptureDevice.authorizationStatus(for: .video).rawValue,
            "frames": count, "distinctSampledPixelHashes": distinct, "presentationDurationSeconds": elapsed,
            "cameraClosed": cameraClosed, "audioInputCount": audioInputs, "events": errors,
            "proofBoundary": "AVFoundation camera device capture; not Roma app insertion or LipCapture movie writer"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportDirectory.appendingPathComponent("camera.json"), options: .atomic)
        }
    }

    private enum ProbeError: Error { case input, output, start }
}
