import SwiftUI
import VoiceInkCore

struct AudioVisualizerView: View {
    let levels: [Float]

    private let barCount = VoiceInkAudioMeterLevel.iOSVisualizerBarCount
    private let barSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(
                            width: barWidth(in: proxy.size),
                            height: barHeight(for: index, in: proxy.size)
                        )
                        .animation(.easeOut(duration: 0.12), value: levels)
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 48)
        .accessibilityLabel(VoiceInkAudioMeterLevel.visualizerAccessibilityLabel)
    }

    private func barWidth(in size: CGSize) -> CGFloat {
        max(2, (size.width - 16) / CGFloat(barCount) - barSpacing)
    }

    private func barHeight(for index: Int, in size: CGSize) -> CGFloat {
        let level = CGFloat(VoiceInkAudioMeterLevel.visualizerLevel(
            forBarAt: index,
            levels: levels,
            barCount: barCount
        ))
        let minHeight = CGFloat(VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight)

        return minHeight + (size.height - minHeight) * level
    }
}

#Preview {
    AudioVisualizerView(
        levels: (0..<VoiceInkAudioMeterLevel.defaultLevelHistoryLimit).map { _ in .random(in: 0.05...0.7) }
    )
        .padding()
}
