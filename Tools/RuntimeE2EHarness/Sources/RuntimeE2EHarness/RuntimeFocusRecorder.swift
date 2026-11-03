import AppKit
import Foundation

// Notification receipt times show focus order without polling or reading window/field contents.
final class RuntimeFocusRecorder: @unchecked Sendable {
    private let center = NSWorkspace.shared.notificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var output: FileHandle?
    private var writeErrorReported = false

    init(outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: outputURL, options: .atomic)
        output = try FileHandle(forWritingTo: outputURL)
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.recordActivation(notification)
        }
        do {
            try append(
                kind: "initialFrontmost",
                application: NSWorkspace.shared.frontmostApplication,
                timestamp: Date(),
                systemUptimeSeconds: ProcessInfo.processInfo.systemUptime
            )
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        // The notification callback can overlap teardown; all mutable state shares this lock.
        lock.lock()
        let activeObserver = observer
        observer = nil
        let activeOutput = output
        output = nil
        lock.unlock()
        if let activeObserver {
            center.removeObserver(activeObserver)
        }
        try? activeOutput?.close()
    }

    func recordCurrent(kind: String) {
        record(kind: kind, application: NSWorkspace.shared.frontmostApplication)
    }

    private func recordActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }
        record(kind: "didActivateApplication", application: application)
    }

    private func record(kind: String, application: NSRunningApplication?) {
        do {
            try append(
                kind: kind,
                application: application,
                timestamp: Date(),
                systemUptimeSeconds: ProcessInfo.processInfo.systemUptime
            )
        } catch {
            lock.lock()
            defer { lock.unlock() }
            if !writeErrorReported {
                fputs("Focus evidence write failed: \(error)\n", stderr)
                writeErrorReported = true
            }
        }
    }

    private func append(
        kind: String,
        application: NSRunningApplication?,
        timestamp: Date,
        systemUptimeSeconds: TimeInterval
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let output else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let event: [String: Any] = [
            "event": kind,
            "timestamp": formatter.string(from: timestamp),
            "systemUptimeSeconds": systemUptimeSeconds,
            "pid": application.map { NSNumber(value: $0.processIdentifier) as Any } ?? NSNull(),
            "bundleID": jsonValue(application?.bundleIdentifier),
            "name": jsonValue(application?.localizedName),
            "bundlePath": jsonValue(application?.bundleURL?.path)
        ]
        var data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        data.append(0x0A)
        try output.write(contentsOf: data)
    }

    private func jsonValue(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }
}
