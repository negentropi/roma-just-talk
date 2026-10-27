import AppKit
import Foundation
import Testing
@testable import VoiceInk

struct WritingTargetTests {
    @Test func replacementPreservesTextAroundAnEmojiSelection() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "Hi 👩🏽‍💻，世界!",
            range: NSRange(location: 3, length: 7)
        ))

        #expect(snapshot.selectedText == "👩🏽‍💻")
        #expect(snapshot.replacement("Felix") == "Hi Felix，世界!")
        #expect(snapshot.value == "Hi 👩🏽‍💻，世界!")
    }

    @Test func replacementHandlesCombiningMarksWithoutChangingAdjacentText() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "Cafe\u{301} noir",
            range: NSRange(location: 3, length: 2)
        ))

        #expect(snapshot.selectedText == "e\u{301}")
        #expect(snapshot.replacement("é chaud") == "Café chaud noir")
    }

    @Test func emptySelectionInsertsAtTheExactCursor() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "前後",
            range: NSRange(location: 1, length: 0)
        ))

        #expect(snapshot.selectedText.isEmpty)
        #expect(snapshot.replacement("中間") == "前中間後")
    }

    @Test func insertionAtEndAndWholeDocumentReplacementAreValid() throws {
        let atEnd = try #require(WritingTarget.TextSnapshot(
            value: "A😀",
            range: NSRange(location: 3, length: 0)
        ))
        let all = try #require(WritingTarget.TextSnapshot(
            value: "A😀",
            range: NSRange(location: 0, length: 3)
        ))

        #expect(atEnd.replacement("!") == "A😀!")
        #expect(all.selectedText == "A😀")
        #expect(all.replacement("新文") == "新文")
    }

    @Test func invalidAndOverflowingRangesAreRejected() {
        let ranges = [
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: -1, length: 1),
            NSRange(location: 0, length: -1),
            NSRange(location: 4, length: 0),
            NSRange(location: 2, length: 2),
            NSRange(location: 1, length: Int.max),
        ]

        for range in ranges {
            #expect(WritingTarget.TextSnapshot(value: "abc", range: range)?.value == nil)
        }
    }

    @Test func selectionCannotSplitAnEmojiSurrogatePair() {
        for range in [
            NSRange(location: 1, length: 1),
            NSRange(location: 2, length: 0),
            NSRange(location: 2, length: 1),
            NSRange(location: 0, length: 2),
        ] {
            #expect(WritingTarget.TextSnapshot(value: "A😀B", range: range)?.value == nil)
        }
    }

    @Test func scalarBoundariesWithinADecomposedCharacterRemainValid() throws {
        let accent = try #require(WritingTarget.TextSnapshot(
            value: "e\u{301} tail",
            range: NSRange(location: 1, length: 1)
        ))
        let between = try #require(WritingTarget.TextSnapshot(
            value: "e\u{301} tail",
            range: NSRange(location: 1, length: 0)
        ))

        #expect(accent.selectedText.utf16.elementsEqual("\u{301}".utf16))
        #expect(accent.replacement("") == "e tail")
        #expect(between.selectedText.isEmpty)
        #expect(between.replacement("x").utf16.elementsEqual("ex\u{301} tail".utf16))
    }

    @Test func matchingAllowsUnavailableSelectedTextOnlyWhenValueAndRangeStillMatch() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "before chosen after",
            range: NSRange(location: 7, length: 6)
        ))

        #expect(snapshot.matches(value: "before chosen after", range: snapshot.range, selectedText: "chosen"))
        #expect(snapshot.matches(value: "before chosen after", range: snapshot.range, selectedText: nil))
        #expect(!snapshot.matches(value: "before chosen after", range: snapshot.range, selectedText: "different"))
    }

    @Test func changedDocumentOrSelectionRejectsReplacement() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "before chosen after",
            range: NSRange(location: 7, length: 6)
        ))

        #expect(!snapshot.matches(value: "before chosen after!", range: snapshot.range, selectedText: "chosen"))
        #expect(!snapshot.matches(value: "before chosen after", range: NSRange(location: 0, length: 6), selectedText: "before"))
        #expect(!snapshot.matches(value: "before chosen after", range: NSRange(location: 7, length: 0), selectedText: ""))
        #expect(!snapshot.matches(value: "before chosen after", range: NSRange(location: Int.max, length: 1), selectedText: nil))
    }

    @Test func unicodeNormalizationChangesAreDocumentDrift() throws {
        let snapshot = try #require(WritingTarget.TextSnapshot(
            value: "café tail",
            range: NSRange(location: 0, length: 3)
        ))
        let accent = try #require(WritingTarget.TextSnapshot(
            value: "é",
            range: NSRange(location: 0, length: 1)
        ))

        #expect(!snapshot.matches(value: "cafe\u{301} tail", range: snapshot.range, selectedText: "caf"))
        #expect(!accent.matches(value: "é", range: accent.range, selectedText: "e\u{301}"))
    }

    @Test func targetIdentityRequiresBothOriginalProcessAndFocusedElement() {
        #expect(WritingTarget.targetMatches(capturedPID: 42, currentPID: 42, isSameElement: true))
        #expect(!WritingTarget.targetMatches(capturedPID: 42, currentPID: 43, isSameElement: true))
        #expect(!WritingTarget.targetMatches(capturedPID: 42, currentPID: 42, isSameElement: false))
        #expect(!WritingTarget.targetMatches(capturedPID: 42, currentPID: nil, isSameElement: true))
    }

    @Test @MainActor func selectedTextSetterReplacesOnlyTheCapturedRange() async throws {
        let access = FakeWritingAccess(value: "前chosen後", range: NSRange(location: 1, length: 6))
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "😀 replacement")
        #expect(outcome.isConfirmed)

        #expect(access.value == "前😀 replacement後")
        #expect(access.range == NSRange(location: 15, length: 0))
        #expect(access.selectedWrites == 1)
    }

    @Test @MainActor func cancellationBeforeNativeReplacementLeavesTheSelectionIntact() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "new", shouldCancel: { true })
        #expect(!outcome.wasAttempted)
        #expect(outcome.failure is CancellationError)

        #expect(access.value == "prefix old suffix")
        #expect(access.range == NSRange(location: 7, length: 3))
        #expect(access.selectedWrites == 0)
    }

    @Test @MainActor func unsupportedSelectedTextSetterLeavesTheDocumentAndSelectionIntact() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        access.selectedBehavior = .unsupported
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "😀")
        #expect(!outcome.wasAttempted)
        #expect(outcome.failure as? WritingTarget.Failure == .replacementFailed)

        #expect(access.value == "prefix old suffix")
        #expect(access.range == NSRange(location: 7, length: 3))
        #expect(access.selectedWrites == 1)
    }

    @Test @MainActor func changedFocusPreventsAnyEditorMutation() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        let target = try access.makeTarget()
        access.validationFailure = .targetChanged

        let outcome = await target.deliver(with: "new")
        #expect(!outcome.wasAttempted)
        #expect(outcome.failure as? WritingTarget.Failure == .targetChanged)

        #expect(access.value == "prefix old suffix")
        #expect(access.range == NSRange(location: 7, length: 3))
        #expect(access.selectedWrites == 0)
    }

    @Test @MainActor func editsOrSelectionMovementDuringGenerationRemainUntouched() async throws {
        let textDrift = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        let textTarget = try textDrift.makeTarget()
        textDrift.value = "prefix old suffix typed"
        let textOutcome = await textTarget.deliver(with: "new")
        #expect(!textOutcome.wasAttempted)
        #expect(textOutcome.failure as? WritingTarget.Failure == .targetChanged)
        #expect(textDrift.value == "prefix old suffix typed")
        #expect(textDrift.selectedWrites == 0)

        let rangeDrift = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        let rangeTarget = try rangeDrift.makeTarget()
        rangeDrift.range = NSRange(location: 0, length: 6)
        let rangeOutcome = await rangeTarget.deliver(with: "new")
        #expect(!rangeOutcome.wasAttempted)
        #expect(rangeOutcome.failure as? WritingTarget.Failure == .targetChanged)
        #expect(rangeDrift.value == "prefix old suffix")
        #expect(rangeDrift.range == NSRange(location: 0, length: 6))
        #expect(rangeDrift.selectedWrites == 0)
    }

    @Test @MainActor func successfulButIneffectiveSetterDoesNotAttemptAnotherMutation() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        access.selectedBehavior = .unchanged(.success)
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "new")
        #expect(outcome.wasAttempted)
        #expect(outcome.failure as? WritingTarget.Failure == .replacementUnconfirmed)

        #expect(access.value == "prefix old suffix")
        #expect(access.selectedWrites == 1)
    }

    @Test @MainActor func errorAfterPartialMutationDoesNotOverwriteTheChangedDocument() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        access.selectedBehavior = .overwrite("prefix partial suffix", .cannotComplete)
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "new")
        #expect(outcome.wasAttempted)
        #expect(outcome.failure as? WritingTarget.Failure == .replacementUnconfirmed)

        #expect(access.value == "prefix partial suffix")
        #expect(access.selectedWrites == 1)
    }

    @Test @MainActor func errorAfterConfirmedReplacementDoesNotRepeatTheReplacement() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        access.selectedBehavior = .replace(.cannotComplete)
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "new")
        #expect(outcome.isConfirmed)

        #expect(access.value == "prefix new suffix")
        #expect(access.selectedWrites == 1)
    }

    @Test @MainActor func rejectedSelectedTextWriteIsNotRetriedThroughAnotherMutation() async throws {
        let access = FakeWritingAccess(value: "prefix old suffix", range: NSRange(location: 7, length: 3))
        access.selectedBehavior = .unchanged(.cannotComplete)
        let target = try access.makeTarget()

        let outcome = await target.deliver(with: "new")
        #expect(outcome.wasAttempted)
        #expect(outcome.failure as? WritingTarget.Failure == .replacementUnconfirmed)

        #expect(access.value == "prefix old suffix")
        #expect(access.range == NSRange(location: 7, length: 3))
        #expect(access.selectedWrites == 1)
    }
}

