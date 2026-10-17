//
//  AudioSessionManager.swift
//  RomaJustTalk-ios
//
//  Manages audio session lifecycle with configurable timeout
//  Prevents "session activation failed" errors by keeping session active between recordings
//

import Foundation
import Combine
import AVFoundation
import OSLog
import RomaCore

extension Notification.Name {
    static let romaIOSAudioRoutingPreferenceDidChange = Notification.Name(
        "romaIOSAudioRoutingPreferenceDidChange"
    )
}

struct RomaIOSAudioInputRoute: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
}

@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published private var lifecycleState = RomaAudioSessionLifecycleState()
    @Published private(set) var inputMode: RomaAudioInputMode
    @Published private(set) var availableInputs: [RomaIOSAudioInputRoute] = []
    @Published private(set) var currentInputUID: String?
    @Published private(set) var routeFallbackMessage: String?
    
    private var deactivationTimer: Timer?
    private var routeChangeCancellable: AnyCancellable?
    private let settings = AppSettings.shared
    
    private init() {
        inputMode = RomaPlatformAudioInputPolicy.inputMode(for: .iOS)
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
        let configuration = RomaIOSAudioSessionRecordingConfiguration.voiceRecording
        
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
            
            RomaIOSLogger.audioSession.notice("\(RomaAudioSessionDiagnostics.activatedForRecordingMessage, privacy: .public)")
            
        } catch let error as NSError {
            RomaIOSLogger.audioSession.error("\(RomaAudioSessionDiagnostics.activationFailedMessage(localizedDescription: error.localizedDescription, code: error.code), privacy: .public)")
            throw error
        }
    }

    func setUsesSystemManagedRouting(_ usesSystemManagedRouting: Bool) {
        inputMode = usesSystemManagedRouting ? .systemDefault : .custom
        RomaAudioInputPreference.saveInputMode(inputMode)
        if !usesSystemManagedRouting,
           RomaAudioInputPreference.selectedDeviceUID() == nil,
           let currentInputUID {
            RomaAudioInputPreference.saveSelectedDeviceUID(currentInputUID)
        }
        NotificationCenter.default.post(
            name: .romaIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
    }

    func selectInput(uid: String) {
        RomaAudioInputPreference.saveSelectedDeviceUID(uid)
        inputMode = .custom
        RomaAudioInputPreference.saveInputMode(.custom)
        NotificationCenter.default.post(
            name: .romaIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
    }

    func refreshRouteState() {
        refreshRouteState(session: .sharedInstance())
    }

    /// Activates audio session for note playback and cancels stale recording cleanup.
    func activateSessionForPlayback() throws {
        let audioSession = AVAudioSession.sharedInstance()
        let configuration = RomaIOSAudioPlaybackSessionConfiguration.notePlayback

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

        RomaIOSLogger.audioSession.notice("\(RomaAudioSessionDiagnostics.activatedForPlaybackMessage, privacy: .public)")
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
                RomaIOSLogger.audioSession.notice(
                    "\(RomaAudioSessionDiagnostics.deactivationScheduledMessage(seconds: Int(self.lifecycleState.timeoutRemaining)), privacy: .public)"
                )
            }
        )
    }

    private func startDeactivationCountdownTimer() {
        // Create timer with shared countdown cadence and deactivate when done
        deactivationTimer = Timer.scheduledTimer(
            withTimeInterval: RomaAudioSessionTimeoutPreference.countdownUpdateInterval,
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
                RomaIOSLogger.audioSession.notice("\(RomaAudioSessionDiagnostics.deactivatedMessage, privacy: .public)")
            }
        } catch {
            RomaIOSLogger.audioSession.error("\(RomaAudioSessionDiagnostics.deactivationFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
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
        let selection = RomaIOSAudioRouteSelectionPolicy.selection(
            inputMode: inputMode,
            selectedInputUID: RomaAudioInputPreference.selectedDeviceUID(),
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
            RomaIOSAudioInputRoute(
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
        let selection = RomaIOSAudioRouteSelectionPolicy.selection(
            inputMode: inputMode,
            selectedInputUID: RomaAudioInputPreference.selectedDeviceUID(),
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
            name: .romaIOSAudioRoutingPreferenceDidChange,
            object: nil
        )
    }
}

extension RomaIOSAudioSessionRecordingConfiguration.Category {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playAndRecord:
            return .playAndRecord
        }
    }
}

extension RomaIOSAudioSessionRecordingConfiguration.Mode {
    var avMode: AVAudioSession.Mode {
        switch self {
        case .spokenAudio:
            return .spokenAudio
        }
    }
}

extension RomaIOSAudioSessionRecordingConfiguration {
    var avOptions: AVAudioSession.CategoryOptions {
        options.reduce(into: []) { result, option in
            result.insert(option.avOption)
        }
    }
}

extension RomaIOSAudioSessionRecordingConfiguration.Option {
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

extension RomaIOSAudioPlaybackSessionConfiguration.Category {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playback:
            return .playback
        }
    }
}

extension RomaIOSAudioPlaybackSessionConfiguration.Mode {
    var avMode: AVAudioSession.Mode {
        switch self {
        case .spokenAudio:
            return .spokenAudio
        }
    }
}
