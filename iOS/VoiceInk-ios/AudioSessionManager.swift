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

extension Notification.Name {
    static let voiceInkIOSAudioRoutingPreferenceDidChange = Notification.Name(
        "voiceInkIOSAudioRoutingPreferenceDidChange"
    )
}

struct VoiceInkIOSAudioInputRoute: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
}

@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published private var lifecycleState = VoiceInkAudioSessionLifecycleState()
    @Published private(set) var inputMode: VoiceInkAudioInputMode
    @Published private(set) var availableInputs: [VoiceInkIOSAudioInputRoute] = []
    @Published private(set) var currentInputUID: String?
    @Published private(set) var routeFallbackMessage: String?
    
    private var deactivationTimer: Timer?
    private var routeChangeCancellable: AnyCancellable?
    private let settings = AppSettings.shared
    
    private init() {
        inputMode = VoiceInkPlatformAudioInputPolicy.inputMode(for: .iOS)
        routeChangeCancellable = NotificationCenter.default.publisher(
            for: AVAudioSession.routeChangeNotification
        ).sink { [weak self] _ in
            Task { @MainActor in
                self?.reconcileRouteAfterChange()
            }
        }
    }
    
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
            refreshRouteState(session: audioSession)
            try applyConfiguredInput(to: audioSession)
            
            lifecycleState.markActivatedForRecording()
            cancelScheduledDeactivation()
            
            VoiceInkIOSLogger.audioSession.notice("\(VoiceInkAudioSessionDiagnostics.activatedForRecordingMessage, privacy: .public)")
            
        } catch let error as NSError {
            VoiceInkIOSLogger.audioSession.error("\(VoiceInkAudioSessionDiagnostics.activationFailedMessage(localizedDescription: error.localizedDescription, code: error.code), privacy: .public)")
            throw error
        }
    }

    func setUsesSystemManagedRouting(_ usesSystemManagedRouting: Bool) {
        inputMode = usesSystemManagedRouting ? .systemDefault : .custom
        VoiceInkAudioInputPreference.saveInputMode(inputMode)
        if !usesSystemManagedRouting,
           VoiceInkAudioInputPreference.selectedDeviceUID() == nil,
           let currentInputUID {
            VoiceInkAudioInputPreference.saveSelectedDeviceUID(currentInputUID)
        }
        NotificationCenter.default.post(
            name: .voiceInkIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
    }

    func selectInput(uid: String) {
        VoiceInkAudioInputPreference.saveSelectedDeviceUID(uid)
        inputMode = .custom
        VoiceInkAudioInputPreference.saveInputMode(.custom)
        NotificationCenter.default.post(
            name: .voiceInkIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
    }

    func refreshRouteState() {
        refreshRouteState(session: .sharedInstance())
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
        lifecycleState.scheduleDeactivationExecution(
            timeoutSeconds: timeoutSeconds
        ).applyRuntimeState(
            deactivateSession: deactivateSession,
            runCountdownTimer: startDeactivationCountdownTimer,
            countdownTimerDidStart: {
                VoiceInkIOSLogger.audioSession.notice(
                    "\(VoiceInkAudioSessionDiagnostics.deactivationScheduledMessage(seconds: Int(self.lifecycleState.timeoutRemaining)), privacy: .public)"
                )
            }
        )
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

    private func applyConfiguredInput(to audioSession: AVAudioSession) throws {
        refreshRouteState(session: audioSession)
        let inputs = audioSession.availableInputs ?? []
        let selection = VoiceInkIOSAudioRouteSelectionPolicy.selection(
            inputMode: inputMode,
            selectedInputUID: VoiceInkAudioInputPreference.selectedDeviceUID(),
            availableInputUIDs: inputs.map(\.uid)
        )
        let preferredInput = selection.preferredInputUID.flatMap { uid in
            inputs.first { $0.uid == uid }
        }
        try audioSession.setPreferredInput(preferredInput)
        routeFallbackMessage = selection.usedSystemFallback
            ? "The selected microphone is unavailable. iOS is choosing the input until it reconnects."
            : nil
        refreshRouteState(session: audioSession)
    }

    private func refreshRouteState(session: AVAudioSession) {
        availableInputs = (session.availableInputs ?? []).map {
            VoiceInkIOSAudioInputRoute(
                id: $0.uid,
                name: $0.portName,
                kind: $0.portType.rawValue
            )
        }
        currentInputUID = session.currentRoute.inputs.first?.uid
    }

    private func reconcileRouteAfterChange() {
        let audioSession = AVAudioSession.sharedInstance()
        refreshRouteState(session: audioSession)
        let inputs = audioSession.availableInputs ?? []
        let selection = VoiceInkIOSAudioRouteSelectionPolicy.selection(
            inputMode: inputMode,
            selectedInputUID: VoiceInkAudioInputPreference.selectedDeviceUID(),
            availableInputUIDs: inputs.map(\.uid)
        )
        routeFallbackMessage = selection.usedSystemFallback
            ? "The selected microphone is unavailable. iOS is choosing the input until it reconnects."
            : nil

        guard let preferredInputUID = selection.preferredInputUID,
              audioSession.preferredInput?.uid != preferredInputUID,
              inputs.contains(where: { $0.uid == preferredInputUID }) else {
            return
        }
        NotificationCenter.default.post(
            name: .voiceInkIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
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
