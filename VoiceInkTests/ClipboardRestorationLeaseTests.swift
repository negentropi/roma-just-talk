import AppKit
import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized, .enabled(if: ClipboardLeaseInputs.isEnabled), .timeLimit(.minutes(2)))
@MainActor
struct ClipboardRestorationLeaseTests {
    @Test func nestedWritingPastesRestoreOriginalAllFormatClipboard() async throws {
        try await run("nestedWritingPastesRestoreOriginalAllFormatClipboard", general: false) { fixture in
            try await fixture.forward()
            try fixture.requestSecond()
            try await fixture.second()
            try await fixture.waitBeyondLastDeadline()
            let restored = try fixture.isOriginal()
            try fixture.finish(originalRestored: restored, postcondition: restored)
            #expect(restored, "nestedWritingPastesRestoreOriginalAllFormatClipboard: original all-format clipboard must survive overlapping owned pastes")
        }
    }

    @Test func writingThenOrdinaryPasteRestoresOriginalAllFormatClipboard() async throws {
        try await run("writingThenOrdinaryPasteRestoresOriginalAllFormatClipboard", general: true) { fixture in
            try await fixture.forward()
            try fixture.requestSecond()
            try await fixture.second()
            try await fixture.ordinary()
            try await fixture.waitBeyondLastDeadline()
            let restored = try fixture.isOriginal()
            try fixture.finish(originalRestored: restored, postcondition: restored)
            #expect(restored, "writingThenOrdinaryPasteRestoresOriginalAllFormatClipboard: original all-format clipboard must survive overlapping owned pastes")
        }
    }

    @Test func preparedOrdinaryPasteDoesNotRestoreRetiredWritingPayload() async throws {
        try await run("preparedOrdinaryPasteDoesNotRestoreRetiredWritingPayload", general: true) { fixture in
            try await fixture.forward()
            try fixture.requestSecond()
            let context = try #require(CursorPaster.preparePasteContext())
            try fixture.record("prepared-context-captured")
            try await fixture.ordinary(prepared: context)
            try await fixture.waitBeyondLastDeadline()
            let restored = try fixture.isOriginal()
            try fixture.finish(originalRestored: restored, postcondition: restored)
            #expect(restored, "preparedOrdinaryPasteDoesNotRestoreRetiredWritingPayload: original all-format clipboard must survive overlapping owned pastes")
        }
    }

    @Test func singleWritingPasteHonorsDefaultRestorationDeadline() async throws {
        try await run("singleWritingPasteHonorsDefaultRestorationDeadline", general: false) { fixture in
            try await fixture.forward()
            try await fixture.waitBeforeDefaultDeadline()
            try fixture.record("before-deadline")
            let stillTemporary = try fixture.isTemporary(ClipboardLeaseFixture.forwardText)
            try await fixture.waitBeyondLastDeadline()
            let restored = try fixture.isOriginal()
            let passed = stillTemporary && restored
            try fixture.finish(originalRestored: restored, postcondition: passed)
            #expect(passed, "Single confirmed writing paste must retain its temporary payload until the default deadline, then restore every original format")
        }
    }

    @Test func newerClipboardCopySurvivesWritingRestorationDeadline() async throws {
        try await run("newerClipboardCopySurvivesWritingRestorationDeadline", general: false) { fixture in
            try await fixture.forward()
            let marker = try #require(fixture.board.string(forType: ClipboardManager.pasteSessionType))
            let newerItem = NSPasteboardItem()
            try #require(newerItem.setString(ClipboardLeaseFixture.forwardText, forType: .string))
            try #require(newerItem.setString(marker, forType: ClipboardManager.pasteSessionType))
            try #require(newerItem.setData(Data([8, 0, 7, 255]), forType: ClipboardLeaseFixture.binaryType))
            fixture.board.clearContents()
            try #require(fixture.board.writeObjects([newerItem]))
            try fixture.record("newer-copy")
            let newer = try fixture.snapshot()
            let newerGeneration = fixture.board.changeCount
            try await fixture.waitBeyondLastDeadline()
            let passed = try fixture.snapshot() == newer && fixture.board.changeCount == newerGeneration
            try fixture.finish(originalRestored: false, postcondition: passed)
            #expect(passed, "A newer clipboard generation with the same temporary text and marker must remain exact after the restoration deadline")
        }
    }

    private func run(
        _ name: String,
        general: Bool,
        body: (ClipboardLeaseFixture) async throws -> Void
    ) async throws {
        let fixture = try ClipboardLeaseFixture(test: name, general: general)
        defer { fixture.close() }
        do {
            try fixture.prepare()
            try await body(fixture)
        } catch {
            fixture.recordFailure(error)
            throw error
        }
    }
}

private enum ClipboardLeaseInputs {
    static func value(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_" + key]
    }

