import Foundation
import AVFoundation
import Combine
import OSLog
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
            VoiceInkIOSLogger.audioPlayback.error("\(VoiceInkAudioPlaybackDiagnostics.loadFailedMessage(errorDescription: String(describing: error)), privacy: .public)")
            isLoading = false
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        let sessionConfiguration = VoiceInkIOSAudioPlaybackSessionConfiguration.notePlayback
        
        do {
            try AVAudioSession.sharedInstance().setCategory(sessionConfiguration.category.avCategory)
            try AVAudioSession.sharedInstance().setActive(true)

            player.rate = playbackRate
            player.play()
            playbackState = playbackState.playing()
            startTimer()
        } catch {
            VoiceInkIOSLogger.audioPlayback.error("\(VoiceInkAudioPlaybackDiagnostics.playFailedMessage(errorDescription: String(describing: error)), privacy: .public)")
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
                self.playbackState = self.playbackState.applyingTimerTickPlan(plan)
                if plan.shouldStopTimer {
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

private extension VoiceInkIOSAudioPlaybackSessionConfiguration.Category {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playback:
            return .playback
        }
    }
}
