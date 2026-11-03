import XCTest
@testable import VoiceInk

@MainActor
final class CaptureAuthorizationDecisionTests: XCTestCase {
    func testCanceledPermissionDecisionDrainsBeforeSystemCallback() async {
        let requested = expectation(description: "system decision requested")
        let completed = expectation(description: "canceled owner drained before system callback")
        var callback: (@Sendable (Bool) -> Void)?
        var decision: Bool?
        let owner = Task { @MainActor in
            decision = await CaptureAuthorizationDecision.request { reply in
                callback = reply
                requested.fulfill()
            }
            completed.fulfill()
        }
        await fulfillment(of: [requested], timeout: 1)
        owner.cancel()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(decision, false, "Cancellation must drain before the withheld system callback")
        callback?(true)
        await owner.value
        XCTAssertEqual(decision, false, "A late system callback must not authorize the canceled owner")
    }

    func testAlreadyCanceledOwnerDoesNotRequestPermission() async {
        var requestCount = 0
        let owner = Task { @MainActor in
            await CaptureAuthorizationDecision.request { reply in
                requestCount += 1
                reply(false)
            }
        }
        owner.cancel()
        let decision = await owner.value
        XCTAssertFalse(decision)
        XCTAssertEqual(requestCount, 0)
    }

    func testGrantedDecision() async {
        let decision = await CaptureAuthorizationDecision.request { $0(true) }
        XCTAssertTrue(decision)
    }

    func testDeniedDecision() async {
        let decision = await CaptureAuthorizationDecision.request { $0(false) }
        XCTAssertFalse(decision)
    }
}
