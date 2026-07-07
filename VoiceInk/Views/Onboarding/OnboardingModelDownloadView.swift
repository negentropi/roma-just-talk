import SwiftUI
import VoiceInkCore

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var showTutorial: Bool

    private let presentation = VoiceInkMacOSOnboardingPresentation.modelDownload

    init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._showTutorial = State(
            initialValue: VoiceInkMacOSOnboardingProgressStore.stage().resumesTutorial
        )
    }

    private var canContinue: Bool {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }
        return transcriptionModelManager.usableModels.contains { $0.name == currentModel.name }
    }

    var body: some View {
        ZStack {
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                GeometryReader { geometry in
                    OnboardingBackgroundView()

                    VStack(spacing: 24) {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 76, height: 76)

                                Image(systemName: canContinue ? "checkmark.seal.fill" : "brain")
                                    .font(.system(size: canContinue ? 38 : 34))
                                    .foregroundColor(.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            VStack(spacing: 12) {
                                Text(presentation.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text(presentation.subtitle)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 620)
                            }
                        }

                        ModelManagementView(contentPadding: 24, minimumHeight: 420)
                            .frame(
                                width: min(max(geometry.size.width * 0.86, 620), 800),
                                height: min(max(geometry.size.height * 0.48, 420), 500)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)

                        VStack(spacing: 16) {
                            Button {
                                VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial)
                                withAnimation {
                                    showTutorial = true
                                }
                            } label: {
                                Text(presentation.nextButtonTitle)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor.opacity(canContinue ? 1 : 0.35))
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(!canContinue)

                            SkipButton(text: presentation.skipButtonTitle) {
                                VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial)
                                withAnimation {
                                    showTutorial = true
                                }
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
}
