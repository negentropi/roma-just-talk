import Foundation
import AVFoundation
import os
import VoiceInkCore

class AudioProcessor {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioProcessor")

    enum AudioProcessingError: LocalizedError {
        case invalidAudioFile
        case conversionFailed
        case exportFailed
        case unsupportedFormat
        case sampleExtractionFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidAudioFile:
                return "The audio file is invalid or corrupted"
            case .conversionFailed:
                return "Failed to convert the audio format"
            case .exportFailed:
                return "Failed to export the processed audio"
            case .unsupportedFormat:
                return "The audio format is not supported"
            case .sampleExtractionFailed:
                return "Failed to extract audio samples"
            }
        }
    }
    
    func processAudioToSamples(_ url: URL) async throws -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw AudioProcessingError.invalidAudioFile
        }
        
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        let totalFrames = audioFile.length
        
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            channels: AVAudioChannelCount(VoiceInkPCM16Audio.monoChannelCount),
            interleaved: false
        )
        
        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }
        
        let chunkSize: AVAudioFrameCount = 50_000_000
        var allSamples: [Float] = []
        var currentFrame: AVAudioFramePosition = 0
        
        while currentFrame < totalFrames {
            let remainingFrames = totalFrames - currentFrame
            let framesToRead = min(chunkSize, AVAudioFrameCount(remainingFrames))
            
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw AudioProcessingError.conversionFailed
            }
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: inputBuffer, frameCount: framesToRead)
            
            if sampleRate == VoiceInkPCM16Audio.mono16kSampleRate
                && channels == AVAudioChannelCount(VoiceInkPCM16Audio.monoChannelCount) {
                let chunkSamples = convertToWhisperFormat(inputBuffer)
                allSamples.append(contentsOf: chunkSamples)
            } else {
                guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                    throw AudioProcessingError.conversionFailed
                }
                
                let ratio = VoiceInkPCM16Audio.mono16kSampleRate / sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
                
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
                    throw AudioProcessingError.conversionFailed
                }
                
                var error: NSError?
                let status = converter.convert(
                    to: outputBuffer,
                    error: &error,
                    withInputFrom: { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                )
                
                if let error = error {
                    throw AudioProcessingError.conversionFailed
                }
                
                if status == .error {
                    throw AudioProcessingError.conversionFailed
                }
                
                let chunkSamples = convertToWhisperFormat(outputBuffer)
                allSamples.append(contentsOf: chunkSamples)
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        return allSamples
    }
    
    private func convertToWhisperFormat(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        return VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: Int(buffer.format.channelCount),
            frameLength: Int(buffer.frameLength),
            sampleAt: { channel, frame in channelData[channel][frame] }
        )
    }
    func saveSamplesAsWav(samples: [Float], to url: URL) throws {
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            channels: AVAudioChannelCount(VoiceInkPCM16Audio.monoChannelCount),
            interleaved: true
        )

        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }

        let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        )
        
        guard let buffer = buffer else {
            throw AudioProcessingError.conversionFailed
        }
        
        let int16Samples = VoiceInkPCM16Audio.pcm16Samples(fromFloatSamples: samples)

        // Copy samples to buffer
        int16Samples.withUnsafeBufferPointer { int16Buffer in
            let int16Pointer = int16Buffer.baseAddress!
            buffer.int16ChannelData![0].update(from: int16Pointer, count: int16Samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        // Create audio file
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        try audioFile.write(from: buffer)
    }
} 
