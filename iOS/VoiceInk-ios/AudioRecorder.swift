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

        // Whisper-compatible format: 16kHz mono WAV
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: VoiceInkPCM16Audio.mono16kSampleRate,
            AVNumberOfChannelsKey: VoiceInkPCM16Audio.monoChannelCount,
            AVLinearPCMBitDepthKey: VoiceInkPCM16Audio.bitsPerSample,
            AVLinearPCMIsBigEndianKey: VoiceInkPCM16Audio.isBigEndian,
            AVLinearPCMIsFloatKey: VoiceInkPCM16Audio.isFloatingPoint,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        guard audioRecorder?.record() == true else {
            let userInfo = [
                NSLocalizedDescriptionKey: VoiceInkRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription
            ]
            throw NSError(domain: VoiceInkAppIdentity.errorDomain(component: "AudioRecorder"), code: 1001, userInfo: userInfo)
        }

        currentRecordingURL = url
        isRecording = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: VoiceInkAudioMeterLevel.iOSUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.audioRecorder?.updateMeters()

                if let power = self.audioRecorder?.averagePower(forChannel: 0) {
                    let normalized = VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: power)
                    self.levelsHistory = VoiceInkAudioMeterLevel.boundedHistory(
                        appending: normalized,
                        to: self.levelsHistory
                    )
                }
            }
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        levelsHistory.removeAll()
        
        // Schedule session deactivation with timeout instead of immediate deactivation
        sessionManager.scheduleDeactivation()
    }

    func discard() {
        audioRecorder?.stop()
        audioRecorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        levelsHistory.removeAll()
        
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        
        // Schedule session deactivation after discard as well
        sessionManager.scheduleDeactivation()
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {}
