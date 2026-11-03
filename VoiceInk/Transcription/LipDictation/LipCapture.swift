import AVFoundation
import Foundation
import os
import VoiceInkCore

struct LipCaptureClip: Sendable {
    let url: URL
    let duration: TimeInterval
    private let directory: URL

    fileprivate init(url: URL, duration: TimeInterval, directory: URL) {
        self.url = url
        self.duration = duration
        self.directory = directory
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum LipCaptureError: LocalizedError {
    case cameraPermissionRequired
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case alreadyRecording
    case notRecording
    case failedToStart
    case interrupted
    case recordingLimitReached

    var errorDescription: String? {
        switch self {
        case .cameraPermissionRequired:
            return "Allow camera access in Lip Dictation settings before recording."
        case .cameraUnavailable:
            return "Connect a camera to use lip dictation."
        case .cannotAddInput, .cannotAddOutput:
            return "The camera could not start recording. Close other camera apps and try again."
        case .alreadyRecording:
            return "A lip dictation recording is already active."
        case .notRecording, .failedToStart:
            return "The lip dictation recording did not start."
        case .interrupted:
            return "The camera stopped before dictation finished. Check the camera and try again."
        case .recordingLimitReached:
            return "Lip dictation stopped at its 60-second limit."
        }
    }
}

actor LipCapture {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LipCapture")
    private final class Recording {
        let id: UUID
        let url: URL
        let directory: URL
        let session: AVCaptureSession
        let output: AVCaptureMovieFileOutput
        let delegate: LipCaptureDelegate
        let onInterruption: @Sendable (Error) -> Void
        var start: CheckedContinuation<Void, Error>?
        var finish: [CheckedContinuation<LipCaptureClip, Error>] = []
        var drain: [CheckedContinuation<Void, Never>] = []
        var stopRequested = false
        var abortError: Error?
        var startupTimeout: Task<Void, Never>?
        var finishTimeout: Task<Void, Never>?

        init(id: UUID, url: URL, directory: URL, session: AVCaptureSession,
             output: AVCaptureMovieFileOutput, delegate: LipCaptureDelegate,
             onInterruption: @escaping @Sendable (Error) -> Void) {
            self.id = id
            self.url = url
            self.directory = directory
            self.session = session
            self.output = output
            self.delegate = delegate
            self.onInterruption = onInterruption
        }
    }

    private var recording: Recording?
    private var completed: (id: UUID, clip: LipCaptureClip)?

    func start(sessionID: UUID, onInterruption: @escaping @Sendable (Error) -> Void) async throws {
        guard recording == nil, completed == nil else { throw LipCaptureError.alreadyRecording }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw LipCaptureError.cameraPermissionRequired
        }
        try Task.checkCancellation()

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard let camera = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw LipCaptureError.cameraUnavailable
        }
        do {
            try add(camera, to: session)
        } catch {
            session.commitConfiguration()
            throw error
        }
        let output = AVCaptureMovieFileOutput()
        output.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LipCaptureError.cannotAddOutput
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        session.commitConfiguration()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaJustTalk-LipDictation", isDirectory: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("capture.mov")
        let delegate = LipCaptureDelegate(owner: self, directory: directory)
        let pending = Recording(id: sessionID, url: url, directory: directory, session: session, output: output,
                                delegate: delegate, onInterruption: onInterruption)
        recording = pending
        delegate.recordingID = pending.id
        session.startRunning()
        guard session.isRunning else {
            recording = nil
            close(pending)
            removeVideo(pending)
            throw LipCaptureError.failedToStart
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.start = continuation
                pending.startupTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                    await self?.abort(id: sessionID, error: LipCaptureError.failedToStart)
                }
                let audioInputCount = session.inputs.flatMap(\.ports).filter { $0.mediaType == .audio }.count
                logger.notice("capture.start id=\(pending.id.uuidString, privacy: .public) audio_inputs=\(audioInputCount, privacy: .public)")
                output.startRecording(to: url, recordingDelegate: delegate)
            }
        } onCancel: {
            Task { await self.abort(id: sessionID, error: CancellationError()) }
        }
    }

    func stop() async throws -> LipCaptureClip {
        try Task.checkCancellation()
        if let completed {
            self.completed = nil
            return completed.clip
        }
        guard let recording else { throw LipCaptureError.notRecording }
        let id = recording.id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                recording.finish.append(continuation)
                recording.stopRequested = true
                if recording.output.isRecording {
                    recording.output.stopRecording()
                }
                recording.session.stopRunning()
                scheduleFinishDeadline(recording)
            }
        } onCancel: {
            Task { await self.abort(id: id, error: CancellationError()) }
        }
    }

    func cancel() async {
        completed?.clip.remove()
        completed = nil
        guard let recording else { return }
        abort(id: recording.id, error: CancellationError())
        guard self.recording?.id == recording.id else { return }
        await withCheckedContinuation { recording.drain.append($0) }
    }

    func captureStatus() -> (isRunning: Bool, isRecording: Bool, audioInputCount: Int) {
        guard let recording else { return (false, false, 0) }
        return (recording.session.isRunning, recording.output.isRecording,
                recording.session.inputs.flatMap(\.ports).filter { $0.mediaType == .audio }.count)
    }

    private func abort(id: UUID, error: Error) {
        guard let recording, recording.id == id else { return }
        guard recording.abortError == nil else { return }
        recording.abortError = error
        recording.startupTimeout?.cancel()
        if recording.output.isRecording { recording.output.stopRecording() }
        recording.session.stopRunning()
        // Removing the parent also prevents a delayed file open from recreating video.
        removeVideo(recording)
        scheduleFinishDeadline(recording)
        logger.notice("capture.aborted id=\(id.uuidString, privacy: .public)")
    }

    private func scheduleFinishDeadline(_ recording: Recording) {
        guard recording.finishTimeout == nil else { return }
        let id = recording.id
        recording.finishTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await self?.finishDeadline(id: id)
        }
    }

    private func finishDeadline(id: UUID) {
        guard let recording, recording.id == id else { return }
        self.recording = nil
        close(recording)
        removeVideo(recording)
        let error = recording.abortError ?? LipCaptureError.interrupted
        recording.start?.resume(throwing: error)
        for continuation in recording.finish { continuation.resume(throwing: error) }
        for continuation in recording.drain { continuation.resume() }
        logger.error("capture.finish_deadline id=\(id.uuidString, privacy: .public)")
        if recording.abortError == nil, !recording.stopRequested { recording.onInterruption(error) }
    }

    private func close(_ recording: Recording) {
        recording.startupTimeout?.cancel()
        recording.finishTimeout?.cancel()
        recording.session.stopRunning()
        recording.session.beginConfiguration()
        for input in recording.session.inputs { recording.session.removeInput(input) }
        recording.session.removeOutput(recording.output)
        recording.session.commitConfiguration()
    }

    private func removeVideo(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.directory)
    }

    private func add(_ device: AVCaptureDevice, to session: AVCaptureSession) throws {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw LipCaptureError.cannotAddInput }
        session.addInput(input)
    }

    fileprivate func didStart(id: UUID) {
        guard let recording, recording.id == id else { return }
        recording.startupTimeout?.cancel()
        recording.startupTimeout = nil
        if recording.abortError != nil {
            recording.output.stopRecording()
            recording.session.stopRunning()
            return
        }
        recording.start?.resume()
        recording.start = nil
        if recording.stopRequested {
            recording.output.stopRecording()
            recording.session.stopRunning()
        }
    }

    fileprivate func didFinish(id: UUID, directory: URL, error: Error?) {
        guard let recording, recording.id == id else {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        self.recording = nil
        close(recording)
        defer { for continuation in recording.drain { continuation.resume() } }
        logger.notice("capture.closed id=\(id.uuidString, privacy: .public) failed=\(error != nil, privacy: .public)")

        let completedDespiteError = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        let failure: Error? = recording.abortError
            ?? (error != nil && !completedDespiteError ? error : nil)
        if let failure {
            removeVideo(recording)
            recording.start?.resume(throwing: failure)
            for continuation in recording.finish { continuation.resume(throwing: failure) }
            if recording.abortError == nil, !recording.stopRequested { recording.onInterruption(failure) }
        } else if recording.start != nil {
            removeVideo(recording)
            recording.start?.resume(throwing: LipCaptureError.failedToStart)
            for continuation in recording.finish { continuation.resume(throwing: LipCaptureError.failedToStart) }
        } else {
            let clip = LipCaptureClip(url: recording.url,
                                      duration: CMTimeGetSeconds(recording.output.recordedDuration),
                                      directory: recording.directory)
            if recording.finish.isEmpty {
                let nativeError = error as NSError?
                if nativeError?.domain == AVFoundationErrorDomain,
                   nativeError?.code == AVError.maximumDurationReached.rawValue {
                    completed = (id, clip)
                    recording.onInterruption(LipCaptureError.recordingLimitReached)
                } else {
                    clip.remove()
                    recording.onInterruption(LipCaptureError.interrupted)
                }
            } else {
                for continuation in recording.finish { continuation.resume(returning: clip) }
            }
        }
    }
}

private final class LipCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var owner: LipCapture?
    var recordingID = UUID()
    let directory: URL

    init(owner: LipCapture, directory: URL) {
        self.owner = owner
        self.directory = directory
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        let id = recordingID
        Task { await owner?.didStart(id: id) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let id = recordingID
        let directory = directory
        Task { [weak owner] in
            if let owner {
                await owner.didFinish(id: id, directory: directory, error: error)
            } else {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}
