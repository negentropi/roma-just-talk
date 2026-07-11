import SwiftUI
import UIKit
import VoiceInkCore

struct KeyboardSetupOnboardingView: View {
    @Binding var currentStep: VoiceInkIOSOnboardingStep

    var body: some View {
        KeyboardSetupView(
            continueAction: advance,
            skipAction: advance
        )
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep.advance()
        }
    }
}

struct KeyboardSetupView: View {
    @Environment(\.openURL) private var openURL
    @State private var readiness: VoiceInkIOSKeyboardReadinessStatus = .unverified
    @State private var verificationStartedAt = Date()
    @State private var testText = ""

    private let coordinator = AppGroupCoordinator.shared
    private let continueAction: (() -> Void)?
    private let skipAction: (() -> Void)?

    init(
        continueAction: (() -> Void)? = nil,
        skipAction: (() -> Void)? = nil
    ) {
        self.continueAction = continueAction
        self.skipAction = skipAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                readinessStatus
                instructions
                verificationField
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, continueAction == nil ? 32 : 132)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(VoiceInkIOSKeyboardSetupPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let continueAction {
                onboardingActions(continueAction: continueAction)
            }
        }
        .onAppear(perform: beginVerification)
        .onDisappear {
            coordinator.onKeyboardReadinessReported = nil
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: VoiceInkIOSKeyboardSetupPresentation.iconSystemName)
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text(VoiceInkIOSKeyboardSetupPresentation.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(VoiceInkIOSKeyboardSetupPresentation.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var readinessStatus: some View {
        let status = VoiceInkIOSKeyboardSetupPresentation.status(readiness)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: status.iconSystemName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.headline)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(VoiceInkIOSKeyboardSetupPresentation.instructions, id: \.number) { step in
                HowItWorksStep(
                    number: step.number,
                    title: step.title,
                    description: step.description
                )
            }

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            } label: {
                Label(
                    VoiceInkIOSKeyboardSetupPresentation.openSettingsButtonTitle,
                    systemImage: VoiceInkIOSKeyboardSetupPresentation.openSettingsButtonSystemImageName
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var verificationField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(VoiceInkIOSKeyboardSetupPresentation.testFieldTitle)
                .font(.headline)

            TextField(
                VoiceInkIOSKeyboardSetupPresentation.testFieldPlaceholder,
                text: $testText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .accessibilityIdentifier("keyboardSetupVerificationField")

            Text(VoiceInkIOSKeyboardSetupPresentation.testFieldHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingActions(continueAction: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(
                VoiceInkIOSKeyboardSetupPresentation.continueButtonTitle,
                action: continueAction
            )
            .buttonStyle(OnboardingButtonStyle())
            .disabled(readiness != .ready)

            if let skipAction {
                Button(
                    VoiceInkIOSKeyboardSetupPresentation.skipButtonTitle,
                    action: skipAction
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var statusColor: Color {
        switch readiness {
        case .unverified:
            return .secondary
        case .fullAccessRequired:
            return .orange
        case .ready:
            return .green
        }
    }

    private func beginVerification() {
        verificationStartedAt = Date()
        readiness = .unverified
        coordinator.onKeyboardReadinessReported = { observation in
            readiness = VoiceInkIOSKeyboardReadinessPolicy.status(
                observation: observation,
                verificationStartedAt: verificationStartedAt
            )
        }
    }
}

#Preview("Keyboard Setup") {
    NavigationStack {
        KeyboardSetupView()
    }
}
