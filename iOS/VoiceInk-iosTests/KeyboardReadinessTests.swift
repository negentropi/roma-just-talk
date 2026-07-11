import Foundation
import XCTest
import VoiceInkCore
@testable import roma_just_talk

final class KeyboardReadinessTests: XCTestCase {
    func testReadinessRequiresAnObservationFromTheCurrentVerification() {
        let verificationStartedAt = Date(timeIntervalSince1970: 200)
        let oldObservation = VoiceInkIOSKeyboardReadinessObservation(
            hasFullAccess: true,
            observedAt: Date(timeIntervalSince1970: 199)
        )

        XCTAssertEqual(
            VoiceInkIOSKeyboardReadinessPolicy.status(
                observation: oldObservation,
                verificationStartedAt: verificationStartedAt
            ),
            .unverified
        )
    }

    func testFreshActivationReportsFullAccessState() {
        let verificationStartedAt = Date(timeIntervalSince1970: 200)

        XCTAssertEqual(
            VoiceInkIOSKeyboardReadinessPolicy.status(
                observation: VoiceInkIOSKeyboardReadinessObservation(
                    hasFullAccess: false,
                    observedAt: verificationStartedAt
                ),
                verificationStartedAt: verificationStartedAt
            ),
            .fullAccessRequired
        )
        XCTAssertEqual(
            VoiceInkIOSKeyboardReadinessPolicy.status(
                observation: VoiceInkIOSKeyboardReadinessObservation(
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
