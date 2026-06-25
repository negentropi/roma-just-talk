//
//  AudioRecorder.swift
//  VoiceInk-ios
//

import Foundation
import Combine
import AVFoundation
import VoiceInkCore

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording: Bool = false
    @Published var currentRecordingURL: URL?
    @Published var levelsHistory: [Float] = [] // normalized 0...1

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let sessionManager = AudioSessionManager.shared

    func startRecording() throws {
        // Use session manager to activate audio session
        try sessionManager.activateSessionForRecording()

        let url = VoiceInkStoredAudioFile.timestampedRecordingFileURL(
            in: VoiceInkIOSStorageDirectories.preparedRecordingsDirectory
        )

        let configuration = VoiceInkIOSAudioRecorderConfiguration.voiceRecording

        audioRecorder = try AVAudioRecorder(url: url, settings: configuration.avAudioRecorderSettings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = configuration.isMeteringEnabled
        guard audioRecorder?.record() == true else {
            throw VoiceInkAudioRecorderStartFailurePolicy.returnedFalseError()
        }

        currentRecordingURL = url
        isRecording = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: VoiceInkAudioMeterLevel.iOSUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.audioRecorder?.updateMeters()

                if let power = self.audioRecorder?.averagePower(forChannel: 0) {
                    let meterPlan = VoiceInkAudioMeterLevel.iOSMeterHistoryUpdatePlan(
                        averageDecibels: power,
                        previousHistory: self.levelsHistory
                    )
                    self.levelsHistory = meterPlan.levelsHistory
                }
            }
        }
    }

    func stopRecording() {
        applyStopPlan(
            VoiceInkAudioRecorderStopPolicy.plan(for: .keepRecordingFile)
        )
    }

    func discard() {
        applyStopPlan(
            VoiceInkAudioRecorderStopPolicy.plan(for: .discardRecordingFile)
        )
    }

    private func applyStopPlan(_ plan: VoiceInkAudioRecorderStopPlan) {
        plan.applyRuntimeState(
            stopRecorder: {
                audioRecorder?.stop()
                audioRecorder = nil
            },
            invalidateMeterTimer: {
                meterTimer?.invalidate()
                meterTimer = nil
            },
            setIsRecording: { isRecording = $0 },
            clearAudioLevels: { levelsHistory.removeAll() },
            deleteCurrentRecordingFile: {
                try? VoiceInkStoredAudioFile.deleteExistingFile(for: currentRecordingURL?.absoluteString)
            },
            clearCurrentRecordingURL: { currentRecordingURL = nil },
            scheduleSessionDeactivation: sessionManager.scheduleDeactivation
        )
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {}

private extension VoiceInkIOSAudioRecorderConfiguration {
    var avAudioRecorderSettings: [String: Any] {
        [
            AVFormatIDKey: format.avFormatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsFloatKey: isFloatingPoint,
            AVEncoderAudioQualityKey: quality.avQualityRawValue
        ]
    }
}

private extension VoiceInkIOSAudioRecorderConfiguration.Format {
    var avFormatID: Int {
        switch self {
        case .linearPCM:
            return Int(kAudioFormatLinearPCM)
        }
    }
}

private extension VoiceInkIOSAudioRecorderConfiguration.Quality {
    var avQualityRawValue: Int {
        switch self {
        case .high:
            return AVAudioQuality.high.rawValue
        }
    }
}
