import SwiftUI
import VoiceInkCore

struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    private let barCount = VoiceInkAudioMeterLevel.macOSVisualizerBarCount
    private let barWidth = CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerBarWidth)
    private let barSpacing = CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerBarSpacing)

    var body: some View {
        TimelineView(.animation(minimumInterval: VoiceInkAudioMeterLevel.macOSVisualizerAnimationMinimumInterval)) { context in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color.opacity(0.85))
                        .frame(width: barWidth, height: barHeight(for: index, at: context.date))
                }
            }
        }
    }

    private func barHeight(for index: Int, at date: Date) -> CGFloat {
        CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
            forBarAt: index,
            time: date.timeIntervalSince1970,
            averagePower: audioMeter.averagePower,
            isActive: isActive,
            barCount: barCount
        ))
    }
}

// Flat bars shown when the recorder is idle (no audio input)
struct StaticVisualizer: View {
    private let barCount = VoiceInkAudioMeterLevel.macOSVisualizerBarCount
    private let barWidth = CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerBarWidth)
    private let barHeight = CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight)
    private let barSpacing = CGFloat(VoiceInkAudioMeterLevel.macOSVisualizerBarSpacing)
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.5))
                    .frame(width: barWidth, height: barHeight)
            }
        }
    }
}

// MARK: - Processing Status Display

struct ProcessingStatusDisplay: View {
    let presentation: VoiceInkRecorderProcessingPresentation
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(presentation.label)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ProgressAnimation(color: color, animationSpeed: presentation.progressAnimationInterval)
        }
        .frame(height: 28) // matches AudioVisualizer maxHeight to prevent layout shift
    }
}
