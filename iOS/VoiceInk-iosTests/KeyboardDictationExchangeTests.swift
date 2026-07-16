import Foundation
import VoiceInkCore
import XCTest
@testable import roma_just_talk

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

    func testDocumentIdentifierPolicyHandlesUnavailableProxyValue() {
        XCTAssertNil(VoiceInkKeyboardDocumentIdentifierPolicy.resolve(nil))

        let documentID = UUID()
        XCTAssertEqual(
            VoiceInkKeyboardDocumentIdentifierPolicy.resolve(
                NSUUID(uuidString: documentID.uuidString)
            ),
            documentID
        )
    }

    func testDismissOnlyRecordingAlertStillProvidesEnabledIOSAction() {
        var openedSettings = false

        VoiceInkRecordingAlertPresentation.noModesAvailable.iOSPrimaryButtonAction {
            openedSettings = true
        }()
        XCTAssertFalse(openedSettings)

        VoiceInkRecordingAlertPresentation.microphonePermissionDenied.iOSPrimaryButtonAction {
            openedSettings = true
        }()
        XCTAssertTrue(openedSettings)
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
                text: "Delivered transcript",
                shouldLowercase: false,
                shouldInsertReturn: false
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
            store.takePendingRequest(now: requestedAt.addingTimeInterval(2))?.requestID,
            newRequestID
        )
    }

    func testPendingRequestBoundsAndConsumesSurroundingContext() throws {
        let store = VoiceInkKeyboardDictationExchangeStore(defaults: defaults)
        let requestID = UUID()
        let documentID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)
        let context = String(repeating: "a", count: 260)

        store.begin(
            documentIdentifier: documentID,
            surroundingTextBeforeCursor: context,
            requestID: requestID,
            now: requestedAt
        )

        XCTAssertEqual(
            store.takePendingRequest(now: requestedAt.addingTimeInterval(1)),
            VoiceInkKeyboardDictationRequest(
                requestID: requestID,
                surroundingTextBeforeCursor: String(repeating: "a", count: 240)
            )
        )
        XCTAssertEqual(
            store.takePendingRequest(now: requestedAt.addingTimeInterval(2)),
            VoiceInkKeyboardDictationRequest(
                requestID: requestID,
                surroundingTextBeforeCursor: nil
            )
        )
    }

    func testCompletedDeliveryPreservesLowercaseIntent() throws {
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
            text: "lowercase transcript",
            shouldLowercase: true,
            shouldInsertReturn: true,
            now: requestedAt.addingTimeInterval(1)
        ))

        let delivery = store.takeCompletedResult(
            for: documentID,
            now: requestedAt.addingTimeInterval(2)
        )
        XCTAssertTrue(delivery?.shouldLowercase == true)
        XCTAssertTrue(delivery?.shouldInsertReturn == true)
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
