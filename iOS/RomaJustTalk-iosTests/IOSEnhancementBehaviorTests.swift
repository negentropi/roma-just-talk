import XCTest
import RomaCore

final class IOSEnhancementBehaviorTests: XCTestCase {
    func testPreferencesBuildExecutionAndSkipConfiguration() throws {
        let defaults = try makeDefaults()
        RomaPostProcessingBehaviorPreference.saveSkipShortEnhancement(true, to: defaults)
        RomaPostProcessingBehaviorPreference.saveShortEnhancementWordThreshold(7, to: defaults)
        RomaPostProcessingBehaviorPreference.saveTimeoutSeconds(20, to: defaults)
        RomaPostProcessingBehaviorPreference.saveRetryOnTimeout(true, to: defaults)
        RomaIOSKeyboardEnhancementContextPreference.saveIsEnabled(false, to: defaults)

        XCTAssertEqual(
            RomaPostProcessingSkipConfiguration.current(in: defaults),
            RomaPostProcessingSkipConfiguration(isEnabled: true, wordThreshold: 7)
        )
        XCTAssertEqual(
            RomaPostProcessingExecutionConfiguration.current(in: defaults),
            RomaPostProcessingExecutionConfiguration(timeoutSeconds: 20, retryOnTimeout: true)
        )
        XCTAssertFalse(RomaIOSKeyboardEnhancementContextPreference.isEnabled(from: defaults))
    }

    func testExecutionReturnsSuccessfulResponse() async throws {
        let result = try await RomaPostProcessingExecutionPolicy.execute(
            configuration: RomaPostProcessingExecutionConfiguration(
                timeoutSeconds: 0.1,
                retryOnTimeout: false
            )
        ) {
            "enhanced"
        }

        XCTAssertEqual(result, "enhanced")
    }

    func testExecutionTimesOutOnceWithoutRetry() async {
        let attempts = AttemptCounter()

        do {
            _ = try await RomaPostProcessingExecutionPolicy.execute(
                configuration: RomaPostProcessingExecutionConfiguration(
                    timeoutSeconds: 0.02,
                    retryOnTimeout: false
                )
            ) {
                await attempts.increment()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                error as? RomaPostProcessingExecutionError,
                .timedOut(seconds: 0.02, attempts: 1)
            )
            let attemptCount = await attempts.value
            XCTAssertEqual(attemptCount, 1)
        }
    }

    func testExecutionRetriesTimeoutUpToThreeAttempts() async {
        let attempts = AttemptCounter()

        do {
            _ = try await RomaPostProcessingExecutionPolicy.execute(
                configuration: RomaPostProcessingExecutionConfiguration(
                    timeoutSeconds: 0.02,
                    retryOnTimeout: true
                )
            ) {
                await attempts.increment()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                error as? RomaPostProcessingExecutionError,
                .timedOut(seconds: 0.02, attempts: 3)
            )
            let attemptCount = await attempts.value
            XCTAssertEqual(attemptCount, 3)
        }
    }

    func testExecutionDoesNotRetryProviderFailure() async {
        let attempts = AttemptCounter()

        do {
            _ = try await RomaPostProcessingExecutionPolicy.execute(
                configuration: RomaPostProcessingExecutionConfiguration(
                    timeoutSeconds: 0.1,
                    retryOnTimeout: true
                )
            ) {
                await attempts.increment()
                throw TestError.providerFailure
            }
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? TestError, .providerFailure)
            let attemptCount = await attempts.value
            XCTAssertEqual(attemptCount, 1)
        }
    }

    func testPostProcessingFailureKeepsOriginalTranscription() async throws {
        let processor = RomaTranscriptionRunProcessor { _ in
            throw RomaPostProcessingExecutionError.timedOut(seconds: 3, attempts: 1)
        }
        let configuration = RomaModeRuntimeConfiguration(
            transcriptionProvider: .groq,
            transcriptionModel: "whisper-large-v3-turbo",
            postProcessingProvider: .openAI,
            postProcessingModel: "gpt-4o-mini",
            prompt: "Polish the transcript.",
            isPostProcessingEnabled: true
        )

        let result = try await processor.processTranscribedText(
            "original transcript",
            transcriptionModelName: configuration.transcriptionModel,
            configuration: configuration,
            apiKeyProvider: { _ in "test-key" }
        )

        XCTAssertEqual(result.finalText, "original transcript")
        XCTAssertNil(result.postProcessingResult)
        XCTAssertTrue(result.postProcessingError?.contains("original transcription was kept") == true)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "IOSEnhancementBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor AttemptCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private enum TestError: Error, Equatable {
    case providerFailure
}
