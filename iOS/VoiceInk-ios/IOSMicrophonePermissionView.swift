import AVFoundation
import Combine
import SwiftUI
import UIKit
import VoiceInkCore

enum IOSMicrophonePermissionAdapter {
    static func currentStatus() -> VoiceInkRecordingPermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func openSettings() {
        VoiceInkRecordingPermissionPolicy.settingsOpenPlan(
            settingsURL: URL(string: UIApplication.openSettingsURLString),
            canOpenURL: UIApplication.shared.canOpenURL
        ).applyRuntimeState { url in
            UIApplication.shared.open(url)
        }
    }
}

@MainActor
final class IOSMicrophonePermissionModel: ObservableObject {
    @Published private(set) var status: VoiceInkRecordingPermissionStatus

    private let statusProvider: () -> VoiceInkRecordingPermissionStatus
    private let requestAccess: (@escaping (Bool) -> Void) -> Void
    private let openSettings: () -> Void

    init(
        statusProvider: @escaping () -> VoiceInkRecordingPermissionStatus,
        requestAccess: @escaping (@escaping (Bool) -> Void) -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.statusProvider = statusProvider
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        self.status = statusProvider()
    }

    static func live() -> IOSMicrophonePermissionModel {
        IOSMicrophonePermissionModel(
            statusProvider: IOSMicrophonePermissionAdapter.currentStatus,
            requestAccess: IOSMicrophonePermissionAdapter.requestAccess,
            openSettings: IOSMicrophonePermissionAdapter.openSettings
        )
    }

    func refresh() {
        status = statusProvider()
    }

    func performRecoveryAction() {
        switch VoiceInkIOSMicrophonePermissionPresentation.status(status).recoveryAction {
        case .requestAccess:
            requestAccess { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        case .openSettings:
            openSettings()
        case .none:
            return
        }
    }
}

@MainActor
struct IOSMicrophonePermissionOnboardingView: View {
    @Binding var currentStep: VoiceInkIOSOnboardingStep

    var body: some View {
        IOSMicrophonePermissionView(
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

@MainActor
struct IOSMicrophonePermissionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: IOSMicrophonePermissionModel

    private let continueAction: (() -> Void)?
    private let skipAction: (() -> Void)?

    init(
        continueAction: (() -> Void)? = nil,
        skipAction: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: .live())
        self.continueAction = continueAction
        self.skipAction = skipAction
    }

    init(
        model: IOSMicrophonePermissionModel,
        continueAction: (() -> Void)? = nil,
        skipAction: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: model)
        self.continueAction = continueAction
        self.skipAction = skipAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                statusCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, continueAction == nil ? 32 : 132)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(VoiceInkIOSMicrophonePermissionPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            model.refresh()
        }
        .safeAreaInset(edge: .bottom) {
            actions
        }
        .onAppear {
            model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: VoiceInkIOSMicrophonePermissionPresentation.settingsRowSystemImageName)
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text(VoiceInkIOSMicrophonePermissionPresentation.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(VoiceInkIOSMicrophonePermissionPresentation.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusCard: some View {
        let presentation = VoiceInkIOSMicrophonePermissionPresentation.status(model.status)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: presentation.iconSystemName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if model.status == .granted, let continueAction {
                Button(
                    VoiceInkIOSMicrophonePermissionPresentation.continueButtonTitle,
                    action: continueAction
                )
                .buttonStyle(OnboardingButtonStyle())
            } else if let recoveryTitle = VoiceInkIOSMicrophonePermissionPresentation
                .status(model.status).recoveryButtonTitle {
                if continueAction == nil {
                    Button(recoveryTitle) {
                        model.performRecoveryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(recoveryTitle) {
                        model.performRecoveryAction()
                    }
                    .buttonStyle(OnboardingButtonStyle())
                }
            } else if continueAction == nil {
                Button(VoiceInkIOSMicrophonePermissionPresentation.refreshButtonTitle) {
                    model.refresh()
                }
                .buttonStyle(.borderedProminent)
            }

            if let skipAction {
                Button(
                    VoiceInkIOSMicrophonePermissionPresentation.skipButtonTitle,
                    action: skipAction
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var statusColor: Color {
        switch model.status {
        case .granted:
            return .green
        case .denied:
            return .orange
        case .undetermined:
            return .secondary
        }
    }
}

#Preview("Microphone Permission") {
    NavigationStack {
        IOSMicrophonePermissionView()
    }
}
