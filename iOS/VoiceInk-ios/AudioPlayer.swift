import Foundation
import AVFoundation
import Combine
import OSLog
import VoiceInkCore

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var playbackState = VoiceInkAudioPlaybackState(
        isPlaying: false,
        currentTime: 0,
        duration: 0,
        playbackRate: VoiceInkAudioPlaybackRate.current()
    ) {
        didSet {
            if oldValue.playbackRate != playbackState.playbackRate {
                VoiceInkAudioPlaybackRate.save(playbackState.playbackRate)
            }
        }
    }
    @Published var isLoading: Bool = false
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let sessionManager = AudioSessionManager.shared
    
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
        
        do {
            try sessionManager.activateSessionForPlayback()

            player.rate = playbackState.playbackRate
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

    func togglePlayback() {
        playbackState.playPausePlan.applyRuntimeState(
            play: play,
            pause: pause
        )
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        playbackState = playbackState.stopped()
        stopTimer()
        sessionManager.scheduleDeactivation()
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
                    shellIsPlaying: self.playbackState.isPlaying
                )
                self.playbackState = self.playbackState.applyingTimerTickPlan(plan)
                plan.applyRuntimeState(
                    seekPlayer: { self.audioPlayer?.currentTime = $0 },
                    stopTimer: {
                        self.stopTimer()
                        self.sessionManager.scheduleDeactivation()
                    }
                )
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
