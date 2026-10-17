import SwiftUI
import RomaCore

struct AudioVisualizerView: View {
    let levels: [Float]

    private let barCount = RomaAudioMeterLevel.iOSVisualizerBarCount

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: CGFloat(RomaAudioMeterLevel.iOSVisualizerBarSpacing)) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(
                            width: CGFloat(RomaAudioMeterLevel.iOSVisualizerBarWidth(
                                containerWidth: Double(proxy.size.width)
                            )),
                            height: CGFloat(RomaAudioMeterLevel.iOSVisualizerBarHeight(
                                forBarAt: index,
                                levels: levels,
                                containerHeight: Double(proxy.size.height)
                            ))
                        )
                        .animation(.easeOut(duration: RomaAudioMeterLevel.iOSVisualizerAnimationDuration), value: levels)
                }
            }
            .padding(.horizontal, CGFloat(RomaAudioMeterLevel.iOSVisualizerHorizontalPadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: CGFloat(RomaAudioMeterLevel.iOSVisualizerFrameHeight))
        .accessibilityLabel(RomaAudioMeterLevel.visualizerAccessibilityLabel)
    }
}

#Preview {
    AudioVisualizerView(
        levels: (0..<RomaAudioMeterLevel.defaultLevelHistoryLimit).map { _ in .random(in: 0.05...0.7) }
    )
        .padding()
}