@MainActor
private final class FakeWritingAccess: WritingTarget.Access {
    enum WriteBehavior {
        case unsupported
        case unchanged(AXError)
        case replace(AXError)
        case overwrite(String, AXError)
    }

    var value: String
    var range: NSRange
    var validationFailure: WritingTarget.Failure?
    var selectedBehavior: WriteBehavior = .replace(.success)
    private(set) var selectedWrites = 0
    var supportsUndoSelection: Bool { false }
    var isUndoTargetAlive: Bool { false }
    func isUndoTargetApplication(_ application: NSRunningApplication) -> Bool { false }

    init(value: String, range: NSRange) {
        self.value = value
        self.range = range
    }

    func makeTarget() throws -> WritingTarget {
        let snapshot = try #require(readSnapshot())
        return WritingTarget(snapshot: snapshot, access: self)
    }

    func validate() throws {
        if let validationFailure { throw validationFailure }
    }

    func readSnapshot() -> WritingTarget.TextSnapshot? {
        WritingTarget.TextSnapshot(value: value, range: range)
    }

    func readValue() -> String? { value }

    func validateUndoIdentity() throws { throw WritingTarget.Failure.unsupportedEditor }
    func setSelectedRange(_ range: NSRange) -> AXError? { nil }

    func replaceSelection(_ text: String, willAttempt: () throws -> Void) throws -> AXError? {
        selectedWrites += 1
        if case .unsupported = selectedBehavior { return nil }
        try willAttempt()
        switch selectedBehavior {
        case .unsupported:
            return nil
        case .unchanged(let error):
            return error
        case .overwrite(let replacement, let error):
            value = replacement
            return error
        case .replace(let error):
            guard let snapshot = readSnapshot() else { return .illegalArgument }
            value = snapshot.replacement(text)
            range = NSRange(location: range.location + text.utf16.count, length: 0)
            return error
        }
    }
}
