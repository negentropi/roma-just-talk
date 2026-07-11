import Foundation
import XCTest
import VoiceInkCore
@testable import roma_just_talk

@MainActor
final class IOSCustomCloudModelTests: XCTestCase {
    func testManagerPersistsCRUDAndKeepsAPIKeysOutsideMetadata() throws {
        let suiteName = "IOSCustomCloudModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var keys: [UUID: String] = [:]
        let manager = IOSCustomCloudModelManager(
            defaults: defaults,
            saveAPIKey: { key, id in
                keys[id] = key
                return true
            },
            loadAPIKey: { keys[$0] },
            deleteAPIKey: { keys[$0] = nil }
        )

        let added = try manager.save(
            draft: draft(displayName: "Private Whisper", apiKey: "first-key"),
            isMultilingual: true
        )

        XCTAssertEqual(manager.modelNames, ["private-whisper"])
        XCTAssertEqual(keys[added.id], "first-key")
        let storedData = try XCTUnwrap(
            defaults.data(forKey: VoiceInkCustomCloudModelStorage.userDefaultsKey)
        )
        XCTAssertFalse(String(decoding: storedData, as: UTF8.self).contains("first-key"))

        let updated = try manager.save(
            draft: draft(displayName: "Private Whisper", apiKey: "second-key"),
            isMultilingual: false,
            editingID: added.id
        )
        XCTAssertEqual(updated.id, added.id)
        XCTAssertEqual(keys[added.id], "second-key")
        XCTAssertEqual(updated.supportedLanguages, VoiceInkLanguageCatalog.englishOnly)

        try manager.remove(id: added.id)
        XCTAssertTrue(manager.models.isEmpty)
        XCTAssertNil(keys[added.id])
    }

    func testCustomProviderAvailabilityAndModeRepairUseStoredModelNames() {
        let unavailable = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(),
            localWhisperModelAvailable: false
        )
        let available = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(),
            localWhisperModelAvailable: false,
            customCloudModelAvailable: true
        )

        XCTAssertFalse(unavailable.availableProviders(for: .transcription).contains(.customCloud))
        XCTAssertTrue(available.availableProviders(for: .transcription).contains(.customCloud))
        XCTAssertFalse(available.availableProviders(for: .postProcessing).contains(.customCloud))

        var mode = Mode.defaultLocalWhisper()
        mode.selectTranscriptionProvider(.customCloud, preferredModel: "private-whisper")
        XCTAssertEqual(mode.runtimeConfiguration.transcriptionProvider, .customCloud)
        XCTAssertEqual(mode.runtimeConfiguration.transcriptionModel, "private-whisper")

        mode.repairCustomCloudModelSelection(availableModelNames: ["replacement"])
        XCTAssertEqual(mode.transcriptionModel, "replacement")
    }

    func testCustomServiceResolvesModelKeyAndSharedRequestInputs() async throws {
        let model = storedModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-cloud-\(UUID().uuidString).wav")
        try Data([1, 2, 3]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var captured: (model: VoiceInkCustomCloudModelStoredRecord, key: String, data: Data, fileName: String, language: String?, prompt: String?)?
        let service = IOSCustomCloudTranscriptionService(
            models: [model],
            loadAPIKey: { $0 == model.id ? "secret" : nil },
            transcribe: { model, key, data, fileName, language, prompt in
                captured = (model, key, data, fileName, language, prompt)
                return "transcribed"
            }
        )

        let text = try await service.transcribeAudioFile(
            apiKey: "custom-cloud",
            model: model.name,
            fileURL: fileURL,
            language: VoiceInkLanguageCatalog.autoDetectCode,
            prompt: "context",
            customVocabulary: ["unused"]
        )

        XCTAssertEqual(text, "transcribed")
        XCTAssertEqual(captured?.model, model)
        XCTAssertEqual(captured?.key, "secret")
        XCTAssertEqual(captured?.data, Data([1, 2, 3]))
        XCTAssertEqual(captured?.fileName, fileURL.lastPathComponent)
        XCTAssertNil(captured?.language)
        XCTAssertEqual(captured?.prompt, "context")
    }

    func testCustomServiceReportsMissingModelAndKey() async throws {
        let model = storedModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-cloud-\(UUID().uuidString).wav")
        try Data([1]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let service = IOSCustomCloudTranscriptionService(
            models: [model],
            loadAPIKey: { _ in nil }
        )

        do {
            _ = try await service.transcribeAudioFile(
                apiKey: "custom-cloud",
                model: model.name,
                fileURL: fileURL,
                language: nil,
                prompt: nil,
                customVocabulary: []
            )
            XCTFail("Missing custom API key must fail")
        } catch VoiceInkCloudTranscriptionError.missingAPIKey {
            // Expected.
        }

        do {
            _ = try await service.transcribeAudioFile(
                apiKey: "custom-cloud",
                model: "deleted-model",
                fileURL: fileURL,
                language: nil,
                prompt: nil,
                customVocabulary: []
            )
            XCTFail("Missing custom model must fail")
        } catch VoiceInkCloudTranscriptionError.unsupportedProvider {
            // Expected.
        }
    }

    private func draft(displayName: String, apiKey: String) -> VoiceInkCustomCloudModelDraft {
        VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: displayName,
            apiEndpoint: "https://example.com/v1/audio/transcriptions",
            apiKey: apiKey,
            modelName: "whisper-1"
        )
    }

    private func storedModel() -> VoiceInkCustomCloudModelStoredRecord {
        VoiceInkCustomCloudModelStoredRecord(
            id: UUID(),
            name: "private-whisper",
            displayName: "Private Whisper",
            description: "Custom transcription model",
            apiEndpoint: "https://example.com/v1/audio/transcriptions",
            modelName: "whisper-1",
            isMultilingualModel: true,
            supportedLanguages: VoiceInkLanguageCatalog.whisperLanguages()
        )
    }
}
