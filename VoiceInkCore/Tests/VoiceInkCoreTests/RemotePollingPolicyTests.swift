import Foundation
@testable import VoiceInkCore

final class RemotePollingPolicyTests: XCTestCase {
    func testPollReturnsFinishedResultWithoutSleeping() async throws {
        var operationCount = 0
        var sleepCount = 0

        let result = try await VoiceInkRemotePollingPolicy.poll(
            maxWaitSeconds: 10,
            sleep: { _ in sleepCount += 1 }
        ) {
            operationCount += 1
            return .finished("done")
        }

        XCTAssertEqual(result, "done")
        XCTAssertEqual(operationCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    func testPollSleepsAndRetriesUntilFinished() async throws {
        var operationCount = 0
        var sleptIntervals: [UInt64] = []

        let result = try await VoiceInkRemotePollingPolicy.poll(
            maxWaitSeconds: 10,
            sleep: { interval in sleptIntervals.append(interval) }
        ) {
            operationCount += 1
            return operationCount == 1 ? .keepPolling : .finished("done")
        }

        XCTAssertEqual(result, "done")
        XCTAssertEqual(operationCount, 2)
        XCTAssertEqual(sleptIntervals, [VoiceInkRemotePollingPolicy.defaultIntervalNanoseconds])
    }

    func testPollTimesOutAfterPendingDecision() async throws {
        var operationCount = 0
        var now = Date(timeIntervalSince1970: 0)

        do {
            let _: String = try await VoiceInkRemotePollingPolicy.poll(
                maxWaitSeconds: 1,
                now: { now },
                sleep: { _ in
                    now = Date(timeIntervalSince1970: now.timeIntervalSince1970 + 2)
                }
            ) {
                operationCount += 1
                return .keepPolling
            }
            XCTFail("Expected polling timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError.timedOut, got \(error)")
        }

        XCTAssertEqual(operationCount, 2)
    }
}
