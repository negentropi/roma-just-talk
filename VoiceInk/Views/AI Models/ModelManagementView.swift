import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import VoiceInkCore

struct ModelManagementView: View {
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var customModelToEdit: CustomCloudModel?
    @StateObject private var aiService = AIService()
    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: VoiceInkModelManagementFilter = .recommended
    @State private var isShowingSettings = false

    private let settingsPanelWidth: CGFloat = 400

    // State for the unified alert
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    private func closeSettings() {
        withAnimation(.smooth(duration: 0.3)) {
            isShowingSettings = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if SystemArchitecture.isIntelMac {
                    intelMacWarningBanner
                }

                defaultModelSection
                languageSelectionSection
                availableModelsSection
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: $isShowingSettings, width: settingsPanelWidth) {
            settingsPanelContent
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text(VoiceInkModelManagementPresentation.deleteButtonTitle), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private var settingsPanelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(VoiceInkModelManagementPresentation.settingsTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { closeSettings() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(VoiceInkModelManagementPresentation.closeButtonHelp)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            ModelSettingsView(whisperPrompt: whisperPrompt)
        }
    }
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VoiceInkModelManagementPresentation.defaultModelTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(transcriptionModelManager.currentTranscriptionModel?.displayName ?? VoiceInkModelManagementPresentation.noModelSelectedText)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false))
        .cornerRadius(10)
    }

    private var languageSelectionSection: some View {
        LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .full, whisperPrompt: whisperPrompt)
    }
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Modern compact pill switcher
                HStack(spacing: 12) {
                    ForEach(VoiceInkModelManagementFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedFilter = filter
                                isShowingSettings = false
                            }
                        }) {
                            Text(filter.title)
                                .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                                .foregroundColor(selectedFilter == filter ? .primary : .primary.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    CardBackground(isSelected: selectedFilter == filter, cornerRadius: 22)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .primary.opacity(0.7))
                        .padding(12)
                        .background(
                            CardBackground(isSelected: isShowingSettings, cornerRadius: 22)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 12)
            
            VStack(spacing: 12) {
                    ForEach(filteredModels, id: \.id) { model in
                        let downloadedLocalModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                            forModelName: model.name,
                            in: whisperModelManager.availableModels
                        )
                        let isWarming = (model as? WhisperModel).map { whisperModel in
                            warmupCoordinator.isWarming(modelNamed: whisperModel.name)
                        } ?? false

                        ModelCardView(
                            model: model,
                            fluidAudioModelManager: fluidAudioModelManager,
                            transcriptionModelManager: transcriptionModelManager,
                            isDownloaded: downloadedLocalModel != nil,
                            isCurrent: transcriptionModelManager.currentTranscriptionModel?.name == model.name,
                            downloadProgress: whisperModelManager.downloadProgress,
                            modelURL: downloadedLocalModel?.url,
                            isWarming: isWarming,
                            deleteAction: {
                                if let customModel = model as? CustomCloudModel {
                                    alertTitle = VoiceInkModelManagementPresentation.deleteCustomModelAlertTitle
                                    alertMessage = VoiceInkModelManagementPresentation.deleteCustomModelAlertMessage(displayName: customModel.displayName)
                                    deleteActionClosure = {
                                        customModelManager.removeCustomModel(withId: customModel.id)
                                        transcriptionModelManager.refreshAllAvailableModels()
                                    }
                                    isShowingDeleteAlert = true
                                } else if let downloadedModel = downloadedLocalModel {
                                    alertTitle = VoiceInkModelManagementPresentation.deleteModelButtonTitle
                                    alertMessage = VoiceInkModelManagementPresentation.deleteModelAlertMessage(modelName: downloadedModel.name)
                                    deleteActionClosure = {
                                        Task {
                                            await whisperModelManager.deleteModel(downloadedModel)
                                        }
                                    }
                                    isShowingDeleteAlert = true
                                }
                            },
                            setDefaultAction: {
                                Task {
                                    transcriptionModelManager.setDefaultTranscriptionModel(model)
                                }
                            },
                            downloadAction: {
                                if let whisperModel = model as? WhisperModel {
                                    Task { await whisperModelManager.downloadModel(whisperModel) }
                                }
                            },
                            editAction: modelManagementFacts(for: model).category == .custom ? { customModel in
                                customModelToEdit = customModel
                            } : nil
                        )
                    }
                    
                    // Import button as a card at the end of the Local list
                    if selectedFilter == .local {
                        HStack(spacing: 8) {
                            Button(action: { presentImportPanel() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text(VoiceInkModelManagementPresentation.importLocalModelTitle)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(CardBackground(isSelected: false))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            InfoTip(
                                VoiceInkModelManagementPresentation.importLocalModelHelpText,
                                learnMoreURL: VoiceInkModelManagementPresentation.importLocalModelLearnMoreURLString
                            )
                            .help(VoiceInkModelManagementPresentation.importLocalModelLearnMoreHelpText)
                        }
                    }
                    
                    if selectedFilter == .custom {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                            Text(VoiceInkModelManagementPresentation.customModelsLimitationText)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                        AddCustomModelCardView(
                            customModelManager: customModelManager,
                            editingModel: customModelToEdit
                        ) {
                            // Refresh the models when a new custom model is added
                            transcriptionModelManager.refreshAllAvailableModels()
                            customModelToEdit = nil // Clear editing state
                        }
                    }
                }
            }
        .padding()
    }



    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text(VoiceInkModelManagementPresentation.intelMacLocalModelsWarningText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text(VoiceInkModelManagementPresentation.intelMacUseCloudButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var filteredModels: [any TranscriptionModel] {
        let models = transcriptionModelManager.allAvailableModels.filter {
            selectedFilter.includes(modelManagementFacts(for: $0))
        }

        guard selectedFilter == .recommended else {
            return models
        }

        return models.sorted {
            selectedFilter.sortRank(forModelName: $0.name) < selectedFilter.sortRank(forModelName: $1.name)
        }
    }

    private func modelManagementFacts(for model: any TranscriptionModel) -> VoiceInkModelManagementModelFacts {
        model.modelManagementFacts(
            isAvailableOnCurrentOS: transcriptionModelManager.isAvailableOnCurrentOS(model)
        )
    }

    // MARK: - Import Panel
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: VoiceInkWhisperModelFiles.modelFileExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = VoiceInkModelManagementPresentation.importLocalModelPanelTitle
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }
}
