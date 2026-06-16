#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class WhisperModelFilesTests: XCTestCase {
    func testBootstrapModelsContainBaseModelSpec() {
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels, [VoiceInkWhisperModelFiles.baseModel])
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.id, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.filename, "ggml-base.bin")
    }
}
#endif
