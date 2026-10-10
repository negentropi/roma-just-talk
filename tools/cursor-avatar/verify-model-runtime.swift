import AVFoundation
import Metal

@main
struct VerifyModelRuntime {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { fatalError("model path and speech audio path required") }
        guard MTLCreateSystemDefaultDevice() == nil else { fatalError("CPU regression requires a Mac without a Metal device") }
        UserDefaults.standard.set("en", forKey: "SelectedLanguage")
        UserDefaults.standard.set(false, forKey: "IsVADEnabled")
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: arguments[2]))
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            fatalError("speech fixture must be mono 16 kHz audio")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { fatalError("floating-point audio required") }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let context = try await WhisperContext.createContext(path: arguments[1])
        let success = await context.fullTranscribe(samples: samples)
        let text = await context.getTranscription()
        await context.releaseResources()
        guard success, text.lowercased().contains("cursor") else { fatalError("speech did not transcribe the cursor fixture: \(text)") }
        print("PASS production WhisperContext loaded and transcribed without Metal: \(text)")
    }
}
