import Foundation
import VoiceInkCore

final class SupportedMediaTests: XCTestCase {
    func testSupportedFileExtensionsPreserveMacOSImportPolicy() {
        XCTAssertEqual(
            VoiceInkSupportedMedia.fileExtensions,
            [
                "wav", "mp3", "m4a", "aiff", "mp4", "mov", "aac", "flac", "caf",
                "amr", "ogg", "oga", "opus", "3gp"
            ]
        )
    }

    func testSupportedFileExtensionLookupIsCaseInsensitive() {
        XCTAssertTrue(VoiceInkSupportedMedia.isSupportedFileExtension("WAV"))
        XCTAssertTrue(VoiceInkSupportedMedia.isSupportedFileExtension("m4a"))
        XCTAssertFalse(VoiceInkSupportedMedia.isSupportedFileExtension("txt"))
    }

    func testSupportedURLAcceptsKnownExtensions() {
        XCTAssertTrue(
            VoiceInkSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.MOV")
            )
        )
    }

    func testSupportedURLRejectsUnknownExtensionWithoutContentType() {
        XCTAssertFalse(
            VoiceInkSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.voiceink-unknown")
            )
        )
    }
}
