import SwiftUI
import AVFoundation
import VoiceInkCore

class WaveformGenerator {
    private static let cache = NSCache<NSString, NSArray>()

    static func generateWaveformSamples(from url: URL, sampleCount: Int = 200) async -> [Float] {
        let cacheKey = url.absoluteString as NSString

        if let cachedSamples = cache.object(forKey: cacheKey) as? [Float] {
            return cachedSamples
        }
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        let stride = max(1, Int(frameCount) / sampleCount)
        let bufferSize = min(UInt32(4096), frameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else { return [] }

        do {
            var maxValues = [Float](repeating: 0.0, count: sampleCount)
            var sampleIndex = 0
            var framePosition: AVAudioFramePosition = 0

            while sampleIndex < sampleCount && framePosition < AVAudioFramePosition(frameCount) {
                audioFile.framePosition = framePosition
                try audioFile.read(into: buffer)

                if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    maxValues[sampleIndex] = abs(channelData[0])
                    sampleIndex += 1
                }

                framePosition += AVAudioFramePosition(stride)
            }

            let normalizedSamples: [Float]
            if let maxSample = maxValues.max(), maxSample > 0 {
                normalizedSamples = maxValues.map { $0 / maxSample }
            } else {
                normalizedSamples = maxValues
            }

            cache.setObject(normalizedSamples as NSArray, forKey: cacheKey)
            return normalizedSamples
        } catch {
            print(VoiceInkAudioPlaybackDiagnostics.macOSWaveformReadFailedMessage(
                errorDescription: String(describing: error)
            ))
            return []
        }
    }
}

class AudioPlayerManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false
    @Published var playbackRate: Float = VoiceInkAudioPlaybackRate.current() {
        didSet { VoiceInkAudioPlaybackRate.save(playbackRate) }
    }

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
    
    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            playbackState = playbackState.loaded(
                duration: audioPlayer?.duration ?? 0,
                resetCurrentTime: false
            )
            isLoadingWaveform = true
            
            Task {
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                await MainActor.run {
                    self.waveformSamples = samples
                    self.isLoadingWaveform = false
                }
            }
        } catch {
            print(VoiceInkAudioPlaybackDiagnostics.macOSLoadFailedMessage(
                localizedDescription: error.localizedDescription
            ))
        }
    }
    
    func play() {
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        playbackState = playbackState.playing()
        startTimer()
    }

    func cyclePlaybackRate() {
        let state = playbackState.cyclingPlaybackRate()
        playbackState = state
        audioPlayer?.rate = state.playbackRate
    }
    
    func pause() {
        audioPlayer?.pause()
        playbackState = playbackState.paused()
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        let state = playbackState.seeking(to: time)
        audioPlayer?.currentTime = state.currentTime
        playbackState = state
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: VoiceInkAudioPlaybackTimeline.updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let plan = VoiceInkAudioPlaybackTimerTickPlan.macOS(
                currentTime: self.audioPlayer?.currentTime ?? 0,
                duration: self.duration
            )
            self.playbackState = self.playbackState.applyingTimerTickPlan(plan)
            if let seekTime = plan.playerSeekTime {
                self.audioPlayer?.pause()
                self.audioPlayer?.currentTime = seekTime
            }
            if plan.shouldStopTimer {
                self.stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    deinit {
        cleanup()
    }
}

struct WaveformView: View {
    let samples: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isLoading: Bool
    var onSeek: (Double) -> Void
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let playbackProgress = VoiceInkAudioPlaybackTimeline.progress(
                currentTime: currentTime,
                duration: duration
            )
            let hoverProgress = VoiceInkAudioPlaybackTimeline.progress(
                locationX: Double(hoverLocation),
                width: Double(geometry.size.width)
            )

            ZStack(alignment: .leading) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(VoiceInkAudioPlaybackPresentation.loadingText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0.5) {
                        ForEach(0..<samples.count, id: \.self) { index in
                            WaveformBar(
                                sample: samples[index],
                                isPlayed: VoiceInkAudioPlaybackTimeline.sampleProgress(
                                    index: index,
                                    sampleCount: samples.count
                                ) <= playbackProgress,
                                totalBars: samples.count,
                                geometryWidth: geometry.size.width,
                                isHovering: isHovering,
                                hoverProgress: CGFloat(hoverProgress)
                            )
                        }
                    }
                    .opacity(0.6)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)

                    if isHovering {
                        Text(
                            VoiceInkDurationPresentation.minutesSeconds(
                                VoiceInkAudioPlaybackTimeline.time(
                                    atLocationX: Double(hoverLocation),
                                    width: Double(geometry.size.width),
                                    duration: duration
                                )
                            )
                        )
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: max(0, min(hoverLocation - 25, geometry.size.width - 50)))
                            .offset(y: -26)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: hoverLocation)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isLoading {
                            hoverLocation = value.location.x
                            onSeek(VoiceInkAudioPlaybackTimeline.time(
                                atLocationX: Double(value.location.x),
                                width: Double(geometry.size.width),
                                duration: duration
                            ))
                        }
                    }
            )
            .onHover { hovering in
                if !isLoading {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
            }
            .onContinuousHover { phase in
                if !isLoading {
                    if case .active(let location) = phase {
                        hoverLocation = location.x
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

struct WaveformBar: View {
    let sample: Float
    let isPlayed: Bool
    let totalBars: Int
    let geometryWidth: CGFloat
    let isHovering: Bool
    let hoverProgress: CGFloat
    
    private var isNearHover: Bool {
        let barPosition = geometryWidth / CGFloat(totalBars)
        let hoverPosition = hoverProgress * geometryWidth
        return abs(barPosition - hoverPosition) < 20
    }
    
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        isPlayed ? Color.primary : Color.primary.opacity(0.3),
                        isPlayed ? Color.primary.opacity(0.8) : Color.primary.opacity(0.2)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(
                width: max((geometryWidth / CGFloat(totalBars)) - 0.5, 1),
                height: max(CGFloat(sample) * 24, 2)
            )
            .scaleEffect(y: isHovering && isNearHover ? 1.15 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: isHovering && isNearHover)
    }
}

// MARK: - Reusable Components

private struct CircleIconButton: View {
    let icon: String
    let action: () -> Void
    var fillOpacity: Double = 0.06
    var iconFont: Font = .system(size: 14, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(fillOpacity))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundStyle(.primary)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AsyncCircleButton: View {
    let defaultIcon: String
    let isLoading: Bool
    let showSuccess: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.green)
                        } else {
                            Image(systemName: defaultIcon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBanner: View {
    let presentation: VoiceInkAudioPlaybackActionBannerPresentation

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(presentation.isError ? .red : .green)
            Text(presentation.message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(presentation.isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .stroke(presentation.isError ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {
    let url: URL
    let transcription: Transcription?
    var onInfoTap: (() -> Void)?
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var bannerPresentation: VoiceInkAudioPlaybackActionBannerPresentation?
    @State private var showPromptPopover = false
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    private var isOperationInProgress: Bool {
        isRetranscribing || isReEnhancing
    }

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, engine: engine)
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                samples: playerManager.waveformSamples,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isLoading: playerManager.isLoadingWaveform,
                onSeek: { playerManager.seek(to: $0) }
            )
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Text(VoiceInkDurationPresentation.minutesSeconds(playerManager.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    CircleIconButton(icon: "folder", action: showInFinder)
                        .help(VoiceInkAudioPlaybackPresentation.showInFinderHelpText)

                    Button(action: { playerManager.cyclePlaybackRate() }) {
                        Circle()
                            .fill(Color.primary.opacity(VoiceInkAudioPlaybackRate.isDefault(playerManager.playbackRate) ? 0.06 : 0.14))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(VoiceInkAudioPlaybackRate.label(for: playerManager.playbackRate))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(VoiceInkAudioPlaybackRate.controlTitle)

                    CircleIconButton(
                        icon: VoiceInkAudioPlaybackPresentation.enhancementPromptSystemImageName(
                            activePromptIcon: enhancementService.activePrompt?.icon
                        ),
                        action: { showPromptPopover.toggle() }
                    )
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.4)
                    .help(VoiceInkAudioPlaybackPresentation.selectEnhancementPromptHelpText)
                    .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                        EnhancementPromptPopover()
                            .environmentObject(enhancementService)
                    }

                    CircleIconButton(
                        icon: VoiceInkAudioPlaybackPresentation.playPauseSystemImageName(isPlaying: playerManager.isPlaying),
                        action: { playerManager.isPlaying ? playerManager.pause() : playerManager.play() }
                    )
                    .scaleEffect(isHovering ? 1.05 : 1.0)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHovering = hovering
                        }
                    }

                        AsyncCircleButton(
                            defaultIcon: "arrow.clockwise",
                            isLoading: isRetranscribing,
                            showSuccess: bannerPresentation == .retranscriptionSuccess,
                            action: retranscribeAudio
                        )
                    .disabled(isOperationInProgress)
                    .help(VoiceInkAudioPlaybackPresentation.retranscribeAudioHelpText)

                    if transcription != nil {
                        AsyncCircleButton(
                            defaultIcon: "wand.and.stars",
                            isLoading: isReEnhancing,
                            showSuccess: bannerPresentation == .reEnhancementSuccess,
                            action: reEnhanceOnly
                        )
                        .disabled(isOperationInProgress || !enhancementService.isEnhancementEnabled || !enhancementService.isConfigured)
                        .opacity(enhancementService.isEnhancementEnabled && enhancementService.isConfigured ? 1.0 : 0.4)
                        .help(VoiceInkAudioPlaybackPresentation.reEnhanceWithSelectedPromptHelpText)
                    }

                    if let onInfoTap {
                        CircleIconButton(icon: "info.circle", action: onInfoTap)
                            .help(VoiceInkAudioPlaybackPresentation.viewDetailsHelpText)
                    }
                }

                Spacer()

                Text(VoiceInkDurationPresentation.minutesSeconds(playerManager.duration))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            playerManager.loadAudio(from: url)
        }
        .onDisappear {
            playerManager.cleanup()
        }
        .overlay(
            VStack {
                if let bannerPresentation {
                    StatusBanner(presentation: bannerPresentation)
                }
                Spacer()
            }
            .padding(.top, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bannerPresentation)
        )
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func showTemporaryBanner(_ presentation: VoiceInkAudioPlaybackActionBannerPresentation) {
        bannerPresentation = presentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { bannerPresentation = nil }
        }
    }

    private func reEnhanceOnly() {
        guard let transcription = transcription else { return }

        if let unavailablePresentation = VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
            isEnabled: enhancementService.isEnhancementEnabled,
            isConfigured: enhancementService.isConfigured
        ) {
            showTemporaryBanner(unavailablePresentation)
            return
        }

        isReEnhancing = true
        bannerPresentation = nil

        Task {
            do {
                let enhancement = try await enhancementService.enhance(transcription.text)
                await MainActor.run {
                    transcription.applyEnhancementResult(enhancement)
                    try? modelContext.save()

                    isReEnhancing = false
                    showTemporaryBanner(.reEnhancementSuccess)
                }
            } catch {
                await MainActor.run {
                    isReEnhancing = false
                    showTemporaryBanner(.reEnhancementFailure(errorDescription: error.localizedDescription))
                }
            }
        }
    }

    private func retranscribeAudio() {
        guard let currentTranscriptionModel = engine.transcriptionModelManager.currentTranscriptionModel else {
            showTemporaryBanner(VoiceInkAudioPlaybackActionBannerPresentation.retranscriptionNoModelFailure)
            return
        }

        isRetranscribing = true
        bannerPresentation = nil

        Task {
            do {
                let _ = try await transcriptionService.retranscribeAudio(from: url, using: currentTranscriptionModel)
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscriptionSuccess)
                }
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscriptionFailure(errorDescription: error.localizedDescription))
                }
            }
        }
    }
}
