import Foundation
@preconcurrency import AVFoundation
import os
import VoiceInkCore

final class SoundPlaybackEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).soundPlayback", qos: .userInitiated)
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "SoundPlaybackEngine")

    private var players: [VoiceInkRecordingSoundPlayerSlot: AVAudioPlayer] = [:]

    func setup(
        soundURLs: [VoiceInkRecordingSoundPlayerSlot: URL?]
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            for slot in VoiceInkRecordingSoundPlaybackPolicy.setupSlots {
                self.players[slot] = self.makePlayer(from: soundURLs[slot] ?? nil, volume: slot.volume)
            }
        }
    }

    func play(_ cue: VoiceInkRecordingSoundCue) {
        queue.async { [weak self] in
            guard let self else { return }

            VoiceInkRecordingSoundPlaybackPolicy.playbackSlots(for: cue)
                .lazy
                .compactMap { self.players[$0] }
                .first?
                .play()
        }
    }

    private func makePlayer(from url: URL?, volume: Float) -> AVAudioPlayer? {
        guard let url else { return nil }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Failed to load sound: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
