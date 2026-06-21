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
            
            print("🎙️ Audio session activated for recording")
            
        } catch let error as NSError {
            print("⚠️ Audio session activation failed: \(error.localizedDescription) (Code: \(error.code))")
            throw error
        }
    }
    
    /// Schedules session deactivation after configured timeout
    func scheduleDeactivation() {
        cancelScheduledDeactivation()
        
        let timeoutSeconds = settings.audioSessionTimeoutSeconds
        let deactivationPlan = lifecycleState.scheduleDeactivation(timeoutSeconds: timeoutSeconds)
        
        switch deactivationPlan {
        case .immediate:
            deactivateSession()
            return
        case .delayed:
            break
        }
        
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
                
                if self.lifecycleState.advanceCountdown() == .immediate {
                    self.deactivateSession()
                }
            }
        }
        
        print("🕒 Audio session deactivation scheduled in \(Int(lifecycleState.timeoutRemaining)) seconds")
    }
    
    /// Immediately deactivates the session
    func deactivateSession() {
        cancelScheduledDeactivation()
        
        guard lifecycleState.isSessionActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            lifecycleState.markDeactivated()
            print("🔇 Audio session deactivated")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func cancelScheduledDeactivation() {
        deactivationTimer?.invalidate()
        deactivationTimer = nil
        lifecycleState.cancelScheduledDeactivation()
    }
}
