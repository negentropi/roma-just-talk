//
//  AudioSessionManager.swift
//  VoiceInk-ios
//
//  Manages audio session lifecycle with configurable timeout
//  Prevents "session activation failed" errors by keeping session active between recordings
//

import Foundation
import Combine
import AVFoundation
import OSLog
import VoiceInkCore

@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published private var lifecycleState = VoiceInkAudioSessionLifecycleState()
    
    private var deactivationTimer: Timer?
    private let settings = AppSettings.shared
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Activates audio session for recording with optimal settings
    func activateSessionForRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        let configuration = VoiceInkIOSAudioSessionRecordingConfiguration.voiceRecording
        
        do {
            try audioSession.setCategory(
                configuration.category.avCategory,
                mode: configuration.mode.avMode,
                options: configuration.avOptions
            )
            
            // Activate the session
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            lifecycleState.markActivatedForRecording()
            cancelScheduledDeactivation()
            
            VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.activatedForRecordingMessage, privacy: .public)")
            
        } catch let error as NSError {
            VoiceInkIOSLogger.audioSession.error("\(VoiceInkAudioSessionDiagnostics.activationFailedMessage(localizedDescription: error.localizedDescription, code: error.code), privacy: .public)")
            throw error
        }
    }

    /// Activates audio session for note playback and cancels stale recording cleanup.
    func activateSessionForPlayback() throws {
        let audioSession = AVAudioSession.sharedInstance()
        let configuration = VoiceInkIOSAudioPlaybackSessionConfiguration.notePlayback

        let activationPlan = lifecycleState.beginPlaybackActivation()
        try activationPlan.applyRuntimeState(
            cancelScheduledDeactivation: invalidateDeactivationTimer,
            deactivateCurrentSession: {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            },
            markDeactivated: { lifecycleState.markDeactivated() }
        )

        try audioSession.setCategory(
            configuration.category.avCategory,
            mode: configuration.mode.avMode
        )

        try audioSession.setActive(true)
        lifecycleState.markActivatedForPlayback()

        VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.activatedForPlaybackMessage, privacy: .public)")
    }
    
    /// Schedules session deactivation after configured timeout
    func scheduleDeactivation() {
        cancelScheduledDeactivation()
        
        let timeoutSeconds = settings.audioSessionTimeoutSeconds
        let executionAction = lifecycleState.scheduleDeactivationExecution(
            timeoutSeconds: timeoutSeconds
        ).applyRuntimeState(
            deactivateSession: deactivateSession,
            runCountdownTimer: startDeactivationCountdownTimer
        )

        guard executionAction == .runCountdownTimer else { return }

        VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.deactivationScheduledMessage(seconds: Int(lifecycleState.timeoutRemaining)), privacy: .public)")
    }

    private func startDeactivationCountdownTimer() {
        // Create timer with shared countdown cadence and deactivate when done
        deactivationTimer = Timer.scheduledTimer(
            withTimeInterval: VoiceInkAudioSessionTimeoutPreference.countdownUpdateInterval,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                self.lifecycleState.advanceCountdownExecution().applyRuntimeState(
                    deactivateSession: { self.deactivateSession() },
                    runCountdownTimer: {}
                )
            }
        }
    }
    
    /// Immediately deactivates the session
    func deactivateSession() {
        let deactivationPlan = lifecycleState.beginImmediateDeactivation()

        do {
            let didDeactivate = try deactivationPlan.applyRuntimeState(
                cancelScheduledDeactivation: invalidateDeactivationTimer,
                deactivateSession: {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                },
                markDeactivated: { lifecycleState.markDeactivated() }
            )
            if didDeactivate {
                VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.deactivatedMessage, privacy: .public)")
            }
        } catch {
            VoiceInkIOSLogger.audioSession.error("\(VoiceInkAudioSessionDiagnostics.deactivationFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    // MARK: - Private Methods
    
    private func cancelScheduledDeactivation() {
        invalidateDeactivationTimer()
        lifecycleState.cancelScheduledDeactivation()
    }

    private func invalidateDeactivationTimer() {
        deactivationTimer?.invalidate()
        deactivationTimer = nil
    }
}

extension VoiceInkIOSAudioSessionRecordingConfiguration.Category {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playAndRecord:
            return .playAndRecord
        }
    }
}

extension VoiceInkIOSAudioSessionRecordingConfiguration.Mode {
    var avMode: AVAudioSession.Mode {
        switch self {
        case .spokenAudio:
            return .spokenAudio
        }
    }
}

extension VoiceInkIOSAudioSessionRecordingConfiguration {
    var avOptions: AVAudioSession.CategoryOptions {
        options.reduce(into: []) { result, option in
            result.insert(option.avOption)
        }
    }
}

extension VoiceInkIOSAudioSessionRecordingConfiguration.Option {
    var avOption: AVAudioSession.CategoryOptions {
        switch self {
        case .defaultToSpeaker:
            return .defaultToSpeaker
        case .allowBluetooth:
            return .allowBluetooth
        case .allowBluetoothA2DP:
            return .allowBluetoothA2DP
        case .mixWithOthers:
            return .mixWithOthers
        }
    }
}

extension VoiceInkIOSAudioPlaybackSessionConfiguration.Category {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playback:
            return .playback
        }
    }
}

extension VoiceInkIOSAudioPlaybackSessionConfiguration.Mode {
    var avMode: AVAudioSession.Mode {
        switch self {
        case .spokenAudio:
            return .spokenAudio
        }
    }
}
