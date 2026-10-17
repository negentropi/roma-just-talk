import Foundation
@preconcurrency import AVFoundation
import os
import RomaCore

final class SoundPlaybackEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(RomaAppIdentity.loggingSubsystem).soundPlayback", qos: .userInitiated)
    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.soundPlaybackEngine
    )

    private var players: [RomaRecordingSoundPlayerSlot: AVAudioPlayer] = [:]

    func setup(
        soundURLs: [RomaRecordingSoundPlayerSlot: URL?]
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            for slot in RomaRecordingSoundPlaybackPolicy.setupSlots {
                self.players[slot] = self.makePlayer(from: soundURLs[slot] ?? nil, volume: slot.volume)
            }
        }
    }

    func play(_ cue: RomaRecordingSoundCue) {
        queue.async { [weak self] in
            guard let self else { return }

            RomaRecordingSoundPlaybackPolicy.playbackSlots(for: cue)
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
            let message = RomaRecordingSoundPlaybackDiagnostics.loadFailedMessage(
                localizedDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
            return nil
        }
    }
}
