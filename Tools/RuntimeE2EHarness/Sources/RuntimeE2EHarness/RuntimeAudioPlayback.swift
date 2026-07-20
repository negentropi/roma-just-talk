import Foundation

struct RuntimeAudioPlaybackResult: Codable {
    let fixturePath: String
    let deviceID: UInt32
    let deviceName: String
    let durationSeconds: Double
    let startedAtSystemUptime: Double
    let finishedAtSystemUptime: Double
    let forcedStopAtExpectedEnd: Bool
}

struct RuntimeAudioThroughVoiceInkProbeReport: Codable {
    let voiceInkSession: RuntimeVoiceInkSessionInfo
    let playback: RuntimeAudioPlaybackResult
    let restoredOriginalState: Bool
}

final class RuntimeAudioPlayback: @unchecked Sendable {
    private let fixtureURL: URL
    private let device: RuntimeAudioDevice
    private let expectedDurationSeconds: TimeInterval
    private let process = Process()
    private let stateLock = NSLock()
    private var startedAt: TimeInterval?
    private var forcedStopAtExpectedEnd = false
    private var automaticStopWorkItem: DispatchWorkItem?

    init(
        fixtureURL: URL,
        device: RuntimeAudioDevice,
        expectedDurationSeconds: TimeInterval
    ) {
        self.fixtureURL = fixtureURL
        self.device = device
        self.expectedDurationSeconds = expectedDurationSeconds
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [fixtureURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
    }

    func start() throws -> TimeInterval {
        guard startedAt == nil else {
            throw RuntimeAudioPlaybackError.alreadyStarted
        }
        try process.run()
        let now = ProcessInfo.processInfo.systemUptime
        startedAt = now
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopAtExpectedEnd()
        }
        automaticStopWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + expectedDurationSeconds + 0.25,
            execute: workItem
        )
        return now
    }

    func waitUntilFinished(timeoutSeconds: TimeInterval? = nil) throws -> RuntimeAudioPlaybackResult {
        guard let startedAt else {
            throw RuntimeAudioPlaybackError.notStarted
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds ?? expectedDurationSeconds + 5)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < terminationDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
        }
        guard !process.isRunning else {
            throw RuntimeAudioPlaybackError.timedOut
        }
        automaticStopWorkItem?.cancel()
        stateLock.lock()
        let forcedStop = forcedStopAtExpectedEnd
        stateLock.unlock()
        guard forcedStop || process.terminationStatus == 0 else {
            throw RuntimeAudioPlaybackError.processFailed(process.terminationStatus)
        }
        let finishedAt = ProcessInfo.processInfo.systemUptime
        return RuntimeAudioPlaybackResult(
            fixturePath: fixtureURL.path,
            deviceID: device.id,
            deviceName: device.name,
            durationSeconds: expectedDurationSeconds,
            startedAtSystemUptime: startedAt,
            finishedAtSystemUptime: finishedAt,
            forcedStopAtExpectedEnd: forcedStop
        )
    }

    func stop() {
        automaticStopWorkItem?.cancel()
        if process.isRunning {
            process.terminate()
        }
    }

    private func stopAtExpectedEnd() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard process.isRunning else { return }
        forcedStopAtExpectedEnd = true
        process.terminate()
    }
}

enum RuntimeAudioPlaybackError: Error, CustomStringConvertible {
    case audioDeviceNotFound
    case alreadyStarted
    case notStarted
    case timedOut
    case processFailed(Int32)

    var description: String {
        switch self {
        case .audioDeviceNotFound:
            return "Configured BlackHole audio device was not found"
        case .alreadyStarted:
            return "Audio playback already started"
        case .notStarted:
            return "Audio playback was not started"
        case .timedOut:
            return "Audio playback timed out"
        case .processFailed(let status):
            return "afplay failed with status \(status)"
        }
    }
}
