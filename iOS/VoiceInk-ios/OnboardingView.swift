//
//  OnboardingView.swift
//  VoiceInk-ios
//
//  Onboarding flow for first-time users
//

import SwiftUI
import VoiceInkCore

struct OnboardingView: View {
    @State private var currentStep = VoiceInkIOSOnboardingStep.initial
    @Binding var isOnboardingComplete: Bool
    
    var body: some View {
        ZStack {
            // Step-by-step views without swiping
            switch currentStep {
            case .welcome:
                WelcomeOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .microphoneSetup:
                IOSMicrophonePermissionOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .modelDownload:
                ModelDownloadOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .keyboardSetup:
                KeyboardSetupOnboardingView(currentStep: $currentStep)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .ready:
                ReadyOnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .ignoresSafeArea(.all)
    }
}

struct WelcomeOnboardingView: View {
    @Binding var currentStep: VoiceInkIOSOnboardingStep
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
                        currentStep.advance()
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
    @Binding var currentStep: VoiceInkIOSOnboardingStep
    @StateObject private var modelManager = LocalModelManager.shared
    @State private var showDownloadConfirmation = false
    
    var body: some View {
        let snapshot = modelManager.managementSnapshot.iOSOnboardingModelDownloadSnapshot()
        let onboardingPresentation = snapshot.onboardingPresentation
        let presentation = snapshot.rowPresentation
        let primaryAction = snapshot.primaryAction
        let confirmedDownloadAction = snapshot.confirmedDownloadRuntimeAction {
            Task {
                await modelManager.downloadModel(snapshot.model)
            }
        }
        let primaryRuntimeAction = primaryAction.runtimeAction(
            continueSetup: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep.advance()
                }
            },
            requestDownload: {
                showDownloadConfirmation = true
            }
        )

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
                        
                        if presentation.shouldShowCircularProgressAccessory {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: presentation.actionSystemImageName)
                                .foregroundColor(presentation.actionTint.onboardingColor)
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
                Button(action: { primaryRuntimeAction?() }) {
                    HStack(spacing: 8) {
                        if let systemImageName = primaryAction.systemImageName {
                            Image(systemName: systemImageName)
                        }
                        Text(primaryAction.title)
                    }
                }
                .buttonStyle(OnboardingButtonStyle())
                .disabled(!primaryAction.isEnabled)
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
        .alert(snapshot.downloadConfirmation.title, isPresented: $showDownloadConfirmation) {
            Button(snapshot.downloadConfirmation.primaryButtonTitle, action: confirmedDownloadAction ?? {})
            Button(snapshot.downloadConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(snapshot.downloadConfirmation.message)
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
        let iconFiles = VoiceInkIOSAppIconPolicy.bundleIconFiles(from: Bundle.main.infoDictionary)
        let iconSource = VoiceInkIOSAppIconPolicy.source(
            iconFiles: iconFiles,
            canLoadImageNamed: { UIImage(named: $0) != nil }
        )

        switch iconSource {
        case .assetName(let iconName):
            if let appIcon = UIImage(named: iconName) {
                Image(uiImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackIcon(VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName)
            }

        case .fallbackSystemImageName(let systemImageName):
            fallbackIcon(systemImageName)
        }
    }

    private func fallbackIcon(_ systemImageName: String) -> some View {
        Image(systemName: systemImageName)
            .font(.system(size: 80))
            .foregroundColor(.blue)
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