    static var isEnabled: Bool {
        value("RJT_CLIPBOARD_LEASE_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }
}

private struct ClipboardLeaseFormat: Codable, Equatable {
    let type: String
    let dataBase64: String
}

private struct ClipboardLeaseEvent: Codable {
    let name: String
    let elapsedSeconds: Double
    let changeCount: Int
    let items: [[ClipboardLeaseFormat]]
    let plainText: String?
    let plainTextUTF8: [UInt8]?
    let plainTextUTF16: [UInt16]?
}

@MainActor
private final class ClipboardLeaseFixture {
    static let binaryType = NSPasteboard.PasteboardType("com.negentropi.RomaJustTalk.tests.clipboard-lease.binary")
    static let forwardText = "FORWARD e\u{301} 🧪\r\nF"
    static let secondText = "INVERSE 🧭\nU"
    static let ordinaryText = "ORDINARY 🦉\r\nO"
    private static let originalText = "Original cafe\u{301} 🧬\r\nC "
    private static let delay = VoiceInkPastePreference.defaultClipboardRestoreDelay
    private static let preferenceKeys = [
        VoiceInkPastePreference.restoreClipboardAfterPasteKey,
        VoiceInkPastePreference.clipboardRestoreDelayKey,
        VoiceInkPasteMethod.userDefaultsKey,
        VoiceInkPasteMethod.legacyAppleScriptPasteKey
    ]

    let board: NSPasteboard
    private let test: String
    private let isGeneral: Bool
    private let output: URL
    private let start = ProcessInfo.processInfo.systemUptime
    private let preferences: [String: Any]
    private let priorContents: [[ClipboardLeaseFormat]]
    private var original: [[ClipboardLeaseFormat]] = []
    private var events: [ClipboardLeaseEvent] = []
    private var lastReturn = 0.0
    private var firstDeadline = 0.0
    private var beganBeforeFirstDeadline: Bool?
    private var confirmedWritingPastes = 0
    private var menuAttempts = 0
    private var ordinaryAttempts = 0
    private var originalRestored = false
    private var postconditionPassed = false
    private var setupValid = false
    private var completed = false
    private var failure: String?
    private let document = ClipboardLeaseDocument()

    init(test: String, general: Bool) throws {
        #if !LOCAL_BUILD
        throw ClipboardLeaseError.notDisposableHost
        #endif
        guard ClipboardLeaseInputs.isEnabled,
              ClipboardLeaseInputs.value("RUNNER_ENVIRONMENT") == "github-hosted",
              let directory = ClipboardLeaseInputs.value("RJT_CLIPBOARD_LEASE_EVIDENCE"),
              directory.hasPrefix("/"),
              let runnerTemporary = ClipboardLeaseInputs.value("RUNNER_TEMP"),
              directory.hasPrefix(runnerTemporary + "/"),
              Bundle.main.bundleIdentifier == "com.negentropi.RomaJustTalk",
              Bundle.main.executableURL?.lastPathComponent == "roma just talk" else {
            throw ClipboardLeaseError.notDisposableHost
        }
        self.test = test
        isGeneral = general
        output = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(test + ".json")
        board = general ? .general : .withUniqueName()
        let domain = UserDefaults.standard.persistentDomain(forName: "com.negentropi.RomaJustTalk") ?? [:]
        preferences = domain.filter { Self.preferenceKeys.contains($0.key) }
        priorContents = try Self.snapshot(board)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write()
    }

    func prepare() throws {
        UserDefaults.standard.set(true, forKey: VoiceInkPastePreference.restoreClipboardAfterPasteKey)
        UserDefaults.standard.set(Self.delay, forKey: VoiceInkPastePreference.clipboardRestoreDelayKey)
        VoiceInkPasteMethod.setCurrent(.standard)
        try #require(Self.delay == 2.0)
        try #require(VoiceInkPastePreference.minimumClipboardRestoreDelay == 0.25)
        try #require(VoiceInkPastePreference.boundedClipboardRestoreDelay() == Self.delay)
        try #require(VoiceInkPastePreference.shouldRestoreClipboardAfterPaste())
        try seedOriginal()
        setupValid = true
    }

    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - start }

    func record(_ name: String) throws {
        let before = board.changeCount
        let items = try snapshot()
        let plainText = board.string(forType: .string)
        try #require(board.changeCount == before, "Clipboard changed while recording observation")
        events.append(.init(
            name: name, elapsedSeconds: elapsed, changeCount: before, items: items,
            plainText: plainText, plainTextUTF8: plainText.map { Array($0.utf8) },
            plainTextUTF16: plainText.map { Array($0.utf16) }
        ))
    }

    func forward() async throws {
        let access = ClipboardLeaseAccess(board: board, document: document)
        let result = try await CursorPaster.pasteWritingReplacement(
            Self.forwardText, expectedValue: "prefix " + Self.forwardText + " suffix",
            access: access, shouldCancel: { false }, pasteboard: board
        )
        try #require(result == .confirmed, "Forward writing paste must actually confirm")
        try #require(access.attempts == 1)
        confirmedWritingPastes += 1
        menuAttempts += access.attempts
        lastReturn = elapsed
        firstDeadline = lastReturn + Self.delay
        try record("forward-confirmed")
        try #require(try isTemporary(Self.forwardText))
    }

    func requestSecond() throws {
        beganBeforeFirstDeadline = elapsed < firstDeadline
        try #require(beganBeforeFirstDeadline == true, "Second request must begin while the first restore is pending")
        try record("second-requested")
    }

    func second() async throws {
        document.range = NSRange(location: 7, length: Self.forwardText.utf16.count)
        let access = ClipboardLeaseAccess(board: board, document: document)
        let result = try await CursorPaster.pasteWritingReplacement(
            Self.secondText, expectedValue: "prefix " + Self.secondText + " suffix",
            access: access, shouldCancel: { false }, pasteboard: board
        )
        try #require(result == .confirmed, "Second writing paste must actually confirm")
        try #require(access.attempts == 1)
        confirmedWritingPastes += 1
        menuAttempts += access.attempts
        lastReturn = elapsed
        try record("second-confirmed")
        try #require(try isTemporary(Self.secondText))
    }

    func ordinary(prepared: CursorPaster.PreparedPasteContext? = nil) async throws {
        try #require(isGeneral)
        try record("ordinary-requested")
        CursorPaster.configureAccessibilityTextInserterForTesting()
        CursorPaster.configurePasteCommandPosterForTesting { [self] _ in
            ordinaryAttempts += 1
            guard board.string(forType: .string)?.utf16.elementsEqual(Self.ordinaryText.utf16) == true else {
                return .commandNotPosted
            }
            return .commandPosted
        }
        defer { CursorPaster.configurePasteCommandPosterForTesting() }
        let result = await CursorPaster.startPasteAtCursor(Self.ordinaryText, preparedContext: prepared).value
        try #require(result == .commandPosted, "Ordinary paste must post through the existing command seam")
        try #require(ordinaryAttempts == 1)
        lastReturn = elapsed
        try record("ordinary-posted")
        try #require(try isTemporary(Self.ordinaryText))
    }

    func waitUntil(_ deadline: Double) async throws {
        let remaining = deadline - elapsed
        if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
    }

    func waitBeyondLastDeadline() async throws {
        try await waitUntil(lastReturn + Self.delay + 0.35)
        try record("after-last-deadline")
    }

    func waitBeforeDefaultDeadline() async throws {
        try await waitUntil(lastReturn + 1.65)
    }

    func isOriginal() throws -> Bool { try snapshot() == original }

    func isTemporary(_ text: String) throws -> Bool {
        let generation = board.changeCount
        let result = board.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true
            && board.string(forType: ClipboardManager.pasteSessionType) != nil
        try #require(board.changeCount == generation)
        return result
    }

    func snapshot() throws -> [[ClipboardLeaseFormat]] { try Self.snapshot(board) }

    private static func snapshot(_ board: NSPasteboard) throws -> [[ClipboardLeaseFormat]] {
        let generation = board.changeCount
        let value = try (board.pasteboardItems ?? []).map { item in
            try item.types.sorted { $0.rawValue < $1.rawValue }.map { type in
                ClipboardLeaseFormat(type: type.rawValue, dataBase64: try #require(item.data(forType: type)).base64EncodedString())
            }
        }
        try #require(board.changeCount == generation, "Clipboard snapshot must have one stable generation")
        return value
    }

    private func seedOriginal() throws {
        let first = NSPasteboardItem()
        let second = NSPasteboardItem()
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jQ3sAAAAASUVORK5CYII="))
        try #require(first.setString(Self.originalText, forType: .string))
        try #require(first.setData(png, forType: .png))
        try #require(first.setData(Data([0, 255, 1, 128, 0, 13, 10]), forType: Self.binaryType))
        try #require(second.setString("Second item 🧿\r\n", forType: .string))
        try #require(second.setData(Data("{\\rtf1\\ansi Second item}".utf8), forType: .rtf))
        board.clearContents()
        try #require(board.writeObjects([first, second]))
        original = try snapshot()
        try record("original")
        try #require(original.count == 2)
        let expected: [[ClipboardLeaseFormat]] = [
            [
                .init(type: NSPasteboard.PasteboardType.string.rawValue, dataBase64: Data(Self.originalText.utf8).base64EncodedString()),
                .init(type: NSPasteboard.PasteboardType.png.rawValue, dataBase64: png.base64EncodedString()),
                .init(type: Self.binaryType.rawValue, dataBase64: Data([0, 255, 1, 128, 0, 13, 10]).base64EncodedString())
            ],
            [
                .init(type: NSPasteboard.PasteboardType.string.rawValue, dataBase64: Data("Second item 🧿\r\n".utf8).base64EncodedString()),
                .init(type: NSPasteboard.PasteboardType.rtf.rawValue, dataBase64: Data("{\\rtf1\\ansi Second item}".utf8).base64EncodedString())
            ]
        ]
        for index in expected.indices {
            for format in expected[index] {
                try #require(original[index].contains(format), "Every explicitly written clipboard format must retain its exact bytes")
            }
        }
    }

    func finish(originalRestored: Bool, postcondition: Bool) throws {
        self.originalRestored = originalRestored
        postconditionPassed = postcondition
        completed = true
        try write()
    }

    func recordFailure(_ error: Error) {
        failure = String(describing: error)
        completed = false
        try? write()
    }

    private func write() throws {
        let payload: [String: Any] = [
            "version": 1, "test": test, "completed": completed, "error": failure as Any? ?? NSNull(),
            "setupValid": setupValid, "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "bundleIdentifier": Bundle.main.bundleIdentifier as Any? ?? NSNull(),
            "executablePath": Bundle.main.executableURL?.path as Any? ?? NSNull(),
            "scope": "clipboard restoration only; controlled menu/document access",
            "pasteboardKind": isGeneral ? "general" : "unique", "timerDelaySeconds": Self.delay,
            "minimumTimerDelaySeconds": VoiceInkPastePreference.minimumClipboardRestoreDelay,
            "originalRestored": originalRestored, "postconditionPassed": postconditionPassed,
            "beganBeforeFirstDeadline": beganBeforeFirstDeadline as Any? ?? NSNull(),
            "elapsedSeconds": elapsed, "confirmedWritingPastes": confirmedWritingPastes,
            "menuAttempts": menuAttempts, "ordinaryAttempts": ordinaryAttempts,
            "events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(events))
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]).write(to: output, options: .atomic)
    }

    func close() {
        CursorPaster.configurePasteCommandPosterForTesting()
        CursorPaster.configureAccessibilityTextInserterForTesting()
        let defaults = UserDefaults.standard
        for key in Self.preferenceKeys {
            if let value = preferences[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        if isGeneral {
            // Restore only the exact generation last observed by this disposable test.
            if let last = events.last, board.changeCount == last.changeCount,
               (try? snapshot()) == last.items, board.changeCount == last.changeCount {
                let items = priorContents.map { formats in
                    let item = NSPasteboardItem()
                    for format in formats {
                        if let data = Data(base64Encoded: format.dataBase64) {
                            #expect(item.setData(data, forType: .init(format.type)))
                        } else {
                            Issue.record("Saved clipboard format could not be decoded during fixture cleanup")
                        }
                    }
                    return item
                }
                board.clearContents()
                if !items.isEmpty { #expect(board.writeObjects(items)) }
                do {
                    #expect(try snapshot() == priorContents, "Disposable general pasteboard cleanup must restore every prior format")
                } catch {
                    Issue.record("Disposable clipboard cleanup failed: \(error)")
                }
            }
        } else {
            board.releaseGlobally()
        }
    }
}

private enum ClipboardLeaseError: Error { case notDisposableHost, targetChanged }

@MainActor
private final class ClipboardLeaseDocument {
    var value = "prefix old suffix"
    var range = NSRange(location: 7, length: 3)
}

@MainActor
private final class ClipboardLeaseAccess: CursorPaster.WritingPasteAccess {
    let board: NSPasteboard
    let document: ClipboardLeaseDocument
    let capturedValue: String
    let capturedRange: NSRange
    private(set) var attempts = 0

    init(board: NSPasteboard, document: ClipboardLeaseDocument) {
        self.board = board
        self.document = document
        capturedValue = document.value
        capturedRange = document.range
    }

    func validateTarget() throws {
        guard document.value.utf16.elementsEqual(capturedValue.utf16), document.range == capturedRange else {
            throw ClipboardLeaseError.targetChanged
        }
    }

    func readValue() -> String? { document.value }

    func pressMenu(authorize: () throws -> Void, willAttempt: () -> Void) async throws
        -> CursorTextContextReader.CapturedMenuAttempt {
        try authorize()
        let payload = try #require(board.string(forType: .string))
        willAttempt()
        attempts += 1
        document.value = (document.value as NSString).replacingCharacters(in: document.range, with: payload)
        document.range = NSRange(location: document.range.location + payload.utf16.count, length: 0)
        return .attempted(.success)
    }
}
