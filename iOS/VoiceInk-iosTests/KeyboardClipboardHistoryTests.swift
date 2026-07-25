import Foundation
import XCTest
@testable import roma_just_talk

@MainActor
final class KeyboardClipboardHistoryTests: XCTestCase {
    private var directoryURL: URL!
    private var store: VoiceInkKeyboardClipboardStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardClipboardHistoryTests.\(UUID().uuidString)")
        store = VoiceInkKeyboardClipboardStore(directoryURL: directoryURL)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        store = nil
        directoryURL = nil
    }

    func testRecordingDeduplicatesAndMovesTheLatestUseFirst() throws {
        let firstDate = Date(timeIntervalSince1970: 100)
        let alpha = try XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Alpha"))
        let beta = try XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Beta"))

        let firstAlpha = try store.record(alpha, now: firstDate)
        try store.record(beta, now: firstDate.addingTimeInterval(1))
        let latestAlpha = try store.record(alpha, now: firstDate.addingTimeInterval(2))

        let items = try store.items(now: firstDate.addingTimeInterval(2))
        XCTAssertEqual(items.map(\.summary), ["Alpha", "Beta"])
        XCTAssertEqual(latestAlpha.id, firstAlpha.id)
        XCTAssertEqual(items.first?.lastUsedAt, firstDate.addingTimeInterval(2))
    }

    func testPinnedItemsSurviveRetentionAndClear() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldDate = now.addingTimeInterval(-VoiceInkKeyboardClipboardStore.retentionInterval - 1)
        let pinned = try store.record(
            XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Pinned")),
            now: oldDate
        )
        try store.togglePinned(id: pinned.id, now: oldDate)
        try store.record(
            XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Temporary")),
            now: now
        )

        XCTAssertEqual(try store.items(now: now).map(\.summary), ["Pinned", "Temporary"])

        try store.removeAllUnpinned()
        let remaining = try store.items(now: now)
        XCTAssertEqual(remaining.map(\.summary), ["Pinned"])
        XCTAssertTrue(remaining[0].isPinned)
    }

    func testExpiredUnpinnedItemsArePruned() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        try store.record(
            XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Expired")),
            now: now.addingTimeInterval(-VoiceInkKeyboardClipboardStore.retentionInterval - 1)
        )
        try store.record(
            XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Current")),
            now: now
        )

        XCTAssertEqual(try store.items(now: now).map(\.summary), ["Current"])
    }

    func testImageDataPersistsAndIsRemovedWithItsItem() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        let item = try store.record(
            XCTUnwrap(VoiceInkKeyboardClipboardPayload(imageData: imageData)),
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(try store.imageData(for: item), imageData)

        try store.remove(id: item.id)
        XCTAssertThrowsError(try store.imageData(for: item))
    }

    func testSearchFiltersTextLinksImagesAndPins() {
        let now = Date(timeIntervalSince1970: 100)
        let items = [
            VoiceInkKeyboardClipboardItem(
                id: UUID(),
                kind: .text,
                fingerprint: "text",
                createdAt: now,
                lastUsedAt: now,
                text: "Project launch notes",
                imageFileName: nil,
                isPinned: true
            ),
            VoiceInkKeyboardClipboardItem(
                id: UUID(),
                kind: .link,
                fingerprint: "link",
                createdAt: now,
                lastUsedAt: now,
                text: "https://raycast.com/clipboard-history",
                imageFileName: nil,
                isPinned: false
            ),
            VoiceInkKeyboardClipboardItem(
                id: UUID(),
                kind: .image,
                fingerprint: "image",
                createdAt: now,
                lastUsedAt: now,
                text: nil,
                imageFileName: "image.png",
                isPinned: false
            )
        ]

        XCTAssertEqual(
            VoiceInkKeyboardClipboardSearch.items(items, matching: "launch", filter: .all).map(\.kind),
            [.text]
        )
        XCTAssertEqual(
            VoiceInkKeyboardClipboardSearch.items(items, matching: "raycast", filter: .links).map(\.kind),
            [.link]
        )
        XCTAssertEqual(
            VoiceInkKeyboardClipboardSearch.items(items, matching: "", filter: .images).map(\.kind),
            [.image]
        )
        XCTAssertEqual(
            VoiceInkKeyboardClipboardSearch.items(items, matching: "", filter: .pinned).map(\.kind),
            [.text]
        )
    }

    func testHistoryKeepsOnlyTheNewestHundredUnpinnedItems() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        for index in 0...VoiceInkKeyboardClipboardStore.maximumUnpinnedItemCount {
            try store.record(
                XCTUnwrap(VoiceInkKeyboardClipboardPayload(text: "Item \(index)")),
                now: start.addingTimeInterval(TimeInterval(index))
            )
        }

        let items = try store.items(
            now: start.addingTimeInterval(TimeInterval(VoiceInkKeyboardClipboardStore.maximumUnpinnedItemCount))
        )
        XCTAssertEqual(items.count, VoiceInkKeyboardClipboardStore.maximumUnpinnedItemCount)
        XCTAssertEqual(items.first?.summary, "Item 100")
        XCTAssertEqual(items.last?.summary, "Item 1")
    }
}
