import AppKit
import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct CapturedWritingPasteTests {
    @Test func targetDriftDuringDiscoveryLeavesTheNewDocumentAndClipboardUntouched() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.duringDiscovery = {
            await Task.yield()
            fixture.access.document = "User's newer document"
        }

        await #expect(throws: WritingPasteFixtureError.targetChanged) {
            try await fixture.replace()
        }

        #expect(fixture.access.document == "User's newer document")
        #expect(fixture.access.attempts == 0)
        #expect(fixture.board.string(forType: .string) == "Previous clipboard")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == nil)
    }

    @Test func cancellationDuringDiscoveryRestoresTheOwnedClipboardWithoutWriting() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.duringDiscovery = {
            await Task.yield()
            fixture.access.cancelled = true
        }

        await #expect(throws: CancellationError.self) {
            try await fixture.replace()
        }

        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 0)
        #expect(fixture.board.string(forType: .string) == "Previous clipboard")
    }

    @Test func focusOrSelectionDriftDuringDiscoveryPreventsThePaste() async throws {
        for moveSelection in [false, true] {
            let fixture = WritingPasteFixture()
            defer { fixture.close() }
            fixture.copy("Previous clipboard")
            fixture.access.duringDiscovery = {
                await Task.yield()
                if moveSelection {
                    fixture.access.range = NSRange(location: 0, length: 6)
                } else {
                    fixture.access.focused = false
                }
            }

            await #expect(throws: WritingPasteFixtureError.targetChanged) {
                try await fixture.replace()
            }

            #expect(fixture.access.document == "prefix old suffix")
            #expect(fixture.access.attempts == 0)
            #expect(fixture.board.string(forType: .string) == "Previous clipboard")
        }
    }

    @Test func newerClipboardCopyDuringDiscoverySurvivesRefusal() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.duringDiscovery = {
            await Task.yield()
            fixture.copy("New user copy")
        }

        do {
            _ = try await fixture.replace()
            Issue.record("A newer clipboard copy must refuse document delivery.")
        } catch CursorPaster.WritingPasteError.clipboardChanged {}

        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 0)
        #expect(fixture.board.string(forType: .string) == "New user copy")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == nil)
    }

    @Test func unavailableMenuRestoresClipboardEvenWhenSuccessfulPastesWouldKeepIt() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.behavior = .unavailable

        let result = try await fixture.replace(restoreClipboard: false)

        #expect(result == .notAttempted)
        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 0)
        #expect(fixture.board.string(forType: .string) == "Previous clipboard")
    }

    @Test func aNewClipboardGenerationWithTheSameTextAndMarkerStillRefusesPosting() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        var copiedChangeCount: Int?
        var copiedMarker: String?
        fixture.access.duringDiscovery = {
            await Task.yield()
            let text = try #require(fixture.board.string(forType: .string))
            let marker = try #require(fixture.board.string(forType: ClipboardManager.pasteSessionType))
            fixture.copy(text)
            #expect(fixture.board.setString(marker, forType: ClipboardManager.pasteSessionType))
            copiedChangeCount = fixture.board.changeCount
            copiedMarker = marker
        }

        do {
            _ = try await fixture.replace()
            Issue.record("A new clipboard generation must refuse posting even with matching data.")
        } catch CursorPaster.WritingPasteError.clipboardChanged {}

        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 0)
        #expect(fixture.board.string(forType: .string) == "NEW")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == copiedMarker)
        #expect(fixture.board.changeCount == copiedChangeCount)
    }

    @Test func confirmedReplacementRestoresAnEmptyClipboard() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }

        let result = try await fixture.replace()
        let restored = await waitForClipboard { fixture.board.pasteboardItems?.isEmpty != false }

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.access.attempts == 1)
        #expect(restored)
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == nil)
    }

    @Test func confirmedReplacementRestoresEveryImageAndTextClipboardFormat() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII="))
        let customType = NSPasteboard.PasteboardType("com.negentropi.RomaJustTalk.tests.binary")
        let custom = Data([0, 1, 2, 255])
        let image = NSPasteboardItem()
        let text = NSPasteboardItem()
        #expect(image.setData(png, forType: .png))
        #expect(text.setString("Previous text", forType: .string))
        #expect(text.setData(custom, forType: customType))
        #expect(fixture.board.writeObjects([image, text]))

        let result = try await fixture.replace()
        let restored = await waitForClipboard { fixture.board.pasteboardItems?.count == 2 }
        let items = try #require(fixture.board.pasteboardItems)

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.access.attempts == 1)
        #expect(restored)
        #expect(items.count == 2)
        #expect(items.first?.data(forType: .png) == png)
        #expect(items.last?.string(forType: .string) == "Previous text")
        #expect(items.last?.data(forType: customType) == custom)
    }

    @Test func aNewCopyAfterConfirmedPasteSurvivesScheduledRestoration() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")

        let result = try await fixture.replace(restorationDelay: 0.03)
        #expect(fixture.board.string(forType: .string) == "NEW")
        fixture.copy("New user copy")
        try await Task.sleep(for: .milliseconds(80))

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "New user copy")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == nil)
    }

    @Test func confirmedPasteRestoresTheClipboardAfterTheRequestedDelay() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")

        let result = try await fixture.replace(restorationDelay: 0.03)
        #expect(fixture.board.string(forType: .string) == "NEW")
        let restored = await waitForClipboard {
            fixture.board.string(forType: .string) == "Previous clipboard"
        }

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(restored)
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == nil)
    }

    @Test func scheduledRestorationCannotOverwriteANewGenerationWithMatchingData() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")

        let result = try await fixture.replace(restorationDelay: 0.03)
        let marker = try #require(fixture.board.string(forType: ClipboardManager.pasteSessionType))
        fixture.copy("NEW")
        #expect(fixture.board.setString(marker, forType: ClipboardManager.pasteSessionType))
        let copiedChangeCount = fixture.board.changeCount
        try await Task.sleep(for: .milliseconds(80))

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.board.string(forType: .string) == "NEW")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) == marker)
        #expect(fixture.board.changeCount == copiedChangeCount)
    }

    @Test func anErrorAfterConfirmedMutationDoesNotRepeatThePaste() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.access.behavior = .replace(.cannotComplete)

        let result = try await fixture.replace(restoreClipboard: false)

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "NEW")
    }

    @Test func acceptedNoOpRemainsUnconfirmedWithoutAnotherMutationOrClipboardRestore() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.behavior = .noOp

        let result = try await fixture.replace()

        #expect(result == .attemptedUnconfirmed)
        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "NEW")
        #expect(fixture.board.string(forType: ClipboardManager.pasteSessionType) != nil)
    }

    @Test func failureAfterMutationCannotEnterThePreMutationRestorationPath() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.behavior = .partialThenThrow

        let result = try await fixture.replace()

        #expect(result == .attemptedUnconfirmed)
        #expect(fixture.access.document == "prefix partial suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "NEW")
    }

    @Test func delayedReadbackConfirmsTheSameSingleMutation() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.access.behavior = .delayedReadback

        let result = try await fixture.replace(restoreClipboard: false)

        #expect(result == .confirmed)
        #expect(fixture.access.document == "prefix NEW suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.access.valueReads >= 2)
    }

    @Test func canonicalEqualityDoesNotConfirmDifferentUTF16Output() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.access.behavior = .canonicalEquivalentOutput

        let result = try await fixture.replace(text: "café", expectedValue: "prefix café suffix")

        #expect(result == .attemptedUnconfirmed)
        #expect(fixture.access.document.utf16.elementsEqual("prefix cafe\u{301} suffix".utf16))
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "café")
    }

    @Test func cancellationAfterAttemptKeepsUncertainContentWithoutRetrying() async throws {
        let fixture = WritingPasteFixture()
        defer { fixture.close() }
        fixture.copy("Previous clipboard")
        fixture.access.behavior = .noOp
        fixture.access.afterAttempt = { fixture.access.cancelled = true }

        let result = try await fixture.replace()

        #expect(result == .attemptedUnconfirmed)
        #expect(fixture.access.document == "prefix old suffix")
        #expect(fixture.access.attempts == 1)
        #expect(fixture.board.string(forType: .string) == "NEW")
    }

    private func waitForClipboard(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }
}

