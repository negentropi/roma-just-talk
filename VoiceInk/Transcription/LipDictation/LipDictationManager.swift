import AVFoundation
import Foundation
import OSLog
import VoiceInkCore
import VoiceInkLip

@MainActor
final class LipDictationManager: ObservableObject {
    static let shared = LipDictationManager()

    @Published private(set) var readiness: LipDictationReadiness = .needsSetup
    @Published private(set) var downloadDescription = ""
    private let runtime: LipRuntime
    private var setupTask: Task<Void, Never>?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LipDictation")

    private init() {
        runtime = LipRuntime(directory: VoiceInkMacOSStorageDirectories.modelsDirectory
            .appendingPathComponent("LipReading", isDirectory: true))
    }

    func refresh() async {
        guard setupTask == nil else { return }
        if let bytes = try? await runtime.installationBytes() {
            let download = ByteCountFormatter.string(fromByteCount: bytes.download, countStyle: .file)
            let installed = ByteCountFormatter.string(fromByteCount: bytes.installed, countStyle: .file)
            downloadDescription = "Downloads \(download). Uses \(installed) on this Mac."
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            readiness = .cameraDenied
        case .authorized:
            readiness = await runtime.isInstalled() ? .ready : .needsSetup
        case .notDetermined:
            readiness = .needsSetup
        @unknown default:
            readiness = .unavailable
        }
    }

    func setUp() async {
        if let setupTask { await setupTask.value; return }
        readiness = .preparing
        let task = Task { [runtime, weak self] in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard !Task.isCancelled else { self?.readiness = .needsSetup; return }
            guard authorized else { self?.readiness = .cameraDenied; return }
            do {
                try await runtime.install()
                guard !Task.isCancelled else { self?.readiness = .needsSetup; return }
                self?.readiness = .ready
                self?.logger.notice("model.install.complete")
            } catch is CancellationError {
                self?.readiness = .needsSetup
            } catch {
                self?.readiness = .failed(message: error.localizedDescription)
                self?.logger.error("model.install.failed type=\(String(describing: type(of: error)), privacy: .public)")
            }
        }
        setupTask = task
        await task.value
        setupTask = nil
    }

    func transcribe(_ clip: LipCaptureClip) async throws -> String {
        try Task.checkCancellation()
        do {
            return try await runtime.transcribe(videoURL: clip.url)
        } catch let error as LipModelStoreError {
            if error == .notInstalled || error == .verificationFailed {
                readiness = .failed(message: error.localizedDescription)
            }
            throw error
        }
    }

    func shutDown() async {
        setupTask?.cancel()
        await runtime.cancelInstallation()
        await setupTask?.value
        setupTask = nil
    }
}
