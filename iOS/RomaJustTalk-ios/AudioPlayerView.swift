import SwiftUI
import RomaCore

struct AudioPlayerView: View {
    let audioFilePath: String
    let duration: Double
    var timestamp: Date? = nil
    @StateObject private var player = AudioPlayer()
    
    var body: some View {
        VStack(spacing: 0) {
            if let ts = timestamp {
                HStack(spacing: 8) {
                    Image(systemName: RomaAudioPlaybackPresentation.timestampSystemImageName)
                        .foregroundStyle(.secondary)
                    Text(RomaDatePresentation.relativeTimestamp(ts))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if RomaDurationPresentation.shouldShowPositiveDuration(duration) {
                        Text(RomaDurationPresentation.metadataSeparatorText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: RomaAudioPlaybackPresentation.durationSystemImageName)
                            .foregroundStyle(.secondary)
                        Text(RomaDurationPresentation.minutesSeconds(duration))
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
                    
                    Text(RomaAudioPlaybackPresentation.loadingText)
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
                    Button(action: player.togglePlayback) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: RomaAudioPlaybackPresentation.playPauseSystemImageName(isPlaying: player.playbackState.isPlaying))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: player.playbackState.isPlaying ? 0 : 1)
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
                                Text(RomaAudioPlaybackRate.label(for: player.playbackState.playbackRate))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RomaAudioPlaybackRate.controlTitle)
                    
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
                                        width: geometry.size.width * CGFloat(RomaAudioPlaybackTimeline.progress(
                                            currentTime: player.playbackState.currentTime,
                                            duration: player.playbackState.duration
                                        )),
                                        height: 4
                                    )
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let seekTime = RomaAudioPlaybackTimeline.time(
                                            atLocationX: Double(value.location.x),
                                            width: Double(geometry.size.width),
                                            duration: player.playbackState.duration
                                        )
                                        player.seek(to: seekTime)
                                    }
                            )
                        }
                        .frame(height: 4)
                        
                        // Time display
                        HStack {
                            Text(RomaDurationPresentation.minutesSeconds(player.playbackState.currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(RomaDurationPresentation.minutesSeconds(player.playbackState.duration))
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
