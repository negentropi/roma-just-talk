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
    
    @Published var isSessionActive: Bool = false
    @Published var timeoutRemaining: TimeInterval = 0
    
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
            
            isSessionActive = true
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
        
        // If timeout is 0, deactivate immediately (legacy behavior)
        guard !VoiceInkAudioSessionTimeoutPreference.shouldDeactivateImmediately(timeoutSeconds) else {
            deactivateSession()
            return
        }
        
        timeoutRemaining = VoiceInkAudioSessionTimeoutPreference.deactivationInterval(for: timeoutSeconds)
        
        // Create timer that updates every second and deactivates when done
        deactivationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.timeoutRemaining -= 1
                
                if self.timeoutRemaining <= 0 {
                    self.deactivateSession()
                }
            }
        }
        
        print("🕒 Audio session deactivation scheduled in \(timeoutSeconds) seconds")
    }
    
    /// Immediately deactivates the session
    func deactivateSession() {
        cancelScheduledDeactivation()
        
        guard isSessionActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
            timeoutRemaining = 0
            print("🔇 Audio session deactivated")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func cancelScheduledDeactivation() {
        deactivationTimer?.invalidate()
        deactivationTimer = nil
        timeoutRemaining = 0
    }
}
