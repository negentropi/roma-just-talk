import Foundation
@testable import VoiceInkCore

final class WhisperModelFilesTests: XCTestCase {
    func testBootstrapModelsContainBaseModelSpec() {
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels, [VoiceInkWhisperModelFiles.baseModel])
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.id, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.filename, "ggml-base.bin")
    }

    func testDownloadableModelsMatchMacOSLocalWhisperCatalog() {
        XCTAssertEqual(
            VoiceInkWhisperModelFiles.downloadableModels.map(\.modelName),
            [
                "ggml-tiny",
                "ggml-tiny.en",
                "ggml-base",
                "ggml-base.en",
                "ggml-large-v2",
                "ggml-large-v3",
                "ggml-large-v3-turbo",
                "ggml-large-v3-turbo-q5_0"
            ]
        )

        let quantizedTurbo = VoiceInkWhisperModelFiles.downloadableModels.last
        XCTAssertEqual(quantizedTurbo?.filename, "ggml-large-v3-turbo-q5_0.bin")
        XCTAssertEqual(quantizedTurbo?.size, "547 MB")
        XCTAssertEqual(quantizedTurbo?.accuracy, 0.95)
        XCTAssertEqual(quantizedTurbo?.ramUsage, 1.0)
    }
}
