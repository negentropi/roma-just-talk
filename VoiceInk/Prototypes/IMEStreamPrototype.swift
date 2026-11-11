// PROTOTYPE (proto/ime-stream-text) — throwaway, not production.
// Drives the Roma Stream input method for one hold: stream guesses as marked text, commit the final
// text on release (confirmed by the input method). Roma Stream stays the user's input source, like
// any input method; Roma never switches sources, because macOS loses quick switches made from
// another app (the app stays on, or never turns on, the input method). When the user is on another
// input source, Roma types live as before. Without the input method's confirmation Roma pastes.
import Carbon
import Foundation
import os

@MainActor
final class IMEStreamPrototype {
    static let shared = IMEStreamPrototype()
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeIMEStream") }
    static let sourceID = "com.negentropi.inputmethod.RomaStream"
    private static let logger = Logger(subsystem: "com.negentropi.RomaJustTalk", category: "IMEStreamPrototype")

    /// This hold streams through Roma Stream.
    private var armed = false
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

    /// Key-down: whether this hold streams through Roma Stream (it is the current input source).
    func begin() -> Bool {
        guard Self.isEnabled else { return false }
        let current = Self.id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        armed = current == Self.sourceID
        Self.logger.notice("begin: source=\(current, privacy: .public) streaming=\(self.armed, privacy: .public)")
        return armed
    }

    func showGuess(_ text: String) {
        guard armed, !text.isEmpty else { return }
        post("partial", text)
    }

    enum Commit { case committed, focusMoved, unavailable }

    /// Release: `.committed` once the input method confirmed the final text replaced its guess;
    /// `.focusMoved` when the user clicked, typed, or moved focus while the guess showed, which, like
    /// live typing, inserts nothing; `.unavailable` means paste as usual.
    func commit(_ text: String) async -> Commit {
        guard armed else { return .unavailable }
        let reply = await request("commit", text)
        Self.logger.notice("commit: reply=\(reply ?? "timeout", privacy: .public)")
        await end()
        switch reply {
        case "committed": return .committed
        case "moved": return .focusMoved
        default: return .unavailable
        }
    }

    /// Any end (empty transcript, cancel, failure): remove a leftover guess.
    func end() async {
        guard armed else { return }
        armed = false
        let reply = await request("clear", "")
        Self.logger.notice("end: clear reply=\(reply ?? "timeout", privacy: .public)")
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

    private static func id(of source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
