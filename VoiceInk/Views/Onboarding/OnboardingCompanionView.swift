import SwiftUI
import VoiceInkCore

struct OnboardingCompanionView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var cursorCompanionController: CursorCompanionController
    @State private var selection: VoiceInkCursorCompanionStyle
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var showTutorial: Bool

    private let presentation = VoiceInkMacOSOnboardingPresentation.companion

    init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._selection = State(initialValue: VoiceInkCursorCompanionPreference.style())
        self._showTutorial = State(
            initialValue: VoiceInkMacOSOnboardingProgressStore.stage().resumesTutorial
        )
    }

    var body: some View {
        ZStack {
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ZStack {
                    OnboardingBackgroundView()

                    VStack(spacing: 24) {
                        ScrollView(.vertical) {
                            VStack(spacing: 32) {
                                VStack(spacing: 12) {
                                    Text(presentation.title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)

                                    Text(presentation.subtitle)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 560)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                HStack(spacing: 16) {
                                    ForEach(VoiceInkCursorCompanionStyle.allCases) { style in
                                        CompanionStyleCard(
                                            style: style,
                                            isSelected: selection == style,
                                            noneCaption: presentation.noneCaption
                                        ) {
                                            selection = style
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                        }

                        VStack(spacing: 16) {
                            Button {
                                cursorCompanionController.style = selection
                                advance()
                            } label: {
                                Text(presentation.continueButtonTitle)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor)
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .accessibilityIdentifier("onboarding-companion-continue")

                            SkipButton(text: presentation.skipButtonTitle) {
                                advance()
                            }
                            .accessibilityIdentifier("onboarding-companion-skip")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .scaleEffect(scale)
                    .opacity(opacity)
                }
                .onAppear {
                    VoiceInkMacOSOnboardingProgressStore.saveStage(.companion)
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
        }
    }

    private func advance() {
        VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial)
        withAnimation { showTutorial = true }
    }
}

private struct CompanionStyleCard: View {
    let style: VoiceInkCursorCompanionStyle
    let isSelected: Bool
    let noneCaption: String
    let action: () -> Void

    @State private var replayID = 0

    // Pointer tip inside the tile, low enough that the perched art above it stays visible.
    private static let pointerTip = CGPoint(x: 52, y: 70)
    private static let tileSize = CGSize(width: 132, height: 116)

    var body: some View {
        Button {
            action()
            replayID += 1
        } label: {
            VStack(spacing: 10) {
                tile
                Text(style.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                if style == .none {
                    Text(noneCaption)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: Self.tileSize.width + 16, alignment: .top)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 1 : 0.1), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .onHover { isHovering in
            if isHovering { replayID += 1 }
        }
        .accessibilityLabel(style == .none ? "No companion" : "\(style.displayName) companion")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-companion-\(style.rawValue)")
    }

    private var tile: some View {
        let offset = CursorCompanionArtwork.perchOffsetFromPointerTip
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))

            PointerArrowShape()
                .fill(Color.white)
                .overlay(PointerArrowShape().stroke(Color.black, lineWidth: 1))
                .frame(width: 16, height: 25)
                .offset(x: Self.pointerTip.x, y: Self.pointerTip.y)

            if style != .none {
                CursorCompanionView(style: style, pose: .perch, phase: .arriving)
                    .id(replayID)
                    .frame(width: CursorCompanionPanel.contentSize.width, height: CursorCompanionPanel.contentSize.height)
                    .position(x: Self.pointerTip.x + offset.width, y: Self.pointerTip.y + offset.height)
            }
        }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Classic macOS arrow pointer with its hotspot at the top-left corner.
private struct PointerArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 0.80),
            CGPoint(x: 0.28, y: 0.62),
            CGPoint(x: 0.50, y: 1.0),
            CGPoint(x: 0.68, y: 0.93),
            CGPoint(x: 0.47, y: 0.56),
            CGPoint(x: 1.0, y: 0.56)
        ]
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}
