import Foundation
@testable import VoiceInkCore

final class ImportedLocalWhisperRuntimeTests: XCTestCase {
    func testImportedLocalModelRemainsSelectedForRuntime() {
        let mode = Mode(
            name: "Imported",
            transcriptionProvider: .localWhisper,
            transcriptionModel: "custom-finetune"
        )

        XCTAssertEqual(
            mode.runtimeConfiguration(
                additionalLocalWhisperModelNames: ["custom-finetune"]
            ).transcriptionModel,
            "custom-finetune"
        )
        XCTAssertEqual(
            mode.runtimeConfiguration.transcriptionModel,
            VoiceInkTranscriptionModelCatalog.localBaseModel
        )
    }

    func testIOSRunSnapshotUsesImportedLocalModel() {
        let mode = Mode(
            name: "Imported",
            transcriptionProvider: .localWhisper,
            transcriptionModel: "custom-finetune"
        )
        let snapshot = VoiceInkIOSAppSettingsRunSnapshot(
            modes: [mode],
            selectedModeId: mode.id,
            selectedTranscriptionLanguage: "en",
            wordReplacementRules: [],
            customVocabulary: [],
            additionalLocalWhisperModelNames: ["custom-finetune"]
        )

        XCTAssertEqual(
            snapshot.transcriptionRunSettings().configuration.transcriptionModel,
            "custom-finetune"
        )
    }

    func testModeRepairFallsBackAfterImportedModelDeletion() {
        var mode = Mode(
            name: "Imported",
            transcriptionProvider: .localWhisper,
            transcriptionModel: "custom-finetune"
        )

        mode.repairLocalWhisperModelSelection(
            additionalLocalWhisperModelNames: ["custom-finetune"]
        )
        XCTAssertEqual(mode.transcriptionModel, "custom-finetune")

        mode.repairLocalWhisperModelSelection(additionalLocalWhisperModelNames: [])
        XCTAssertEqual(
            mode.transcriptionModel,
            VoiceInkTranscriptionModelCatalog.localBaseModel
        )
    }

    func testLocalModelRepairLeavesCloudSelectionUntouched() {
        var mode = Mode(
            name: "Cloud",
            transcriptionProvider: .openAI,
            transcriptionModel: "future-cloud-model"
        )

        mode.repairLocalWhisperModelSelection(
            additionalLocalWhisperModelNames: []
        )

        XCTAssertEqual(mode.transcriptionModel, "future-cloud-model")
    }
}
