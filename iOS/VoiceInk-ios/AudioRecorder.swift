import AVFoundation
import Combine
import Foundation
import VoiceInkCore

private final class VoiceInkIOSAudioCaptureSink: @unchecked Sendable {
    private static let deliveryQueueKey = DispatchSpecificKey<UInt8>()

    private let lock = NSLock()
    private let deliveryQueue = DispatchQueue(label: "VoiceInk.iOSAudioCaptureSink.delivery")
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let preRollBuffer = VoiceInkPCM16PreRollBuffer()
    private let onAveragePower: @Sendable (Float) -> Void
    private var audioFile: AVAudioFile?
    private var onPCMChunk: (@Sendable (Data) -> Void)?
    private var deliveryGeneration: UInt64 = 0

    init(
        inputFormat: AVAudioFormat,
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
        self.onAveragePower = onAveragePower
        deliveryQueue.setSpecific(key: Self.deliveryQueueKey, value: 1)
    }

    func beginRecording(
        to outputURL: URL,
        onPCMChunk: @escaping @Sendable (Data) -> Void
    ) throws {
        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        lock.lock()
        defer { lock.unlock() }

        let preRollData = preRollBuffer.snapshotData()
        if !preRollData.isEmpty {
            try write(preRollData, to: file)
        }
        preRollBuffer.clear()
        deliveryGeneration &+= 1
        let generation = deliveryGeneration
        audioFile = file
        self.onPCMChunk = onPCMChunk

        let chunkByteCount = VoiceInkPCM16Audio.byteCount(
            forMono16kDuration: VoiceInkAudioPreRollPolicy.streamingChunkDurationSeconds
        )
        for chunk in VoiceInkPCM16Audio.monoPCM16Chunks(
            from: preRollData,
            maxByteCount: chunkByteCount
        ) {
            enqueue(chunk, generation: generation, callback: onPCMChunk)
        }
    }

    func finishRecording() {
        let isOnDeliveryQueue = DispatchQueue.getSpecific(key: Self.deliveryQueueKey) != nil
        lock.lock()
        audioFile = nil
        onPCMChunk = nil
        preRollBuffer.clear()
        if isOnDeliveryQueue {
            deliveryGeneration &+= 1
        }
        lock.unlock()

        guard !isOnDeliveryQueue else { return }
        deliveryQueue.sync {}
        lock.lock()
        deliveryGeneration &+= 1
        lock.unlock()
    }

    private func enqueue(
        _ data: Data,
        generation: UInt64,
        callback: @escaping @Sendable (Data) -> Void
    ) {
        deliveryQueue.async { [weak self] in
            guard self?.isCurrentDeliveryGeneration(generation) == true else { return }
            callback(data)
        }
    }

    private func isCurrentDeliveryGeneration(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return deliveryGeneration == generation
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

        guard let samples = outputBuffer.int16ChannelData?[0] else { return }
        let sampleCount = Int(outputBuffer.frameLength) * Int(outputFormat.channelCount)
        let data = Data(bytes: samples, count: sampleCount * MemoryLayout<Int16>.size)

        lock.lock()
        let isRecording = audioFile != nil
        if let audioFile {
            try? audioFile.write(from: outputBuffer)
            if let onPCMChunk {
                enqueue(data, generation: deliveryGeneration, callback: onPCMChunk)
            }
        } else {
            preRollBuffer.append(samples, sampleCount: sampleCount)
        }
        lock.unlock()

        if isRecording {
            onAveragePower(Self.averagePowerDecibels(samples: samples, count: sampleCount))
        }
    }

    private func write(_ data: Data, to file: AVAudioFile) throws {
        let sampleCount = data.count / VoiceInkPCM16Audio.bytesPerSample
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let destination = buffer.int16ChannelData?[0] else {
            return
        }

        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            UnsafeMutableRawPointer(destination).copyMemory(
                from: source,
                byteCount: sampleCount * VoiceInkPCM16Audio.bytesPerSample
            )
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        try file.write(from: buffer)
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
    private var routingPreferenceCancellable: AnyCancellable?
    private var shouldRestartCaptureAfterRecording = false
    private let sessionManager = AudioSessionManager.shared

    init() {
        routingPreferenceCancellable = NotificationCenter.default.publisher(
            for: .voiceInkIOSAudioRoutingPreferenceDidChange
        ).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isRecording {
                    self.shouldRestartCaptureAfterRecording = true
                    return
                }
                guard self.audioEngine != nil else { return }
                self.tearDownCapture()
                try? self.ensureCaptureRunning()
            }
        }
    }

    var isPreRollBuffering: Bool {
        audioEngine?.isRunning == true && !isRecording
    }

    func startPreRollBuffering() throws {
        try ensureCaptureRunning()
    }

    func startRecording(
        onPCMChunk: @escaping @Sendable (Data) -> Void = { _ in }
    ) throws {
        try ensureCaptureRunning()

        let url = VoiceInkStoredAudioFile.timestampedRecordingFileURL(
            in: VoiceInkIOSStorageDirectories.preparedRecordingsDirectory
        )
        guard let captureSink else {
            throw VoiceInkAudioRecorderStartFailurePolicy.returnedFalseError()
        }
        do {
            try captureSink.beginRecording(to: url, onPCMChunk: onPCMChunk)
        } catch {
            _ = try? VoiceInkStoredAudioFile.deleteExistingFile(for: url.absoluteString)
            throw error
        }

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
                captureSink?.finishRecording()
            },
            invalidateMeterTimer: {},
            setIsRecording: { isRecording = $0 },
            clearAudioLevels: { levelsHistory.removeAll() },
            deleteCurrentRecordingFile: {
                _ = try? VoiceInkStoredAudioFile.deleteExistingFile(
                    for: currentRecordingURL?.absoluteString
                )
            },
            clearCurrentRecordingURL: { currentRecordingURL = nil },
            scheduleSessionDeactivation: {}
        )
        restartCaptureForPendingRouteChangeIfNeeded()
    }

    func suspendPreRollBufferingIfIdle() {
        guard !isRecording else { return }
        tearDownCapture()
        sessionManager.deactivateSession()
    }

    private func ensureCaptureRunning() throws {
        if let audioEngine, audioEngine.isRunning, captureSink != nil {
            return
        }

        tearDownCapture()
        try sessionManager.activateSessionForRecording()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let sink: VoiceInkIOSAudioCaptureSink
        do {
            sink = try VoiceInkIOSAudioCaptureSink(
                inputFormat: inputFormat,
                onAveragePower: { [weak self] averagePower in
                    Task { @MainActor in
                        guard let self else { return }
                        self.levelsHistory = VoiceInkAudioMeterLevel.iOSMeterHistoryUpdatePlan(
                            averageDecibels: averagePower,
                            previousHistory: self.levelsHistory
                        ).levelsHistory
                    }
                }
            )
        } catch {
            sessionManager.deactivateSession()
            throw error
        }

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
            sessionManager.deactivateSession()
            throw error
        }

        audioEngine = engine
        captureSink = sink
    }

    private func tearDownCapture() {
        guard let audioEngine else {
            captureSink = nil
            return
        }
        captureSink?.finishRecording()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
        captureSink = nil
    }

    private func restartCaptureForPendingRouteChangeIfNeeded() {
        guard shouldRestartCaptureAfterRecording else { return }
        shouldRestartCaptureAfterRecording = false
        tearDownCapture()
        try? ensureCaptureRunning()
    }
}
