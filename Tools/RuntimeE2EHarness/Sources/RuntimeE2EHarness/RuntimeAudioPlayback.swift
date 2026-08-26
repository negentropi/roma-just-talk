import Darwin
import Foundation
import RuntimeE2ECore

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
    private let completionGraceSeconds: TimeInterval
    private let process = Process()
    private let stateLock = NSLock()
    private let terminationLock = NSLock()
    private var startedAt: TimeInterval?
    private var timedOut = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        fixtureURL: URL,
        device: RuntimeAudioDevice,
        expectedDurationSeconds: TimeInterval,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/afplay"),
        arguments: [String]? = nil,
        completionGraceSeconds: TimeInterval = RuntimePlaybackReleasePolicy.completionGraceSeconds
    ) {
        self.fixtureURL = fixtureURL
        self.device = device
        self.expectedDurationSeconds = expectedDurationSeconds
        self.completionGraceSeconds = completionGraceSeconds
        process.executableURL = executableURL
        process.arguments = arguments ?? [fixtureURL.path]
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
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.enforceTimeout()
        }
        self.timeoutWorkItem = timeoutWorkItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + expectedDurationSeconds + completionGraceSeconds,
            execute: timeoutWorkItem
        )
        return now
    }

    func waitUntilFinished() throws -> RuntimeAudioPlaybackResult {
        guard let startedAt else {
            throw RuntimeAudioPlaybackError.notStarted
        }
        let deadline = startedAt + expectedDurationSeconds + completionGraceSeconds
        while isProcessRunning && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        if isProcessRunning {
            enforceTimeout()
        }
        timeoutWorkItem?.cancel()
        guard !isProcessRunning else {
            throw RuntimeAudioPlaybackError.processCleanupFailed
        }
        if didTimeOut {
            throw RuntimeAudioPlaybackError.timedOut
        }
        guard process.terminationStatus == 0 else {
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
            forcedStopAtExpectedEnd: false
        )
    }

    func stop() throws {
        timeoutWorkItem?.cancel()
        guard terminateAndWait(markTimedOut: false) else {
            throw RuntimeAudioPlaybackError.processCleanupFailed
        }
    }

    private var isProcessRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process.isRunning
    }

    private var didTimeOut: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return timedOut
    }

    private func enforceTimeout() {
        _ = terminateAndWait(markTimedOut: true)
    }

    private func terminateAndWait(markTimedOut: Bool) -> Bool {
        terminationLock.lock()
        defer { terminationLock.unlock() }

        stateLock.lock()
        guard process.isRunning else {
            stateLock.unlock()
            return true
        }
        timedOut = timedOut || markTimedOut
        let processID = process.processIdentifier
        process.terminate()
        stateLock.unlock()

        waitForExit(timeoutSeconds: 0.1)
        guard isProcessRunning else { return true }
        Darwin.kill(processID, SIGKILL)
        waitForExit(timeoutSeconds: 1)
        return !isProcessRunning
    }

    private func waitForExit(timeoutSeconds: TimeInterval) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        while isProcessRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func verifyLifecycle() throws {
        let testDevice = RuntimeAudioDevice(
            id: 0,
            uid: "playback-check",
            name: "playback-check",
            inputChannels: 0,
            outputChannels: 0
        )
        let completedPlayback = RuntimeAudioPlayback(
            fixtureURL: URL(fileURLWithPath: "/dev/null"),
            device: testDevice,
            expectedDurationSeconds: 0.05,
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["0.01"],
            completionGraceSeconds: 0.1
        )
        _ = try completedPlayback.start()
        _ = try completedPlayback.waitUntilFinished()

        let stalledPlayback = RuntimeAudioPlayback(
            fixtureURL: URL(fileURLWithPath: "/dev/null"),
            device: testDevice,
            expectedDurationSeconds: 0.01,
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            completionGraceSeconds: 0.04
        )
        _ = try stalledPlayback.start()
        Thread.sleep(forTimeInterval: 0.5)
        guard !stalledPlayback.isProcessRunning else {
            throw RuntimeAudioPlaybackError.timeoutCheckFailed
        }
        do {
            _ = try stalledPlayback.waitUntilFinished()
            throw RuntimeAudioPlaybackError.timeoutCheckFailed
        } catch RuntimeAudioPlaybackError.timedOut {}

        let stubbornPlayback = RuntimeAudioPlayback(
            fixtureURL: URL(fileURLWithPath: "/dev/null"),
            device: testDevice,
            expectedDurationSeconds: 0.2,
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; exec /bin/sleep 5"],
            completionGraceSeconds: 0.3
        )
        _ = try stubbornPlayback.start()
        do {
            _ = try stubbornPlayback.waitUntilFinished()
            throw RuntimeAudioPlaybackError.timeoutCheckFailed
        } catch RuntimeAudioPlaybackError.timedOut {
            guard !stubbornPlayback.isProcessRunning,
                  stubbornPlayback.process.terminationReason == .uncaughtSignal,
                  stubbornPlayback.process.terminationStatus == SIGKILL else {
                throw RuntimeAudioPlaybackError.timeoutCheckFailed
            }
        }
    }
}

enum RuntimeAudioPlaybackError: Error, CustomStringConvertible {
    case audioDeviceNotFound
    case alreadyStarted
    case notStarted
    case timedOut
    case processFailed(Int32)
    case processCleanupFailed
    case timeoutCheckFailed

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
        case .processCleanupFailed:
            return "Audio playback process could not be stopped"
        case .timeoutCheckFailed:
            return "Playback timeout enforcement check failed"
        }
    }
}
