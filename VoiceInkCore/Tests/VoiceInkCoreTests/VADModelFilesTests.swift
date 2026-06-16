import Foundation
@testable import VoiceInkCore

final class VADModelFilesTests: XCTestCase {
    func testSileroFilenameUsesSharedResourceNameAndExtension() {
        XCTAssertEqual(VoiceInkVADModelFiles.sileroResourceName, "ggml-silero-v5.1.2")
        XCTAssertEqual(VoiceInkVADModelFiles.sileroFileExtension, "bin")
        XCTAssertEqual(VoiceInkVADModelFiles.sileroFilename, "ggml-silero-v5.1.2.bin")
    }
}
