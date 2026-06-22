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
        
        do {
            // Configure session for recording with background support
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
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
    
    /// Schedules session deactivation after configured timeout
    func scheduleDeactivation() {
        cancelScheduledDeactivation()
        
        let timeoutSeconds = settings.audioSessionTimeoutSeconds
        let deactivationPlan = lifecycleState.scheduleDeactivationExecution(timeoutSeconds: timeoutSeconds)
        
        if deactivationPlan.shouldDeactivateSession {
            deactivateSession()
            return
        }

        guard deactivationPlan.shouldRunCountdownTimer else { return }
        
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
                
                if self.lifecycleState.advanceCountdownExecution().shouldDeactivateSession {
                    self.deactivateSession()
                }
            }
        }
        
        VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.deactivationScheduledMessage(seconds: Int(lifecycleState.timeoutRemaining)), privacy: .public)")
    }
    
    /// Immediately deactivates the session
    func deactivateSession() {
        cancelScheduledDeactivation()
        
        guard lifecycleState.isSessionActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            lifecycleState.markDeactivated()
            VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.deactivatedMessage, privacy: .public)")
        } catch {
            VoiceInkIOSLogger.audioSession.error("\(VoiceInkAudioSessionDiagnostics.deactivationFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    // MARK: - Private Methods
    
    private func cancelScheduledDeactivation() {
        deactivationTimer?.invalidate()
        deactivationTimer = nil
        lifecycleState.cancelScheduledDeactivation()
    }
}
