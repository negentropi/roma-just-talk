import Foundation
@testable import VoiceInkCore

final class TranscriptionStreamingPreferenceTests: XCTestCase {
    func testKeyPreservesExistingPerModelPattern() {
        XCTAssertEqual(VoiceInkTranscriptionStreamingPreference.keyPrefix, "streaming-enabled-")
        XCTAssertEqual(
            VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            "streaming-enabled-parakeet-tdt-0.6b-v3"
        )
    }

    func testStreamingPreferenceDefaultsEnabledWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testStreamingPreferenceSavesAndReadsOverride() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingRejectsUnsupportedModels() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: VoiceInkTranscriptionStreamingModelSnapshot(
                    name: "whisper-base",
                    supportsStreaming: false
                ),
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingForStreamingOnlyModelIgnoresStoredDisabledValue() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "ink-whisper",
                to: defaults
            )

            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: VoiceInkTranscriptionStreamingModelSnapshot(
                    name: "ink-whisper",
                    supportsStreaming: true,
                    isStreamingOnly: true
                ),
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingUsesStoredPreferenceForBatchCapableStreamingModel() {
        withIsolatedDefaults { defaults in
            let model = VoiceInkTranscriptionStreamingModelSnapshot(
                name: "universal-3-pro",
                supportsStreaming: true
            )

            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))

            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: model.name,
                to: defaults
            )

            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionStreamingPreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }
}
