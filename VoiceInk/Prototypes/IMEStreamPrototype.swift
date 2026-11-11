// PROTOTYPE (proto/ime-stream-text) — throwaway, not production.
// Drives the Roma Stream input method for one hold: select it on key-down, stream guesses as marked
// text, commit the final text on release (confirmed by the input method), then restore the user's
// input source. If the input method cannot confirm, Roma falls back to its normal paste.
import Carbon
import Foundation
import os

@MainActor
final class IMEStreamPrototype {
    static let shared = IMEStreamPrototype()
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeIMEStream") }
    static let sourceID = "com.negentropi.inputmethod.RomaStream"
    private static let logger = Logger(subsystem: "com.negentropi.RomaJustTalk", category: "IMEStreamPrototype")

    /// A hold is in progress; only then may a guess switch the input source.
    private var armed = false
    /// Roma Stream is selected for this hold.
    private var active = false
    private var previousSource: TISInputSource?
    private var selectedAt = ContinuousClock.now
    private var pendingRestore: Task<Void, Never>?
    /// macOS drops a switch back that follows the switch too closely, leaving the app on Roma
    /// Stream (measured: 4 of 10 stuck at 0.1–0.3 s, 0 of 10 at 0.6 s and 1 s). Every later
    /// switch pair then flips it the other way.
    private static let minimumDwell = Duration.milliseconds(800)
    private var acks: [String: CheckedContinuation<String?, Never>] = [:]
    private var ackObserver: NSObjectProtocol?

    private init() {
        ackObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.negentropi.RomaStream.ack"), object: nil, queue: .main
        ) { note in
            let reply = note.object as? String ?? ""
            MainActor.assumeIsolated { IMEStreamPrototype.shared.received(reply) }
        }
    }

    /// Key-down. The input source is switched only once there is a guess to show, so a short
    /// tap, which never gets one, leaves it alone.
    func begin() {
        guard Self.isEnabled else { return }
        armed = true
    }

    private func select() {
        if let pendingRestore {
            // The previous hold's switch back has not run yet: Roma Stream is still selected.
            pendingRestore.cancel()
            self.pendingRestore = nil
            active = true
            return
        }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard Self.id(of: current) != Self.sourceID else { active = true; return }
        guard let stream = Self.source() else {
            Self.logger.error("Roma Stream is not enabled in System Settings; live text stays off")
            armed = false
            return
        }
        previousSource = current
        selectedAt = .now
        let status = TISSelectInputSource(stream)
        active = status == noErr
        Self.logger.notice("select: status=\(status, privacy: .public) previous=\(Self.id(of: current), privacy: .public)")
    }

    func showGuess(_ text: String) {
        guard armed, !text.isEmpty else { return }
        if !active { select() }
        guard active else { return }
        post("partial", text)
    }

    enum Commit { case committed, focusMoved, unavailable }

    /// Release: `.committed` once the input method confirmed the final text replaced its guess;
    /// `.focusMoved` when the user clicked, typed, or moved focus while the guess showed, which, like
    /// live typing, inserts nothing; `.unavailable` means paste as usual.
    func commit(_ text: String) async -> Commit {
        guard active else { return .unavailable }
        let reply = await request("commit", text)
        Self.logger.notice("commit: reply=\(reply ?? "timeout", privacy: .public)")
        await end()
        switch reply {
        case "committed": return .committed
        case "moved": return .focusMoved
        default: return .unavailable
        }
    }

    /// Any end (empty transcript, cancel, failure): remove a leftover guess and restore the input source.
    func end() async {
        armed = false
        guard active else { return }
        active = false
        let reply = await request("clear", "")
        Self.logger.notice("end: clear reply=\(reply ?? "timeout", privacy: .public)")
        // A new hold may have taken Roma Stream over while the clear was in flight.
        guard !active, let previousSource else { return }
        let wait = Self.minimumDwell - (ContinuousClock.now - selectedAt)
        pendingRestore = Task { @MainActor in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            self.pendingRestore = nil
            self.previousSource = nil
            let status = TISSelectInputSource(previousSource)
            Self.logger.notice("end: restore \(Self.id(of: previousSource), privacy: .public) status=\(status, privacy: .public) after \(String(describing: wait), privacy: .public) wait")
        }
    }

    private func request(_ kind: String, _ text: String) async -> String? {
        let token = UUID().uuidString
        return await withCheckedContinuation { continuation in
            acks[token] = continuation
            post(kind, token + "\n" + text)
            Task { @MainActor in
                // Longer than the input method's 1 s hold on updates, so a late ack can never race a fallback paste.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.acks.removeValue(forKey: token)?.resume(returning: nil)
            }
        }
    }

    private func received(_ reply: String) {
        let parts = reply.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        acks.removeValue(forKey: parts[0])?.resume(returning: parts[1])
    }

    private func post(_ kind: String, _ object: String) {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.negentropi.RomaStream.\(kind)"), object: object, userInfo: nil, deliverImmediately: true)
    }

    private static func source() -> TISInputSource? {
        let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: sourceID] as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private static func id(of source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
