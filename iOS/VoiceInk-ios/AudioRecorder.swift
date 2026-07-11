import AVFoundation
import Combine
import Foundation
import VoiceInkCore

private final class VoiceInkIOSAudioCaptureSink: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let audioFile: AVAudioFile
    private let onPCMChunk: @Sendable (Data) -> Void
    private let onAveragePower: @Sendable (Float) -> Void

    init(
        inputFormat: AVAudioFormat,
        outputURL: URL,
        onPCMChunk: @escaping @Sendable (Data) -> Void,
        onAveragePower: @escaping @Sendable (Float) -> Void
    ) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: VoiceInkIOSAudioRecorderConfiguration.voiceRecording.sampleRate,
            channels: AVAudioChannelCount(
                VoiceInkIOSAudioRecorderConfiguration.voiceRecording.channelCount
            ),
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw VoiceInkAudioRecorderStartFailurePolicy.returnedFalseError()
        }

        self.outputFormat = outputFormat
        self.converter = converter
        self.audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        self.onPCMChunk = onPCMChunk
        self.onAveragePower = onAveragePower
    }

    func consume(_ inputBuffer: AVAudioPCMBuffer) {
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            max(1, ceil(Double(inputBuffer.frameLength) * ratio) + 1)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else { return }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, conversionError == nil, outputBuffer.frameLength > 0 else {
            return
        }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            return
        }

        guard let samples = outputBuffer.int16ChannelData?[0] else { return }
        let sampleCount = Int(outputBuffer.frameLength) * Int(outputFormat.channelCount)
        onPCMChunk(Data(bytes: samples, count: sampleCount * MemoryLayout<Int16>.size))
        onAveragePower(Self.averagePowerDecibels(samples: samples, count: sampleCount))
    }

    private static func averagePowerDecibels(
        samples: UnsafePointer<Int16>,
        count: Int
    ) -> Float {
        guard count > 0 else { return -160 }
        var sum: Double = 0
        for index in 0..<count {
            let normalized = Double(samples[index]) / Double(Int16.max)
            sum += normalized * normalized
        }
        let rms = sqrt(sum / Double(count))
        return rms > 0 ? Float(20 * log10(rms)) : -160
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var currentRecordingURL: URL?
    @Published var levelsHistory: [Float] = []

    private var audioEngine: AVAudioEngine?
    private var captureSink: VoiceInkIOSAudioCaptureSink?
    private let sessionManager = AudioSessionManager.shared

    func startRecording(
        onPCMChunk: @escaping @Sendable (Data) -> Void = { _ in }
    ) throws {
        try sessionManager.activateSessionForRecording()

        let url = VoiceInkStoredAudioFile.timestampedRecordingFileURL(
            in: VoiceInkIOSStorageDirectories.preparedRecordingsDirectory
        )
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let sink = try VoiceInkIOSAudioCaptureSink(
            inputFormat: inputFormat,
            outputURL: url,
            onPCMChunk: onPCMChunk,
            onAveragePower: { [weak self] averagePower in
                Task { @MainActor in
                    guard let self else { return }
                    levelsHistory = VoiceInkAudioMeterLevel.iOSMeterHistoryUpdatePlan(
                        averageDecibels: averagePower,
                        previousHistory: levelsHistory
                    ).levelsHistory
                }
            }
        )

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat
        ) { buffer, _ in
            sink.consume(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            try? VoiceInkStoredAudioFile.deleteExistingFile(for: url.absoluteString)
            throw error
        }

        audioEngine = engine
        captureSink = sink
        currentRecordingURL = url
        isRecording = true
    }

    func stopRecording() {
        applyStopPlan(VoiceInkAudioRecorderStopPolicy.plan(for: .keepRecordingFile))
    }

    func discard() {
        applyStopPlan(VoiceInkAudioRecorderStopPolicy.plan(for: .discardRecordingFile))
    }

    private func applyStopPlan(_ plan: VoiceInkAudioRecorderStopPlan) {
        plan.applyRuntimeState(
            stopRecorder: {
                audioEngine?.inputNode.removeTap(onBus: 0)
                audioEngine?.stop()
                audioEngine = nil
                captureSink = nil
            },
            invalidateMeterTimer: {},
            setIsRecording: { isRecording = $0 },
            clearAudioLevels: { levelsHistory.removeAll() },
            deleteCurrentRecordingFile: {
                try? VoiceInkStoredAudioFile.deleteExistingFile(
                    for: currentRecordingURL?.absoluteString
                )
            },
            clearCurrentRecordingURL: { currentRecordingURL = nil },
            scheduleSessionDeactivation: sessionManager.scheduleDeactivation
        )
    }
}
