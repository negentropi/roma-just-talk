//
//  OnboardingView.swift
//  VoiceInk-ios
//
//  Onboarding flow for first-time users
//

import SwiftUI
import VoiceInkCore

struct OnboardingView: View {
    @State private var currentStep = 0
    @Binding var isOnboardingComplete: Bool
    
    var body: some View {
        ZStack {
            // Step-by-step views without swiping
            if currentStep == 0 {
                WelcomeOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else if currentStep == 1 {
                ModelDownloadOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else if currentStep == 2 {
                ReadyOnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .ignoresSafeArea(.all)
    }
}

struct WelcomeOnboardingView: View {
    @Binding var currentStep: Int
    private let presentation = VoiceInkIOSOnboardingPresentation.welcome
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Header
            VStack(spacing: 24) {
                AppIconView()
                    .frame(width: 100, height: 100)
                    .cornerRadius(22)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                
                VStack(spacing: 12) {
                    Text(presentation.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(presentation.subtitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Features
            VStack(alignment: .leading, spacing: 24) {
                ForEach(presentation.features, id: \.title) { feature in
                    FeatureRow(
                        icon: feature.iconSystemName,
                        title: feature.title,
                        description: feature.description
                    )
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Continue Button
            VStack {
                Button(presentation.primaryButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = 1
                    }
                }
                .buttonStyle(OnboardingButtonStyle())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

struct ModelDownloadOnboardingView: View {
    @Binding var currentStep: Int
    @StateObject private var modelManager = LocalModelManager.shared
    @State private var showDownloadConfirmation = false
    private let onboardingPresentation = VoiceInkIOSOnboardingPresentation.modelDownload
    
    var baseModel = VoiceInkWhisperModelFiles.baseModel

    private var baseModelDownloadState: VoiceInkWhisperModelDownloadState {
        modelManager.downloadState(for: baseModel)
    }

    private var downloadConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation {
        .download(for: baseModel)
    }

    private var rowPresentation: VoiceInkWhisperModelDownloadRowPresentation {
        baseModelDownloadState.rowPresentation(for: baseModel)
    }
    
    var body: some View {
        let presentation = rowPresentation

        VStack(spacing: 0) {
            Spacer()
            
            // Header
            VStack(spacing: 24) {
                Image(systemName: onboardingPresentation.iconSystemName)
                    .font(.system(size: 70))
                    .foregroundColor(.accentColor)
                
                VStack(spacing: 12) {
                    Text(onboardingPresentation.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(onboardingPresentation.subtitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            Spacer()
            
            // Model Info Card
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(presentation.title)
                                .font(.headline).fontWeight(.semibold)
                            Text(presentation.subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        switch presentation.action {
                        case .downloaded:
                            Image(systemName: presentation.actionSystemImageName)
                                .foregroundColor(.green)
                                .font(.title)
                        case .downloading:
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        case .download:
                            Image(systemName: presentation.actionSystemImageName)
                                .foregroundColor(.accentColor)
                                .font(.title)
                        }
                    }
                    
                    if presentation.shouldShowProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(presentation.progress.compactStatusText)
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text(presentation.progress.percentText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.accentColor)
                            }
                            
                            ProgressView(value: presentation.progress.fraction)
                                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Bottom Action Buttons
            VStack(spacing: 16) {
                switch presentation.action {
                case .downloading:
                    Button(presentation.progress.compactStatusText) {}
                        .buttonStyle(OnboardingButtonStyle())
                        .disabled(true)

                case .downloaded:
                    Button(onboardingPresentation.continueButtonTitle) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = 2
                        }
                    }
                    .buttonStyle(OnboardingButtonStyle())

                case .download:
                    Button(action: {
                        showDownloadConfirmation = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: presentation.downloadButtonSystemImageName)
                            Text(presentation.downloadButtonTitle)
                        }
                    }
                    .buttonStyle(OnboardingButtonStyle())
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .alert(item: $modelManager.downloadError) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.primaryButtonTitle)) {
                    modelManager.downloadError = nil
                }
            )
        }
        .alert(downloadConfirmation.title, isPresented: $showDownloadConfirmation) {
            Button(downloadConfirmation.primaryButtonTitle) {
                downloadModel()
            }
            Button(downloadConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(downloadConfirmation.message)
        }
    }
    
    private func downloadModel() {
        Task {
            await modelManager.downloadModel(baseModel)
        }
    }
}

struct ReadyOnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    private let presentation = VoiceInkIOSOnboardingPresentation.ready
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Success Icon & Text
            VStack(spacing: 24) {
                Image(systemName: presentation.iconSystemName)
                    .font(.system(size: 70))
                    .foregroundColor(.green)
                
                VStack(spacing: 12) {
                    Text(presentation.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(presentation.subtitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            // How it works
            VStack(alignment: .leading, spacing: 24) {
                ForEach(presentation.steps, id: \.number) { step in
                    HowItWorksStep(
                        number: step.number,
                        title: step.title,
                        description: step.description
                    )
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Start Button
            VStack {
                Button(presentation.primaryButtonTitle) {
                    completeOnboarding()
                }
                .buttonStyle(OnboardingButtonStyle())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    @MainActor
    private func completeOnboarding() {
        AppSettings.shared.completeFirstTimeSetup()
        withAnimation(.easeInOut(duration: 0.5)) {
            isOnboardingComplete = true
        }
    }
}

// MARK: - Supporting Views

struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? Color.accentColor : Color.gray)
            .cornerRadius(16)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.accentColor)
                .frame(width: 40, alignment: .center)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HowItWorksStep: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - App Icon Helper

struct AppIconView: View {
    var body: some View {
        // Try to get the app icon from the bundle
        if let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last,
           let appIcon = UIImage(named: lastIcon) {
            Image(uiImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to system icon
            Image(systemName: VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName)
                .font(.system(size: 80))
                .foregroundColor(.blue)
        }
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
