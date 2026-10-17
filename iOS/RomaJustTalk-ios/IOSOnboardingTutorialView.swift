import SwiftData
import SwiftUI
import RomaCore

struct IOSOnboardingTutorialView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var currentStep: RomaIOSOnboardingStep
    @ObservedObject var recordingManager: RecordingManager
    @State private var state = RomaIOSOnboardingTutorialState.ready
    private let settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                instructions
                resultCard
                recordingAction
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 132)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            onboardingActions
        }
        .sheet(
            isPresented: Binding(
                get: { recordingManager.flowState.isRecordingSheetPresented },
                set: { recordingManager.setRecordingSheetPresented($0) }
            )
        ) {
            RecordingSheetView(
                recordingManager: recordingManager,
                settings: settings,
                onCancel: cancelRecording,
                onStop: stopRecording
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .interactiveDismissDisabled(true)
        }
        .alert(item: $recordingManager.activeRecordingAlert) { presentation in
            presentation.iOSAlert(openSettings: recordingManager.openSettings)
        }
        .onDisappear {
            if recordingManager.flowState.recordingState.isRecorderCaptureInProgress {
                recordingManager.cancelRecording()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: RomaIOSOnboardingTutorialPresentation.iconSystemName)
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text(RomaIOSOnboardingTutorialPresentation.title)
                .font(.largeTitle.bold())

            Text(RomaIOSOnboardingTutorialPresentation.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(RomaIOSOnboardingTutorialPresentation.instructionSteps, id: \.number) { step in
                HowItWorksStep(
                    number: step.number,
                    title: step.title,
                    description: step.description
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultCard: some View {
        VStack(spacing: 12) {
            switch state {
            case .ready:
                status(
                    icon: "mic.circle",
                    title: RomaIOSOnboardingTutorialPresentation.readyTitle,
                    detail: RomaIOSOnboardingTutorialPresentation.readyDetail,
                    color: .accentColor
                )
            case .processing:
                ProgressView()
                Text(RomaIOSOnboardingTutorialPresentation.processingTitle)
                    .font(.headline)
                Text(RomaIOSOnboardingTutorialPresentation.processingDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .succeeded(let text):
                status(
                    icon: "checkmark.circle.fill",
                    title: RomaIOSOnboardingTutorialPresentation.successTitle,
                    detail: text,
                    color: .green
                )
            case .failed(let reason):
                status(
                    icon: "exclamationmark.triangle.fill",
                    title: RomaIOSOnboardingTutorialPresentation.failureTitle,
                    detail: reason,
                    color: .orange
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var recordingAction: some View {
        Button(action: startRecording) {
            Label(
                state.canComplete
                    ? RomaIOSOnboardingTutorialPresentation.retryButtonTitle
                    : RomaIOSOnboardingTutorialPresentation.startButtonTitle,
                systemImage: "mic.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(state == .processing || recordingManager.flowState.recordingState.isRecorderCaptureInProgress)
    }

    private var onboardingActions: some View {
        VStack(spacing: 10) {
            Button(RomaIOSOnboardingTutorialPresentation.continueButtonTitle) {
                advance()
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(!state.canComplete)

            Button(RomaIOSOnboardingTutorialPresentation.skipButtonTitle) {
                advance()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func status(
        icon: String,
        title: String,
        detail: String,
        color: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
    }

    private func startRecording() {
        state = .ready
        recordingManager.startRecordingFlow()
    }

    private func cancelRecording() {
        recordingManager.cancelRecording()
        state = .ready
    }

    private func stopRecording() {
        state = .processing
        recordingManager.stopRecording(modelContext: modelContext) { outcome in
            state = .completed(with: outcome)
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep.advance()
        }
    }
}

#Preview {
    IOSOnboardingTutorialView(
        currentStep: .constant(.tutorial),
        recordingManager: RecordingManager()
    )
    .modelContainer(for: Transcription.self, inMemory: true)
}
