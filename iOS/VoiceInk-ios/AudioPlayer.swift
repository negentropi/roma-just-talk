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
    
    func loadAudio(from path: String) {
        isLoading = true
        
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
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
            isPlaying = true
            startTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        let clampedTime = VoiceInkAudioPlaybackTimeline.clampedTime(time, duration: duration)
        audioPlayer?.currentTime = clampedTime
        currentTime = clampedTime
    }

    func cyclePlaybackRate() {
        playbackRate = VoiceInkAudioPlaybackRate.next(after: playbackRate)
        audioPlayer?.rate = playbackRate
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
                self.currentTime = plan.currentTime

                if case .markStopped = plan.action {
                    self.isPlaying = false
                    self.stopTimer()
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
