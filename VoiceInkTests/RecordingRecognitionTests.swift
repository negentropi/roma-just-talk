import XCTest
@testable import VoiceInk

@MainActor
final class RecordingRecognitionTests: XCTestCase {
    func testVoiceSuccessCancelsAndDrainsLipRecognition() async throws {
        let started = expectation(description: "lip inference started")
        let canceled = expectation(description: "unused lip inference canceled")
        let cleaning = expectation(description: "lip cleanup started")
        let voiceGate = Gate()
        let cleanupGate = Gate()
        let cancellation = AsyncStream<Void>.makeStream()
        var cleanupFinished = false
        var delivered = false
        let lips = Task<String, Error> { @MainActor in
            await withTaskCancellationHandler {
                started.fulfill()
                for await _ in cancellation.stream { break }
                cleaning.fulfill()
                await cleanupGate.wait()
                cleanupFinished = true
                return "unused lips"
            } onCancel: {
                cancellation.continuation.finish()
                canceled.fulfill()
            }
        }
        let voice = Task<String, Error> { @MainActor in
            await voiceGate.wait()
            return "  Spoken words.\n"
        }
        let owner = Task { @MainActor in
            let selection = try await RecordingRecognition.resolve(voice: voice, lips: lips)
            delivered = true
            return selection
        }
        defer {
            owner.cancel()
            voice.cancel()
            lips.cancel()
            voiceGate.open()
            cleanupGate.open()
        }
        await fulfillment(of: [started], timeout: 2)
        voiceGate.open()
        let cancellationObserved = await XCTWaiter.fulfillment(of: [canceled, cleaning], timeout: 2)
        XCTAssertEqual(cancellationObserved, .completed, "Ready voice must cancel lip inference that would otherwise remain blocked")
        XCTAssertFalse(delivered, "Voice must not be delivered before actual lip cleanup finishes")
        XCTAssertFalse(cleanupFinished)
        // Also release the known-bad await-both policy so a red regression never strands tasks.
        lips.cancel()
        cleanupGate.open()
        let selection = try await owner.value
        XCTAssertTrue(cleanupFinished)
        XCTAssertEqual(selection, .voice("  Spoken words.\n"))
    }

    func testEmptyVoiceWaitsForLipResultWithoutCancelingIt() async throws {
        let started = expectation(description: "fallback lip inference started")
        let release = Gate()
        var delivered = false
        let lips = Task<String, Error> { @MainActor in
            started.fulfill()
            await release.wait()
            try Task.checkCancellation()
            return "  Lip words.\n"
        }
        let voice = Task<String, Error> { " \n\t" }
        let owner = Task { @MainActor in
            let selection = try await RecordingRecognition.resolve(voice: voice, lips: lips)
            delivered = true
            return selection
        }
        defer { release.open(); voice.cancel(); lips.cancel(); owner.cancel() }
        await fulfillment(of: [started], timeout: 2)
        _ = await voice.result
        XCTAssertFalse(delivered)
        XCTAssertFalse(lips.isCancelled)
        release.open()
        let selection = try await owner.value
        XCTAssertEqual(selection, .lips("  Lip words.\n"))
        XCTAssertFalse(lips.isCancelled)
    }

    func testMissingAndFailedVoiceUseLipResult() async throws {
        for voice in [nil, task(.failure(Failure.voice))] {
            let lips = task(.success("lip fallback"))
            let selection = try await RecordingRecognition.resolve(voice: voice, lips: lips)
            XCTAssertEqual(selection, .lips("lip fallback"))
            XCTAssertFalse(lips.isCancelled)
        }
    }

    func testSingleInputsAndEmptyResultsPreserveExistingPolicy() async throws {
        let cases: [(Result<String, Error>?, Result<String, Error>?, RecordingRecognition)] = [
            (.success(" raw voice\n"), nil, .voice(" raw voice\n")),
            (nil, .success(" raw lips\n"), .lips(" raw lips\n")),
            (.success("voice"), .failure(Failure.lips), .voice("voice")),
            (nil, nil, .none),
            (.success(" \n"), .success("\t"), .none)
        ]
        for (voice, lips, expected) in cases {
            let selection = try await RecordingRecognition.resolve(voice: voice.map(task), lips: lips.map(task))
            XCTAssertEqual(selection, expected)
        }
    }

    func testEmptyResultsRetainErrorPriority() async {
        let cases: [(Result<String, Error>?, Result<String, Error>?, Failure)] = [
            (.failure(Failure.voice), nil, .voice),
            (nil, .failure(Failure.lips), .lips),
            (.failure(Failure.voice), .failure(Failure.lips), .lips),
            (.failure(Failure.voice), .success(" \n"), .voice),
            (.success(""), .failure(Failure.lips), .lips)
        ]
        for (voice, lips, expected) in cases {
            do {
                _ = try await RecordingRecognition.resolve(voice: voice.map(task), lips: lips.map(task))
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? Failure, expected)
            }
        }
    }

    func testCanceledOwnerNeverDeliversAfterLipCleanup() async {
        let cleaning = expectation(description: "lip cleanup held open")
        let cleanupGate = Gate()
        let cancellation = AsyncStream<Void>.makeStream()
        var cleanupFinished = false
        var delivered = false
        let lips = Task<String, Error> { @MainActor in
            await withTaskCancellationHandler {
                for await _ in cancellation.stream { break }
                cleaning.fulfill()
                await cleanupGate.wait()
                cleanupFinished = true
                return "unused"
            } onCancel: { cancellation.continuation.finish() }
        }
        let voice = task(.success("voice"))
        let owner = Task { @MainActor in
            let selection = try await RecordingRecognition.resolve(voice: voice, lips: lips)
            delivered = true
            return selection
        }
        defer { cleanupGate.open(); lips.cancel(); voice.cancel(); owner.cancel() }
        let cleanupObserved = await XCTWaiter.fulfillment(of: [cleaning], timeout: 2)
        XCTAssertEqual(cleanupObserved, .completed)
        owner.cancel()
        lips.cancel()
        cleanupGate.open()
        let result = await owner.result
        guard case .failure(let error) = result else { return XCTFail("Canceled owner delivered text") }
        XCTAssertTrue(error is CancellationError)
        XCTAssertTrue(cleanupFinished)
        XCTAssertFalse(delivered)
    }

    func testAlreadyCanceledOwnerNeverDelivers() async {
        let release = Gate()
        let voice = task(.success("voice"))
        let owner = Task { @MainActor in
            await release.wait()
            return try await RecordingRecognition.resolve(voice: voice, lips: nil)
        }
        owner.cancel()
        release.open()
        let result = await owner.result
        guard case .failure(let error) = result else { return XCTFail("Already canceled owner delivered text") }
        XCTAssertTrue(error is CancellationError)
        _ = await voice.result
    }

    private enum Failure: Error, Equatable { case voice, lips }

    private func task(_ result: Result<String, Error>) -> Task<String, Error> {
        Task { try result.get() }
    }

    // Unlike a canceled AsyncStream iterator, this gate stays closed until cleanup is explicitly released.
    @MainActor private final class Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
}