private enum WritingPasteFixtureError: Error, Equatable { case targetChanged, afterAttempt }

@MainActor
private final class WritingPasteFixture {
    let board = NSPasteboard.withUniqueName()
    lazy var access = WritingPasteAccess(board: board)

    func close() {
        access.duringDiscovery = nil
        access.afterAttempt = nil
        board.releaseGlobally()
    }

    func copy(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func replace(
        text: String = "NEW",
        expectedValue: String = "prefix NEW suffix",
        restoreClipboard: Bool = true,
        restorationDelay: TimeInterval = 0
    ) async throws -> CursorPaster.WritingPasteResult {
        try await CursorPaster.pasteWritingReplacement(
            text,
            expectedValue: expectedValue,
            access: access,
            shouldCancel: { self.access.cancelled },
            pasteboard: board,
            restoreClipboard: restoreClipboard,
            restorationDelay: restorationDelay
        )
    }
}

@MainActor
private final class WritingPasteAccess: CursorPaster.WritingPasteAccess {
    enum Behavior {
        case unavailable, noOp, partialThenThrow, delayedReadback, canonicalEquivalentOutput
        case replace(AXError)
    }

    let board: NSPasteboard
    var document = "prefix old suffix"
    var range = NSRange(location: 7, length: 3)
    var cancelled = false
    var focused = true
    var behavior: Behavior = .replace(.success)
    var duringDiscovery: (@MainActor () async throws -> Void)?
    var afterAttempt: (@MainActor () -> Void)?
    private(set) var attempts = 0
    private(set) var valueReads = 0

    init(board: NSPasteboard) { self.board = board }

    func validateTarget() throws {
        guard focused, document.utf16.elementsEqual("prefix old suffix".utf16),
              range == NSRange(location: 7, length: 3) else {
            throw WritingPasteFixtureError.targetChanged
        }
    }

    func pressMenu(authorize: () throws -> Void, willAttempt: () -> Void) async throws
        -> CursorTextContextReader.CapturedMenuAttempt {
        try authorize()
        try await duringDiscovery?()
        try authorize()
        if case .unavailable = behavior { return .notAttempted }
        willAttempt()
        attempts += 1
        switch behavior {
        case .unavailable, .noOp, .delayedReadback:
            break
        case .replace:
            replaceDocumentFromClipboard()
        case .partialThenThrow:
            document = "prefix partial suffix"
            throw WritingPasteFixtureError.afterAttempt
        case .canonicalEquivalentOutput:
            document = "prefix cafe\u{301} suffix"
        }
        afterAttempt?()
        if case .replace(let error) = behavior { return .attempted(error) }
        return .attempted(.success)
    }

    func readValue() -> String? {
        valueReads += 1
        if case .delayedReadback = behavior, valueReads == 2 { replaceDocumentFromClipboard() }
        return document
    }

    private func replaceDocumentFromClipboard() {
        let replacement = board.string(forType: .string) ?? "<missing clipboard>"
        document = (document as NSString).replacingCharacters(in: range, with: replacement)
        range = NSRange(location: 7 + replacement.utf16.count, length: 0)
    }
}
