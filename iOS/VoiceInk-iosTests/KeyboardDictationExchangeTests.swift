import Foundation
import XCTest
@testable import VoiceInk_ios

final class KeyboardDictationExchangeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "KeyboardDictationExchangeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testMatchingDocumentTakesCompletedTextExactlyOnce() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let requestID = UUID()
        let documentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(
            store.begin(
                documentIdentifier: documentID,
                requestID: requestID,
                now: requestedAt
            ),
            requestID
        )
        XCTAssertTrue(store.complete(
            requestID: requestID,
            text: "Delivered transcript",
            now: requestedAt.addingTimeInterval(1)
        ))

        XCTAssertEqual(
            store.takeCompletedResult(
                for: documentID,
                now: requestedAt.addingTimeInterval(2)
            ),
            VoiceInkKeyboardDictationDelivery(
                requestID: requestID,
                text: "Delivered transcript"
            )
        )
        XCTAssertNil(store.takeCompletedResult(
            for: documentID,
            now: requestedAt.addingTimeInterval(2)
        ))
    }

    func testDifferentDocumentCannotTakeCompletedText() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let requestID = UUID()
        let originalDocumentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        store.begin(
            documentIdentifier: originalDocumentID,
            requestID: requestID,
            now: requestedAt
        )
        XCTAssertTrue(store.complete(
            requestID: requestID,
            text: "Private transcript",
            now: requestedAt.addingTimeInterval(1)
        ))

        let otherDocumentID = UUID()
        XCTAssertEqual(
            store.status(
                for: otherDocumentID,
                now: requestedAt.addingTimeInterval(2)
            ),
            .waitingForOriginalDocument(requestID: requestID)
        )
        XCTAssertNil(store.takeCompletedResult(
            for: otherDocumentID,
            now: requestedAt.addingTimeInterval(2)
        ))
        XCTAssertNotNil(store.takeCompletedResult(
            for: originalDocumentID,
            now: requestedAt.addingTimeInterval(2)
        ))
    }

    func testNewRequestSupersedesOldCompletion() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let oldRequestID = UUID()
        let newRequestID = UUID()
        let documentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        store.begin(
            documentIdentifier: documentID,
            requestID: oldRequestID,
            now: requestedAt
        )
        store.begin(
            documentIdentifier: documentID,
            requestID: newRequestID,
            now: requestedAt.addingTimeInterval(1)
        )

        XCTAssertFalse(store.complete(
            requestID: oldRequestID,
            text: "Stale transcript",
            now: requestedAt.addingTimeInterval(2)
        ))
        XCTAssertEqual(
            store.pendingRequestID(now: requestedAt.addingTimeInterval(2)),
            newRequestID
        )
    }

    func testFailureRemainsVisibleUntilClearedForRetry() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let requestID = UUID()
        let documentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        store.begin(
            documentIdentifier: documentID,
            requestID: requestID,
            now: requestedAt
        )
        XCTAssertTrue(store.fail(
            requestID: requestID,
            message: "Microphone permission denied.",
            now: requestedAt.addingTimeInterval(1)
        ))

        XCTAssertEqual(
            store.status(
                for: documentID,
                now: requestedAt.addingTimeInterval(2)
            ),
            .failed(
                requestID: requestID,
                message: "Microphone permission denied."
            )
        )
        XCTAssertTrue(store.clear(
            requestID: requestID,
            now: requestedAt.addingTimeInterval(2)
        ))
        XCTAssertEqual(
            store.status(
                for: documentID,
                now: requestedAt.addingTimeInterval(2)
            ),
            .none
        )
    }

    func testExpiredExchangeCannotInsertStaleText() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let requestID = UUID()
        let documentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        store.begin(
            documentIdentifier: documentID,
            requestID: requestID,
            now: requestedAt
        )
        XCTAssertTrue(store.complete(
            requestID: requestID,
            text: "Expired transcript",
            now: requestedAt.addingTimeInterval(1)
        ))

        let expiredAt = requestedAt.addingTimeInterval(
            VoiceInkKeyboardDictationExchangeStore.expirationInterval + 2
        )
        XCTAssertNil(store.takeCompletedResult(for: documentID, now: expiredAt))
        XCTAssertEqual(store.status(for: documentID, now: expiredAt), .none)
    }
}
