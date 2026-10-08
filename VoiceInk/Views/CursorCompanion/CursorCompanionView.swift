import SwiftUI
import VoiceInkCore

/// Draws the companion so that its artwork anchor sits at the center of the view.
struct CursorCompanionView: View {
    let style: VoiceInkCursorCompanionStyle
    let pose: VoiceInkCursorCompanionPose
    let phase: VoiceInkCursorCompanionPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var artScale: CGFloat = 0.2
    @State private var artRise: CGFloat = 10
    @State private var artSquash: CGFloat = 1
    @State private var artOpacity: Double = 0
    @State private var breath: CGFloat = 1
    @State private var successRingScale: CGFloat = 0.4
    @State private var successRingOpacity: Double = 0
    @State private var failureGlowOpacity: Double = 0
    @State private var failurePulses: CGFloat = 0
    @State private var shakes: CGFloat = 0
    @State private var sequence: Task<Void, Never>?

    private var artwork: CursorCompanionArtwork? {
        CursorCompanionArtwork.artwork(style: style, pose: pose)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.red.opacity(0.55), Color.red.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                ))
                .frame(width: 120, height: 120)
                .opacity(failureGlowOpacity)

            FailurePulseRing(progress: failurePulses, count: 3)
                .frame(width: 90, height: 90)

            Circle()
                .stroke(Color.white, lineWidth: 3)
                .blur(radius: 1.5)
                .shadow(color: .white, radius: 6)
                .frame(width: 36, height: 36)
                .scaleEffect(successRingScale)
                .opacity(successRingOpacity)

            if let artwork, let rendition = artwork.rendition {
                art(artwork, image: rendition.image, size: rendition.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { play(phase) }
        .onChange(of: phase) { _, newPhase in play(newPhase) }
        .onDisappear { sequence?.cancel() }
    }

    private func art(_ artwork: CursorCompanionArtwork, image: NSImage, size: CGSize) -> some View {
        let anchor = UnitPoint(x: artwork.anchor.x, y: artwork.anchor.y)
        return ZStack {
            if let caretBar = artwork.caretBar {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 1.5))
                    .frame(width: caretBar.width * size.width + 1, height: size.height)
                    .position(x: caretBar.x * size.width, y: size.height * 0.5)
            }
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(x: 1, y: artSquash, anchor: anchor)
        .scaleEffect(artScale * breath, anchor: anchor)
        .modifier(ShakeEffect(shakes: shakes))
        .opacity(artOpacity)
        .offset(
            x: (0.5 - artwork.anchor.x) * size.width,
            y: (0.5 - artwork.anchor.y) * size.height + artRise
        )
    }

    private func play(_ phase: VoiceInkCursorCompanionPhase) {
        sequence?.cancel()
        switch phase {
        case .hidden, .awaitingAudio:
            resetWithoutAnimation()
        case .arriving:
            resetWithoutAnimation()
            sequence = Task { @MainActor in await arrive() }
        case .listening:
            settle()
        case .leaving:
            leave()
        case .failed, .stalled:
            resetWithoutAnimation()
            sequence = Task { @MainActor in await fail() }
        }
    }

    private func resetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            artScale = reduceMotion ? 1 : 0.2
            artRise = reduceMotion ? 0 : 10
            artSquash = 1
            artOpacity = 0
            breath = 1
            successRingScale = 0.4
            successRingOpacity = 0
            failureGlowOpacity = 0
            failurePulses = 0
            shakes = 0
        }
    }

    /// A one-frame pause lets reset values render first; otherwise SwiftUI coalesces
    /// reset and target into one update and nothing animates.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func arrive() async {
        if !reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { successRingOpacity = 0.9 }
        }
        guard await pause(0.016) else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { artOpacity = 1 }
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            artScale = 1
            artRise = 0
        }
        withAnimation(.easeOut(duration: 0.1)) { artOpacity = 1 }
        withAnimation(.easeOut(duration: 0.7)) {
            successRingScale = 3.2
            successRingOpacity = 0
        }

        guard await pause(0.16) else { return }
        withAnimation(.easeOut(duration: 0.07)) { artSquash = 0.9 }

        guard await pause(0.08) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { artSquash = 1 }
    }

    private func settle() {
        withAnimation(.easeInOut(duration: 0.4)) {
            artScale = 1
            artRise = 0
            artSquash = 1
            artOpacity = 0.92
        }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            breath = 1.025
        }
    }

    private func leave() {
        withAnimation(.easeIn(duration: 0.3)) {
            if !reduceMotion {
                artScale = 0.6
            }
            breath = 1
            artOpacity = 0
            failureGlowOpacity = 0
        }
    }

    private func fail() async {
        guard await pause(0.016) else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) {
                artOpacity = 1
                failureGlowOpacity = 1
            }
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            artScale = 1
            artRise = 0
        }
        withAnimation(.easeOut(duration: 0.1)) { artOpacity = 1 }
        withAnimation(.easeOut(duration: 0.2)) { failureGlowOpacity = 1 }
        withAnimation(.linear(duration: 1.5)) { failurePulses = 3 }

        guard await pause(0.12) else { return }
        withAnimation(.linear(duration: 0.45)) { shakes = 3 }
    }
}

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * 2 * .pi), y: 0))
    }
}

/// One expanding red ring per whole unit of `progress`.
private struct FailurePulseRing: View, Animatable {
    var progress: CGFloat
    let count: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let cycle = progress - progress.rounded(.down)
        let isActive = progress > 0 && progress < count
        Circle()
            .stroke(Color.red, lineWidth: 2.5)
            .scaleEffect(0.4 + cycle)
            .opacity(isActive ? Double(1 - cycle) * 0.9 : 0)
    }
}
