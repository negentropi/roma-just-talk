import Foundation
import AVFoundation
import Combine
import VoiceInkCore

@MainActor
final class AudioPlayer: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading: Bool = false
    @Published var playbackRate: Float = VoiceInkAudioPlaybackRate.current() {
        didSet { VoiceInkAudioPlaybackRate.save(playbackRate) }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    private var playbackState: VoiceInkAudioPlaybackState {
        get {
            VoiceInkAudioPlaybackState(
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration,
                playbackRate: playbackRate
            )
        }
        set {
            if isPlaying != newValue.isPlaying {
                isPlaying = newValue.isPlaying
            }
            if currentTime != newValue.currentTime {
                currentTime = newValue.currentTime
            }
            if duration != newValue.duration {
                duration = newValue.duration
            }
            if playbackRate != newValue.playbackRate {
                playbackRate = newValue.playbackRate
            }
        }
    }
    
    func loadAudio(from path: String) {
        isLoading = true
        
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            playbackState = playbackState.loaded(
                duration: audioPlayer?.duration ?? 0,
                resetCurrentTime: true
            )
            isLoading = false
        } catch {
            print("Failed to load audio: \(error)")
            isLoading = false
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)

            player.rate = playbackRate
            player.play()
            playbackState = playbackState.playing()
            startTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        playbackState = playbackState.paused()
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        playbackState = playbackState.stopped()
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        let state = playbackState.seeking(to: time)
        audioPlayer?.currentTime = state.currentTime
        playbackState = state
    }

    func cyclePlaybackRate() {
        let state = playbackState.cyclingPlaybackRate()
        playbackState = state
        audioPlayer?.rate = state.playbackRate
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: VoiceInkAudioPlaybackTimeline.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                let plan = VoiceInkAudioPlaybackTimerTickPlan.iOS(
                    currentTime: player.currentTime,
                    playerIsPlaying: player.isPlaying,
                    shellIsPlaying: self.isPlaying
                )
                var state = self.playbackState.updatingCurrentTime(plan.currentTime)

                if case .markStopped = plan.action {
                    state = state.paused()
                    self.playbackState = state
                    self.stopTimer()
                } else {
                    self.playbackState = state
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}
