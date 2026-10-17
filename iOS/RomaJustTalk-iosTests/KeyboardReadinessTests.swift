import Foundation
import XCTest
import RomaCore
@testable import roma_just_talk

final class KeyboardReadinessTests: XCTestCase {
    func testReadinessRequiresAnObservationFromTheCurrentVerification() {
        let verificationStartedAt = Date(timeIntervalSince1970: 200)
        let oldObservation = RomaIOSKeyboardReadinessObservation(
            hasFullAccess: true,
            observedAt: Date(timeIntervalSince1970: 199)
        )

        XCTAssertEqual(
            RomaIOSKeyboardReadinessPolicy.status(
                observation: oldObservation,
                verificationStartedAt: verificationStartedAt
            ),
            .unverified
        )
    }

    func testFreshActivationReportsFullAccessState() {
        let verificationStartedAt = Date(timeIntervalSince1970: 200)

        XCTAssertEqual(
            RomaIOSKeyboardReadinessPolicy.status(
                observation: RomaIOSKeyboardReadinessObservation(
                    hasFullAccess: false,
                    observedAt: verificationStartedAt
                ),
                verificationStartedAt: verificationStartedAt
            ),
            .fullAccessRequired
        )
        XCTAssertEqual(
            RomaIOSKeyboardReadinessPolicy.status(
                observation: RomaIOSKeyboardReadinessObservation(
                    hasFullAccess: true,
                    observedAt: verificationStartedAt
                ),
                verificationStartedAt: verificationStartedAt
            ),
            .ready
        )
    }

    @MainActor
    func testDarwinBridgeReportsBothKeyboardAccessStates() {
        let coordinator = AppGroupCoordinator.shared
        let reportExpectation = expectation(description: "keyboard readiness reports")
        reportExpectation.expectedFulfillmentCount = 2
        var reportedStates: Set<Bool> = []

        coordinator.onKeyboardReadinessReported = { observation in
            reportedStates.insert(observation.hasFullAccess)
            reportExpectation.fulfill()
        }

        coordinator.reportKeyboardReadiness(hasFullAccess: false)
        coordinator.reportKeyboardReadiness(hasFullAccess: true)
        wait(for: [reportExpectation], timeout: 2)
        coordinator.onKeyboardReadinessReported = nil

        XCTAssertEqual(reportedStates, [false, true])
    }
}
