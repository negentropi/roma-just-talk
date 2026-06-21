import SwiftUI
import VoiceInkCore

struct AudioVisualizerView: View {
    let levels: [Float]

    private let barCount = VoiceInkAudioMeterLevel.iOSVisualizerBarCount

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerBarSpacing)) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(
                            width: barWidth(in: proxy.size),
                            height: barHeight(for: index, in: proxy.size)
                        )
                        .animation(.easeOut(duration: VoiceInkAudioMeterLevel.iOSVisualizerAnimationDuration), value: levels)
                }
            }
            .padding(.horizontal, CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerHorizontalPadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerFrameHeight))
        .accessibilityLabel(VoiceInkAudioMeterLevel.visualizerAccessibilityLabel)
    }

    private func barWidth(in size: CGSize) -> CGFloat {
        CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: Double(size.width)))
    }

    private func barHeight(for index: Int, in size: CGSize) -> CGFloat {
        CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
            forBarAt: index,
            levels: levels,
            containerHeight: Double(size.height)
        ))
    }
}

#Preview {
    AudioVisualizerView(
        levels: (0..<VoiceInkAudioMeterLevel.defaultLevelHistoryLimit).map { _ in .random(in: 0.05...0.7) }
    )
        .padding()
}
