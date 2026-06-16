import SwiftUI

struct AudioVisualizerView: View {
    let levels: [CGFloat]

    private let barCount = 8
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
        .accessibilityLabel("Audio level visualizer")
    }

    private func barWidth(in size: CGSize) -> CGFloat {
        max(2, (size.width - 16) / CGFloat(barCount) - barSpacing)
    }

    private func barHeight(for index: Int, in size: CGSize) -> CGFloat {
        guard !levels.isEmpty else { return 4 }

        let span = max(1, min(levels.count, barCount))
        let step = max(1, levels.count / span)
        let sourceIndex = max(0, levels.count - 1 - index * step)
        let level = max(0, min(1, levels[sourceIndex]))
        let minHeight: CGFloat = 4

        return minHeight + (size.height - minHeight) * level
    }
}

#Preview {
    AudioVisualizerView(levels: (0..<40).map { _ in .random(in: 0.05...0.7) })
        .padding()
}
