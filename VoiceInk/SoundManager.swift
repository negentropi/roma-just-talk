import Foundation
import SwiftUI
import VoiceInkCore

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let playbackEngine = SoundPlaybackEngine()
    @AppStorage(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey) private var isSoundFeedbackEnabled = VoiceInkRecordingFeedbackPreference.defaultIsSoundFeedbackEnabled

    private init() {
        setupSounds()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadCustomSounds),
            name: NSNotification.Name(VoiceInkCustomSoundPreference.changedNotificationName),
            object: nil
        )
    }

    private func setupSounds() {
        let customSoundManager = CustomSoundManager.shared
        playbackEngine.setup(
            soundURLs: [
                .defaultStart: customSoundManager.builtInSoundURL(for: .start),
                .defaultStop: customSoundManager.builtInSoundURL(for: .stop),
                .defaultEsc: CustomSoundManager.BuiltInSound.sound7.bundleURL,
                .customStart: customSoundManager.getCustomSoundURL(for: .start),
                .customStop: customSoundManager.getCustomSoundURL(for: .stop)
            ]
        )
    }

    @objc private func reloadCustomSounds() {
        setupSounds()
    }

    func playStartSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playStartSound()
    }

    func playStopSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playStopSound()
    }
    
    func playEscSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playEscSound()
    }
    
    var isEnabled: Bool {
        get { isSoundFeedbackEnabled }
        set {
            objectWillChange.send()
            isSoundFeedbackEnabled = newValue
        }
    }
} 
