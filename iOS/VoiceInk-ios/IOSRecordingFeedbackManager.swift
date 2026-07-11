import AVFoundation
import UIKit
import VoiceInkCore

@MainActor
final class IOSRecordingFeedbackManager {
    static let shared = IOSRecordingFeedbackManager()

    private var activePlayers: [String: AVAudioPlayer] = [:]

    private init() {}

    func playStartFeedback() async {
        let plan = VoiceInkIOSRecordingFeedbackPreference.plan()
        playHaptic(for: .start, when: plan.playsHaptic)
        guard plan.playsSound, let player = makePlayer(for: .start) else { return }

        prepareAmbientPlaybackSession()
        activePlayers["start"] = player
        player.play()
        try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
        activePlayers["start"] = nil
    }

    func playStopFeedback() {
        let plan = VoiceInkIOSRecordingFeedbackPreference.plan()
        playHaptic(for: .stop, when: plan.playsHaptic)
        guard plan.playsSound, let player = makePlayer(for: .stop) else { return }

        prepareAmbientPlaybackSession()
        activePlayers["stop"] = player
        player.play()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
            self?.activePlayers["stop"] = nil
        }
    }

    func preview(_ type: VoiceInkCustomSoundType) {
        guard let player = makePlayer(for: type.recordingSoundCue) else { return }
        prepareAmbientPlaybackSession()
        activePlayers[type.rawValue] = player
        player.play()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
            self?.activePlayers[type.rawValue] = nil
        }
    }

    func importCustomSound(from sourceURL: URL, for type: VoiceInkCustomSoundType) -> Result<Void, VoiceInkCustomSoundError> {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure(.fileNotFound)
        }
        guard let player = try? AVAudioPlayer(contentsOf: sourceURL) else {
            return .failure(.invalidAudioFile)
        }
        if let error = VoiceInkCustomSoundPreference.preflightValidationError(
            fileExists: true,
            duration: player.duration
        ) {
            return .failure(error)
        }

        let directory = customSoundsDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(.directoryCreationFailed)
        }

        let result = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: type
        ).applyRuntimeState(
            removeExistingDestination: { try FileManager.default.removeItem(at: $0) },
            copyToDestination: { try FileManager.default.copyItem(at: sourceURL, to: $0) }
        )

        switch result {
        case .success(let filename):
            VoiceInkCustomSoundPreference.saveCustomFilename(filename, for: type)
            VoiceInkCustomSoundPreference.saveIsUsingCustomSound(true, for: type)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private var customSoundsDirectory: URL {
        VoiceInkIOSStorageDirectories.documentsDirectory
            .appendingPathComponent(VoiceInkCustomSoundPreference.customSoundsRelativeDirectory, isDirectory: true)
    }

    private func makePlayer(for cue: VoiceInkRecordingSoundCue) -> AVAudioPlayer? {
        let type: VoiceInkCustomSoundType
        switch cue {
        case .start:
            type = .start
        case .stop:
            type = .stop
        case .esc:
            return nil
        }
        let state = VoiceInkCustomSoundPreference.selectionState(for: type)
        let url = state.customSoundURL(in: customSoundsDirectory)
            ?? Bundle.main.url(
                forResource: state.selectedBuiltInSound.rawValue,
                withExtension: state.selectedBuiltInSound.fileExtension
            )
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = VoiceInkRecordingSoundPlayerSlot.defaultStart.volume
        player.prepareToPlay()
        return player
    }

    private func prepareAmbientPlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func playHaptic(for cue: VoiceInkRecordingSoundCue, when isEnabled: Bool) {
        guard isEnabled else { return }
        switch cue {
        case .start:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .stop:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .esc:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
