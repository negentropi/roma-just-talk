@testable import VoiceInkCore

final class AudioRecorderConfigurationTests: XCTestCase {
    func testIOSAudioRecorderConfigurationUsesMono16kPCM16Policy() {
        XCTAssertEqual(
            VoiceInkIOSAudioRecorderConfiguration.voiceRecording,
            VoiceInkIOSAudioRecorderConfiguration(
                format: .linearPCM,
                sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
                channelCount: VoiceInkPCM16Audio.monoChannelCount,
                bitDepth: VoiceInkPCM16Audio.bitsPerSample,
                isBigEndian: VoiceInkPCM16Audio.isBigEndian,
                isFloatingPoint: VoiceInkPCM16Audio.isFloatingPoint,
                quality: .high,
                isMeteringEnabled: true
            )
        )
    }
}
