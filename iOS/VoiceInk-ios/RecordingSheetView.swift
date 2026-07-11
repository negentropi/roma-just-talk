import SwiftUI
import VoiceInkCore

struct RecordingSheetView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var settings: AppSettings
    let onCancel: () -> Void
    let onStop: () -> Void
    private let recordingSheetPresentation = VoiceInkRecordingSheetPresentation.iOS
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Button(recordingSheetPresentation.cancelButtonTitle, action: onCancel)
                    .font(.body)
                Spacer()
                Text(VoiceInkDurationPresentation.minutesSeconds(
                    recordingManager.flowState.currentDuration,
                    padMinutesToTwoDigits: true
                ))
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .padding(.top, 8)

            AudioVisualizerView(levels: recordingManager.currentAudioLevels)
                .padding(.vertical, 4)

            VoiceInkModeSelectionControlView(
                modes: settings.modes,
                selectedModeId: $settings.selectedModeId,
                showsTitle: true
            )

            if settings.modes.activeMode(selectedModeId: settings.selectedModeId)?.isPostProcessingEnabled == true {
                Picker(
                    "Prompt",
                    selection: Binding(
                        get: { settings.recordingPromptOverrideId },
                        set: { recordingManager.selectPromptForActiveRecording($0) }
                    )
                ) {
                    Text("Mode Prompt").tag(nil as UUID?)
                    ForEach(settings.customPrompts) { prompt in
                        Text(prompt.title).tag(prompt.id as UUID?)
                    }
                }
            }

            if !recordingManager.livePartialTranscript.isEmpty {
                Text(recordingManager.livePartialTranscript)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let fallback = recordingManager.liveTranscriptionFallbackMessage {
                Text(fallback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Stop Button - Matching main button style
            Button(action: onStop) {
                Label(
                    recordingSheetPresentation.stopButtonTitle,
                    systemImage: recordingSheetPresentation.stopButtonSystemImageName
                )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
}

extension VoiceInkRecordingAlertPresentation {
    func iOSAlert(openSettings: @escaping () -> Void) -> Alert {
        let primaryAction = runtimeAction(openSettings: openSettings)
        if let secondaryButtonTitle {
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .default(Text(primaryButtonTitle), action: primaryAction),
                secondaryButton: .cancel(Text(secondaryButtonTitle))
            )
        }

        return Alert(
            title: Text(title),
            message: Text(message),
            dismissButton: .default(Text(primaryButtonTitle), action: primaryAction)
        )
    }
}

#Preview {
    RecordingSheetView(
        recordingManager: RecordingManager(),
        settings: AppSettings.shared,
        onCancel: {},
        onStop: {}
    )
}

struct VoiceInkModeSelectionControlView: View {
    let modes: [Mode]
    @Binding var selectedModeId: UUID?
    var showsTitle = false

    var body: some View {
        let presentation = modes.modeSelectionPresentation

        if presentation.shouldShowControl {
            VStack(spacing: 8) {
                if showsTitle {
                    Text(VoiceInkModeSelectionPresentation.controlTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                selectionControl(for: presentation)
            }
        }
    }

    @ViewBuilder
    private func selectionControl(for presentation: VoiceInkModeSelectionPresentation) -> some View {
        if presentation.shouldShowPicker {
            Picker(VoiceInkModeSelectionPresentation.controlTitle, selection: $selectedModeId) {
                ForEach(modes) { mode in
                    Text(mode.name).tag(mode.id as UUID?)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 80)
        } else if let name = presentation.singleModeName {
            Text(name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
    }
}
