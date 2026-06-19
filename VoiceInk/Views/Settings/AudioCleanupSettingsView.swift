import SwiftUI
import SwiftData
import VoiceInkCore

struct AudioCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private let presentation = VoiceInkMacOSCleanupSettingsPresentation.macOS

    // Audio cleanup settings
    @AppStorage(VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled) private var isTranscriptionCleanupEnabled = false
    @AppStorage(VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) private var transcriptionRetentionMinutes = VoiceInkPreferenceDefault.transcriptionRetentionMinutes
    @AppStorage(VoiceInkUserDefaultsKey.isAudioCleanupEnabled) private var isAudioCleanupEnabled = false
    @AppStorage(VoiceInkUserDefaultsKey.audioRetentionPeriodDays) private var audioRetentionPeriod = VoiceInkPreferenceDefault.audioRetentionDays
    @State private var isPerformingCleanup = false
    @State private var isShowingConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showResultAlert = false
    @State private var cleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showTranscriptCleanupResult = false

    // Expansion states - collapsed by default
    @State private var isTranscriptExpanded = false
    @State private var isAudioExpanded = false
    @State private var isHandlingTranscriptToggle = false
    @State private var isHandlingAudioToggle = false

    var body: some View {
        Group {
            // Transcript cleanup - hierarchical
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Toggle(isOn: $isTranscriptionCleanupEnabled) {
                        HStack(spacing: 4) {
                            Text(presentation.transcriptToggleTitle)
                            InfoTip(presentation.transcriptHelpText)
                        }
                    }

                    Spacer()

                    Image(systemName: presentation.disclosureSystemImageName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isTranscriptionCleanupEnabled && isTranscriptExpanded ? 90 : 0))
                        .opacity(isTranscriptionCleanupEnabled ? 1 : 0.4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isHandlingTranscriptToggle else { return }
                    if isTranscriptionCleanupEnabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTranscriptExpanded.toggle()
                        }
                    }
                }

                if isTranscriptionCleanupEnabled && isTranscriptExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(presentation.transcriptRetentionPickerTitle, selection: $transcriptionRetentionMinutes) {
                            ForEach(presentation.transcriptRetentionOptions) { option in
                                Text(option.title).tag(option.value)
                            }
                        }

                        Button(presentation.manualCleanupButtonTitle) {
                            Task {
                                await TranscriptionAutoCleanupService.shared.runManualCleanup(modelContext: modelContext)
                                await MainActor.run {
                                    showTranscriptCleanupResult = true
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isTranscriptExpanded)
            .alert(presentation.transcriptCleanupAlertTitle, isPresented: $showTranscriptCleanupResult) {
                Button(presentation.okButtonTitle, role: .cancel) { }
            } message: {
                Text(presentation.transcriptCleanupCompleteMessage)
            }
            .onChange(of: isTranscriptionCleanupEnabled) { _, newValue in
                isHandlingTranscriptToggle = true
                if newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTranscriptExpanded = true
                    }
                    AudioCleanupManager.shared.stopAutomaticCleanup()
                } else {
                    isTranscriptExpanded = false
                    if isAudioCleanupEnabled {
                        AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isHandlingTranscriptToggle = false
                }
            }

            // Audio cleanup - only show if transcript cleanup is disabled
            if !isTranscriptionCleanupEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Toggle(isOn: $isAudioCleanupEnabled) {
                            HStack(spacing: 4) {
                                Text(presentation.audioToggleTitle)
                                InfoTip(presentation.audioHelpText)
                            }
                        }

                        Spacer()

                        Image(systemName: presentation.disclosureSystemImageName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isAudioCleanupEnabled && isAudioExpanded ? 90 : 0))
                            .opacity(isAudioCleanupEnabled ? 1 : 0.4)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isHandlingAudioToggle else { return }
                        if isAudioCleanupEnabled {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAudioExpanded.toggle()
                            }
                        }
                    }

                    if isAudioCleanupEnabled && isAudioExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(presentation.audioRetentionPickerTitle, selection: $audioRetentionPeriod) {
                                ForEach(presentation.audioRetentionOptions) { option in
                                    Text(option.title).tag(option.value)
                                }
                            }

                            Button(presentation.audioCleanupButtonTitle(isAnalyzing: isPerformingCleanup)) {
                                Task {
                                    await MainActor.run { isPerformingCleanup = true }
                                    let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
                                    await MainActor.run {
                                        cleanupInfo = info
                                        isPerformingCleanup = false
                                        isShowingConfirmation = true
                                    }
                                }
                            }
                            .disabled(isPerformingCleanup)
                        }
                        .padding(.top, 12)
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isAudioExpanded)
                .alert(presentation.audioCleanupAlertTitle, isPresented: $isShowingConfirmation) {
                    Button(presentation.cancelButtonTitle, role: .cancel) { }

                    if cleanupInfo.fileCount > 0 {
                        Button(presentation.deleteFilesButtonTitle(fileCount: cleanupInfo.fileCount), role: .destructive) {
                            Task {
                                await MainActor.run { isPerformingCleanup = true }
                                let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                                    modelContext: modelContext,
                                    transcriptions: cleanupInfo.transcriptions
                                )
                                await MainActor.run {
                                    cleanupResult = result
                                    isPerformingCleanup = false
                                    showResultAlert = true
                                }
                            }
                        }
                    }
                } message: {
                    if cleanupInfo.fileCount > 0 {
                        Text(
                            presentation.audioCleanupConfirmationMessage(
                                fileCount: cleanupInfo.fileCount,
                                totalSizeText: AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize)
                            )
                        )
                    } else {
                        Text(presentation.noAudioFilesMessage(retentionDays: audioRetentionPeriod))
                    }
                }
                .alert(presentation.cleanupCompleteAlertTitle, isPresented: $showResultAlert) {
                    Button(presentation.okButtonTitle, role: .cancel) { }
                } message: {
                    Text(
                        presentation.audioCleanupResultMessage(
                            deletedCount: cleanupResult.deletedCount,
                            errorCount: cleanupResult.errorCount
                        )
                    )
                }
                .onChange(of: isAudioCleanupEnabled) { _, newValue in
                    isHandlingAudioToggle = true
                    if newValue {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAudioExpanded = true
                        }
                    } else {
                        isAudioExpanded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isHandlingAudioToggle = false
                    }
                }
            }
        }
    }
}
