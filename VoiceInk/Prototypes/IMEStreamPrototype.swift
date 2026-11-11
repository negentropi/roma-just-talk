// PROTOTYPE (proto/ime-stream-text) — throwaway, not production.
// Drives the Roma Stream input method for one hold: stream guesses as marked text, commit the final
// text on release (confirmed by the input method). Roma Stream stays the user's input source, like
// any input method; Roma never switches sources, because macOS loses quick switches made from
// another app (the app stays on, or never turns on, the input method). When the user is on another
// input source, Roma types live as before. Without the input method's confirmation Roma pastes.
import Carbon
import Foundation
import os

/// The channel to Roma Stream; holds come from `begin()`.
@MainActor
final class IMEStreamPrototype {
    static let shared = IMEStreamPrototype()
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeIMEStream") }
    static let sourceID = "com.negentropi.inputmethod.RomaStream"
    fileprivate static let logger = Logger(subsystem: "com.negentropi.RomaJustTalk", category: "IMEStreamPrototype")

    /// The newest hold; only its "shown" confirmations count.
    private weak var activeHold: IMEStreamHold?
    private var acks: [String: CheckedContinuation<String?, Never>] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.negentropi.RomaStream.ack"), object: nil, queue: .main) { note in
            let reply = note.object as? String ?? ""
            MainActor.assumeIsolated { IMEStreamPrototype.shared.received(reply) }
        })
        observers.append(center.addObserver(forName: .init("com.negentropi.RomaStream.shown"), object: nil, queue: .main) { note in
            let holdID = note.object as? String
            MainActor.assumeIsolated {
                if let hold = IMEStreamPrototype.shared.activeHold, hold.id == holdID { hold.guessShown = true }
            }
        })
        observers.append(center.addObserver(forName: .init("com.negentropi.RomaStream.seen"), object: nil, queue: .main) { note in
            let holdID = note.object as? String
            MainActor.assumeIsolated {
                if let hold = IMEStreamPrototype.shared.activeHold, hold.id == holdID { hold.seen = true }
            }
        })
    }

    /// Key-down: a hold that streams through Roma Stream, or nil when another input source is
    /// selected (Roma types live instead).
    func begin() -> IMEStreamHold? {
        guard Self.isEnabled else { return nil }
        let current = Self.id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        Self.logger.notice("begin: source=\(current, privacy: .public)")
        guard current == Self.sourceID else { return nil }
        let hold = IMEStreamHold(channel: self)
        activeHold = hold
        return hold
    }

    /// Fields are joined by newlines; only the last may contain one.
    fileprivate func post(_ kind: String, _ fields: [String]) {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.negentropi.RomaStream.\(kind)"), object: fields.joined(separator: "\n"), userInfo: nil, deliverImmediately: true)
    }

    fileprivate func request(_ kind: String, _ fields: [String], timeout: Duration) async -> String? {
        let token = UUID().uuidString
        return await withCheckedContinuation { continuation in
            acks[token] = continuation
            post(kind, [token] + fields)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.acks.removeValue(forKey: token)?.resume(returning: nil)
            }
        }
    }

    private func received(_ reply: String) {
        let parts = reply.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        acks.removeValue(forKey: parts[0])?.resume(returning: parts[1])
    }

    private static func id(of source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// One Shift hold streaming through Roma Stream. Every message carries its ID, so an older hold's
/// late cleanup can never touch a newer one.
@MainActor
final class IMEStreamHold {
    /// `.uncertain`: Roma Stream did not answer, so the text may already be in the field (or a guess
    /// may still be up); pasting could duplicate it, so Roma inserts nothing and points to History.
    /// `.cancelled`: the hold was cancelled while Roma waited on Roma Stream; insert nothing.
    enum Commit { case committed, focusMoved, uncertain, cancelled, unavailable }

    let id = UUID().uuidString
    private let channel: IMEStreamPrototype
    /// Roma Stream confirmed it showed a guess in a field. Without one, release pastes at once
    /// instead of waiting on an input method that has no field to commit into.
    fileprivate var guessShown = false
    /// A guess was sent; it may still be on its way to the field.
    private var guessSent = false
    /// Roma Stream received this hold. If it never did (not running), no guess can be on screen.
    fileprivate var seen = false
    private var ended = false

    fileprivate init(channel: IMEStreamPrototype) {
        self.channel = channel
    }

    func showGuess(_ text: String) {
        guard !ended, !text.isEmpty else { return }
        guessSent = true
        channel.post("partial", [id, text])
    }

    /// Release: `.committed` once the input method confirmed the final text replaced its guess;
    /// `.focusMoved` when the user clicked, typed, or moved focus while the guess showed, which, like
    /// live typing, inserts nothing; `.unavailable` means paste as usual.
    func commit(_ text: String) async -> Commit {
        // Ended before release finished: the hold was cancelled; insert nothing.
        guard !ended else { return .cancelled }
        defer { end() }
        guard guessShown else {
            // Take down a guess still on its way before Roma pastes, or Chrome would keep it as text.
            guard guessSent else { return .unavailable }
            let reply = await channel.request("clear", [id], timeout: .milliseconds(300))
            IMEStreamPrototype.logger.notice("commit: no guess shown; clear reply=\(reply ?? "timeout", privacy: .public)")
            if ended { return .cancelled }
            switch reply {
            case nil: return seen ? .uncertain : .unavailable
            case "moved": return .focusMoved
            // Roma Stream never got this hold (it restarted): nothing of it can be on screen.
            case "stale": return seen ? .focusMoved : .unavailable
            default: return .unavailable
            }
        }
        // Roma Stream refuses the commit after this deadline, which passes before Roma stops waiting:
        // once Roma falls back to pasting, a delayed commit can no longer insert the text a second time.
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        let reply = await channel.request("commit", [id, String(deadline), text], timeout: .milliseconds(1500))
        IMEStreamPrototype.logger.notice("commit: reply=\(reply ?? "timeout", privacy: .public)")
        if ended, reply != "committed" { return .cancelled }
        switch reply {
        case "committed": return .committed
        // "stale": a newer hold replaced this hold's guess; pasting would land in its way.
        case "moved", "stale": return .focusMoved
        case nil: return .uncertain
        // "late", "nofield": Roma Stream inserted nothing and took its guess down.
        default: return .unavailable
        }
    }

    /// Any end (empty transcript, cancel, failure): remove this hold's leftover guess. Never waited
    /// on, so it cannot delay the paste.
    func end() {
        guard !ended else { return }
        ended = true
        channel.post("clear", ["", id])
    }
}
