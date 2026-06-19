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
                    recordingManager.currentDuration,
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

    private var presentation: VoiceInkModeSelectionPresentation {
        modes.modeSelectionPresentation
    }

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .picker, .singleModeName(_):
            VStack(spacing: 8) {
                if showsTitle {
                    Text(VoiceInkModeSelectionPresentation.controlTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                selectionControl
            }
        }
    }

    @ViewBuilder
    private var selectionControl: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .picker:
            Picker(VoiceInkModeSelectionPresentation.controlTitle, selection: $selectedModeId) {
                ForEach(modes) { mode in
                    Text(mode.name).tag(mode.id as UUID?)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 80)
        case .singleModeName(let name):
            Text(name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
    }
}
