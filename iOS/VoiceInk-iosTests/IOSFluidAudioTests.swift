import XCTest
import VoiceInkCore
@testable import roma_just_talk

@MainActor
final class IOSFluidAudioTests: XCTestCase {
    func testAudioTranscriptionServiceFactoryRoutesLocalFluidAudio() async throws {
        var localFactoryCallCount = 0
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: {
                StubAudioTranscriptionService(text: "whisper")
            },
            localFluidAudioServiceFactory: {
                localFactoryCallCount += 1
                return StubAudioTranscriptionService(text: "parakeet")
            }
        )

        let transcript = try await factory.service(for: .localFluidAudio).transcribeAudioFile(
            apiKey: "local-fluidaudio",
            model: "parakeet-tdt-0.6b-v3",
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            language: nil,
            prompt: nil,
            customVocabulary: []
        )

        XCTAssertEqual(localFactoryCallCount, 1)
        XCTAssertEqual(transcript, "parakeet")
    }

    func testDownloadLifecyclePublishesAvailableModel() async {
        let downloaded = LockedFlag()
        let manager = FluidAudioModelManager(client: FluidAudioModelDownloadClient(
            modelsExist: { _ in downloaded.value },
            cacheDirectoryExists: { _ in false },
            validateCache: { _ in false },
            downloadAndLoad: { _, _, reportProgress in
                reportProgress(VoiceInkFluidAudioDownloadStatus(
                    fractionCompleted: 0.5,
                    phase: .downloadingFiles(completedFiles: 1, totalFiles: 2)
                ))
                downloaded.value = true
            }
        ))
        let modelName = VoiceInkTranscriptionModelCatalog.fluidAudioModels[0].name

        await manager.downloadFluidAudioModel(named: modelName)

        XCTAssertTrue(manager.isFluidAudioModelDownloaded(named: modelName))
        XCTAssertFalse(manager.isFluidAudioModelDownloading(named: modelName))
        XCTAssertNil(manager.downloadStatus(forModelNamed: modelName))
        XCTAssertNil(manager.downloadIssue(forModelNamed: modelName))
    }

    func testDownloadFailureExposesRetryState() async {
        struct DownloadFailure: LocalizedError {
            var errorDescription: String? { "Offline" }
        }

        let manager = FluidAudioModelManager(client: FluidAudioModelDownloadClient(
            modelsExist: { _ in false },
            cacheDirectoryExists: { _ in false },
            validateCache: { _ in false },
            downloadAndLoad: { _, _, _ in throw DownloadFailure() }
        ))
        let modelName = VoiceInkTranscriptionModelCatalog.fluidAudioModels[0].name

        await manager.downloadFluidAudioModel(named: modelName)

        XCTAssertEqual(
            manager.downloadIssue(forModelNamed: modelName),
            .failed("Offline")
        )
    }

    func testInvalidBatchModelFailsBeforeRuntimeLoading() async {
        do {
            _ = try await IOSFluidAudioTranscriptionService().transcribeAudioFile(
                apiKey: "local-fluidaudio",
                model: "missing",
                fileURL: URL(fileURLWithPath: "/tmp/missing.wav"),
                language: nil,
                prompt: nil,
                customVocabulary: []
            )
            XCTFail("Expected invalid model failure")
        } catch let error as IOSFluidAudioTranscriptionError {
            guard case .invalidModel = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalFluidAudioProviderRequiresDownloadedModelAndExposesCatalog() {
        let state = VoiceInkProviderAPIKeyState()
        XCTAssertFalse(state.isReady(
            for: .localFluidAudio,
            localWhisperModelAvailable: true,
            localFluidAudioModelAvailable: false
        ))
        XCTAssertTrue(state.isReady(
            for: .localFluidAudio,
            localWhisperModelAvailable: true,
            localFluidAudioModelAvailable: true
        ))
        XCTAssertEqual(
            VoiceInkProviderKind.localFluidAudio.models(for: .transcription),
            VoiceInkTranscriptionModelCatalog.fluidAudioModels.map(\.name)
        )
    }

    func testLocalFluidAudioLiveCapabilityUsesSelectedModel() {
        let modelName = VoiceInkTranscriptionModelCatalog.fluidAudioModels[0].name
        let request = VoiceInkLiveTranscriptionPolicy.capability(for:
            Mode(
                name: "Parakeet",
                transcriptionProvider: .localFluidAudio,
                transcriptionModel: modelName,
                isPostProcessingEnabled: false
            ).runtimeConfiguration
        )

        XCTAssertEqual(request?.provider, .localFluidAudio)
        XCTAssertEqual(request?.selectedModel, modelName)
        XCTAssertEqual(request?.connectionModel, modelName)
        XCTAssertEqual(
            request?.finalCommitTimeoutNanoseconds,
            VoiceInkStreamingFinalCommitTimeout.localFluidAudioNanoseconds
        )
    }
}

private struct StubAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    let text: String

    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        text
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get {
            lock.withLock { storedValue }
        }
        set {
            lock.withLock { storedValue = newValue }
        }
    }
}
