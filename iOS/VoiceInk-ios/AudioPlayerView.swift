import SwiftUI
import VoiceInkCore

struct AudioPlayerView: View {
    let audioFilePath: String
    let duration: Double
    var timestamp: Date? = nil
    @StateObject private var player = AudioPlayer()
    
    var body: some View {
        VStack(spacing: 0) {
            if let ts = timestamp {
                HStack(spacing: 8) {
                    Image(systemName: VoiceInkAudioPlaybackPresentation.timestampSystemImageName)
                        .foregroundStyle(.secondary)
                    Text(VoiceInkDatePresentation.relativeTimestamp(ts))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if VoiceInkDurationPresentation.shouldShowPositiveDuration(duration) {
                        Text(VoiceInkDurationPresentation.metadataSeparatorText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: VoiceInkAudioPlaybackPresentation.durationSystemImageName)
                            .foregroundStyle(.secondary)
                        Text(VoiceInkDurationPresentation.minutesSeconds(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            if player.isLoading {
                // Simple loading state
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.blue)
                    
                    Text(VoiceInkAudioPlaybackPresentation.loadingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                // Clean player interface
                HStack(spacing: 16) {
                    // Play/Pause button
                    Button(action: {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: VoiceInkAudioPlaybackPresentation.playPauseSystemImageName(isPlaying: player.isPlaying))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: player.isPlaying ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        player.cyclePlaybackRate()
                    }) {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(VoiceInkAudioPlaybackRate.label(for: player.playbackRate))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VoiceInkAudioPlaybackRate.controlTitle)
                    
                    // Progress and time
                    VStack(spacing: 8) {
                        // Simple progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(.quaternaryLabel))
                                    .frame(height: 4)
                                
                                // Progress
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.blue)
                                    .frame(
                                        width: geometry.size.width * CGFloat(VoiceInkAudioPlaybackTimeline.progress(
                                            currentTime: player.currentTime,
                                            duration: player.duration
                                        )),
                                        height: 4
                                    )
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let seekTime = VoiceInkAudioPlaybackTimeline.time(
                                            atLocationX: Double(value.location.x),
                                            width: Double(geometry.size.width),
                                            duration: player.duration
                                        )
                                        player.seek(to: seekTime)
                                    }
                            )
                        }
                        .frame(height: 4)
                        
                        // Time display
                        HStack {
                            Text(VoiceInkDurationPresentation.minutesSeconds(player.currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(VoiceInkDurationPresentation.minutesSeconds(player.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            player.loadAudio(from: audioFilePath)
        }
        .onDisappear {
            player.stop()
        }
    }
}

#Preview {
    AudioPlayerView(audioFilePath: "", duration: 120)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}
