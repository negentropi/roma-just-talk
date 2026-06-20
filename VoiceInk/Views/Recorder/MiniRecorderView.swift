import SwiftUI
import VoiceInkCore

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage(VoiceInkRecorderPreviewPreference.userDefaultsKey)
    private var showLiveTextPreview = VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled

    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactWidth: CGFloat = 184
    private let expandedWidth: CGFloat = 300
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14

    private var hasTranscriptPreview: Bool {
        showLiveTextPreview
            && stateProvider.recordingState.isActivelyRecording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            RecorderPromptButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.leading, 12)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter
            )

            Spacer(minLength: 0)

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasTranscriptPreview {
                TranscriptPreviewView(text: stateProvider.partialTranscript)
                Divider().background(Color.white.opacity(0.15))
            }
        }
    }

    var body: some View {
        if windowManager.isVisible {
            VStack(spacing: 0) {
                transcriptSection
                controlBar
            }
            .frame(width: hasTranscriptPreview ? expandedWidth : compactWidth)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: hasTranscriptPreview ? expandedCornerRadius : compactCornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.3), value: hasTranscriptPreview)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
