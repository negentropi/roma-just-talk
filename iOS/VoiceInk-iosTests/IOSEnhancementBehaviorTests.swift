import XCTest
import VoiceInkCore

final class IOSEnhancementBehaviorTests: XCTestCase {
    func testPreferencesBuildExecutionAndSkipConfiguration() throws {
        let defaults = try makeDefaults()
        VoiceInkPostProcessingBehaviorPreference.saveSkipShortEnhancement(true, to: defaults)
        VoiceInkPostProcessingBehaviorPreference.saveShortEnhancementWordThreshold(7, to: defaults)
        VoiceInkPostProcessingBehaviorPreference.saveTimeoutSeconds(20, to: defaults)
        VoiceInkPostProcessingBehaviorPreference.saveRetryOnTimeout(true, to: defaults)
        VoiceInkIOSKeyboardEnhancementContextPreference.saveIsEnabled(false, to: defaults)

        XCTAssertEqual(
            VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
            VoiceInkPostProcessingSkipConfiguration(isEnabled: true, wordThreshold: 7)
        )
        XCTAssertEqual(
            VoiceInkPostProcessingExecutionConfiguration.current(in: defaults),
            VoiceInkPostProcessingExecutionConfiguration(timeoutSeconds: 20, retryOnTimeout: true)
        )
        XCTAssertFalse(VoiceInkIOSKeyboardEnhancementContextPreference.isEnabled(from: defaults))
    }

    func testExecutionReturnsSuccessfulResponse() async throws {
        let result = try await VoiceInkPostProcessingExecutionPolicy.execute(
            configuration: VoiceInkPostProcessingExecutionConfiguration(
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
            _ = try await VoiceInkPostProcessingExecutionPolicy.execute(
                configuration: VoiceInkPostProcessingExecutionConfiguration(
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
                error as? VoiceInkPostProcessingExecutionError,
                .timedOut(seconds: 0.02, attempts: 1)
            )
            let attemptCount = await attempts.value
            XCTAssertEqual(attemptCount, 1)
        }
    }

    func testExecutionRetriesTimeoutUpToThreeAttempts() async {
        let attempts = AttemptCounter()

        do {
            _ = try await VoiceInkPostProcessingExecutionPolicy.execute(
                configuration: VoiceInkPostProcessingExecutionConfiguration(
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
                error as? VoiceInkPostProcessingExecutionError,
                .timedOut(seconds: 0.02, attempts: 3)
            )
            let attemptCount = await attempts.value
            XCTAssertEqual(attemptCount, 3)
        }
    }

    func testExecutionDoesNotRetryProviderFailure() async {
        let attempts = AttemptCounter()

        do {
            _ = try await VoiceInkPostProcessingExecutionPolicy.execute(
                configuration: VoiceInkPostProcessingExecutionConfiguration(
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
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            throw VoiceInkPostProcessingExecutionError.timedOut(seconds: 3, attempts: 1)
        }
        let configuration = VoiceInkModeRuntimeConfiguration(
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
