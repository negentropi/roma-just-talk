import AppKit
import Foundation
import Testing
@testable import VoiceInk

@Suite(.serialized)
@MainActor
struct ClipboardRestorationOwnershipTests {
    @Test func unresolvedMenuPreparationRejectsACompetingClipboardWrite() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try #require(board.setString("original e\u{301} 🧪", forType: .string))
        let gate = ClipboardOwnershipGate()
        let first = ClipboardOwnershipAccess(board: board, gate: gate)
        let work = Task { @MainActor in
            try await CursorPaster.pasteWritingReplacement("first", expectedValue: "first", access: first,
                shouldCancel: { false }, pasteboard: board, restoreClipboard: true, restorationDelay: 0.25)
        }
        defer { gate.release(); work.cancel() }
        try await gate.waitUntilEntered()
        let ownedGeneration = board.changeCount
        let second = ClipboardOwnershipAccess(board: board)
        do {
            _ = try await CursorPaster.pasteWritingReplacement("second", expectedValue: "second", access: second,
                shouldCancel: { false }, pasteboard: board, restoreClipboard: true, restorationDelay: 0.25)
            Issue.record("An unresolved preparation must reject another owned clipboard writer")
        } catch CursorPaster.WritingPasteError.clipboardChanged { }
        #expect(second.attempts == 0)
        #expect(board.changeCount == ownedGeneration)
        #expect(board.string(forType: .string) == "first")
        gate.release()
        let result = try await work.value
        #expect(result == .confirmed)
        #expect(first.attempts == 1)
        try await CursorPaster.settlePendingClipboardRestore(pasteboard: board)
        #expect(board.string(forType: .string)?.utf16.elementsEqual("original e\u{301} 🧪".utf16) == true)
    }

    @Test func cancelingANewWaiterDoesNotCancelTheEarlierRestoration() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try #require(board.setString("original", forType: .string))
        let access = ClipboardOwnershipAccess(board: board)
        _ = try await CursorPaster.pasteWritingReplacement("forward", expectedValue: "forward", access: access,
            shouldCancel: { false }, pasteboard: board, restoreClipboard: true, restorationDelay: 0.5)
        var waiterStarted = false
        let waiter = Task { @MainActor in
            waiterStarted = true
            try await CursorPaster.settlePendingClipboardRestore(pasteboard: board)
        }
        for _ in 0..<100 where !waiterStarted { try await Task.sleep(for: .milliseconds(5)) }
        try #require(waiterStarted)
        waiter.cancel()
        do { try await waiter.value; Issue.record("Canceled waiter must throw") }
        catch is CancellationError { }
        try await CursorPaster.settlePendingClipboardRestore(pasteboard: board)
        #expect(board.string(forType: .string) == "original")
        #expect(access.attempts == 1)
    }

    @Test func cancellationDuringDeliveryObservationStillCommitsExactReadback() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try #require(board.setString("original", forType: .string))
        let access = ClipboardOwnershipAccess(board: board)
        access.delayReadback = true
        var confirmations = 0
        let work = Task { @MainActor in
            try await CursorPaster.pasteWritingReplacement("delivered", expectedValue: "delivered", access: access,
                shouldCancel: { false }, pasteboard: board, restoreClipboard: true, restorationDelay: 0.25,
                onConfirmed: { confirmations += 1 })
        }
        defer { work.cancel() }
        for _ in 0..<100 where access.reads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try #require(access.reads == 1)
        access.deliverReadback()
        work.cancel()
        let result = try await work.value
        #expect(result == .confirmed)
        #expect(confirmations == 1)
        #expect(access.attempts == 1)
        try await CursorPaster.settlePendingClipboardRestore(pasteboard: board)
        #expect(board.string(forType: .string) == "original")
    }

    @Test func confirmedCallbackPrecedesImmediateRestorationAndFiresOnce() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try #require(board.setString("original", forType: .string))
        let access = ClipboardOwnershipAccess(board: board)
        var seen: [String?] = []
        let result = try await CursorPaster.pasteWritingReplacement("delivered", expectedValue: "delivered", access: access,
            shouldCancel: { false }, pasteboard: board, restoreClipboard: true, restorationDelay: 0,
            onConfirmed: { seen.append(board.string(forType: .string)) })
        #expect(result == .confirmed)
        #expect(seen == ["delivered"])
        #expect(board.string(forType: .string) == "original")
    }

    @Test func unreadableOriginalFormatRefusesBeforeClipboardOrEditorMutation() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let provider = ClipboardUnreadableDataProvider()
        let item = NSPasteboardItem()
        let type = NSPasteboard.PasteboardType("com.negentropi.RomaJustTalk.tests.unreadable")
        try #require(item.setDataProvider(provider, forTypes: [type]))
        try #require(board.writeObjects([item]))
        let generation = board.changeCount
        let access = ClipboardOwnershipAccess(board: board)
        do {
            _ = try await CursorPaster.pasteWritingReplacement("new", expectedValue: "new", access: access,
                shouldCancel: { false }, pasteboard: board, restoreClipboard: true)
            Issue.record("Unreadable original formats must refuse the preparation")
        } catch CursorPaster.WritingPasteError.clipboardUnreadable { }
        #expect(board.changeCount == generation)
        #expect(access.attempts == 0)
        withExtendedLifetime(provider) { }
    }
}

@MainActor
private final class ClipboardOwnershipGate {
    private(set) var entered = false
    private var released = false
    func wait() async throws {
        entered = true
        for _ in 0..<1_000 {
            if released { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ClipboardOwnershipError.timeout
    }
    func waitUntilEntered() async throws {
        for _ in 0..<1_000 {
            if entered { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ClipboardOwnershipError.timeout
    }
    func release() { released = true }
}

private enum ClipboardOwnershipError: Error { case timeout }

private final class ClipboardUnreadableDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) { }
}

@MainActor
private final class ClipboardOwnershipAccess: CursorPaster.WritingPasteAccess {
    let board: NSPasteboard
    let gate: ClipboardOwnershipGate?
    private(set) var attempts = 0
    private(set) var reads = 0
    var delayReadback = false
    private var value = "before"
    init(board: NSPasteboard, gate: ClipboardOwnershipGate? = nil) { self.board = board; self.gate = gate }
    func validateTarget() throws { }
    func readValue() -> String? { reads += 1; return value }
    func deliverReadback() { value = board.string(forType: .string) ?? "" }
    func pressMenu(authorize: () throws -> Void, willAttempt: () -> Void) async throws -> CursorTextContextReader.CapturedMenuAttempt {
        try authorize()
        try await gate?.wait()
        try authorize()
        willAttempt()
        attempts += 1
        if !delayReadback { deliverReadback() }
        return .attempted(.success)
    }
}
