import SwiftUI
import RomaCore

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var engine: RomaEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var whisperModelManager: WhisperModelManager
    @EnvironmentObject var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @State private var menuRefreshTrigger = false
    @State private var isHovered = false
    @AppStorage(RomaMenuBarPreference.showMenuBarIconKey) private var showMenuBarIcon = RomaMenuBarPreference.defaultShowMenuBarIcon
    
    var body: some View {
        VStack {
            Button(RomaMacOSMenuBarPresentation.toggleRecorderTitle) {
                recorderUIManager.handleToggleMiniRecorder()
            }

            Divider()

            Menu {
                ForEach(transcriptionModelManager.usableModels, id: \.id) { model in
                    Button {
                        Task {
                            transcriptionModelManager.setDefaultTranscriptionModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if transcriptionModelManager.currentTranscriptionModel?.id == model.id {
                                Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                Divider()

                Button(RomaMacOSMenuBarPresentation.manageModelsTitle) {
                    openMainWindowAndNavigate(to: RomaMacOSNavigationDestination.aiModels.rawValue)
                }
            } label: {
                HStack {
                    Text(RomaMacOSMenuBarPresentation.transcriptionModelTitle(
                        currentDisplayName: transcriptionModelManager.currentTranscriptionModel?.displayName
                    ))
                    Image(systemName: RomaMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Divider()
            
            Toggle(RomaMacOSMenuBarPresentation.aiEnhancementToggleTitle, isOn: $enhancementService.isEnhancementEnabled)
            
            Menu {
                ForEach(enhancementService.allPrompts) { prompt in
                    Button {
                        enhancementService.setActivePrompt(prompt)
                    } label: {
                        HStack {
                            Image(systemName: prompt.icon)
                                .foregroundColor(.accentColor)
                            Text(prompt.title)
                            if enhancementService.selectedPromptId == prompt.id {
                                Spacer()
                                Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(RomaMacOSMenuBarPresentation.promptTitle(activePromptTitle: enhancementService.activePrompt?.title))
                    Image(systemName: RomaMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Menu {
                ForEach(aiService.connectedProviders, id: \.self) { provider in
                    Button {
                        aiService.selectedProvider = provider
                    } label: {
                        HStack {
                            Text(provider.rawValue)
                            if aiService.selectedProvider == provider {
                                Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if aiService.connectedProviders.isEmpty {
                    Text(RomaMacOSMenuBarPresentation.noProvidersConnectedText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(RomaMacOSMenuBarPresentation.aiProviderTitle(selectedProviderName: aiService.selectedProvider.rawValue))
                    Image(systemName: RomaMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Menu {
                ForEach(aiService.availableModels, id: \.self) { model in
                    Button {
                        aiService.selectModel(model)
                    } label: {
                        HStack {
                            Text(model)
                            if aiService.currentModel == model {
                                Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if aiService.availableModels.isEmpty {
                    Text(RomaMacOSMenuBarPresentation.noModelsAvailableText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(RomaMacOSMenuBarPresentation.aiModelTitle(currentModelName: aiService.currentModel))
                    Image(systemName: RomaMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .menuItem)

            Menu {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button {
                        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                    } label: {
                        HStack {
                            Text(device.name)
                            if audioDeviceManager.getCurrentDevice() == device.id {
                                Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if audioDeviceManager.availableDevices.isEmpty {
                    Text(RomaMacOSMenuBarPresentation.noDevicesAvailableText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(RomaMacOSMenuBarPresentation.audioInputTitle)
                    Image(systemName: RomaMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }

            Menu(RomaMacOSMenuBarPresentation.additionalMenuTitle) {
                Button {
                    enhancementService.useClipboardContext.toggle()
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text(RomaMacOSMenuBarPresentation.clipboardContextTitle)
                        Spacer()
                        if enhancementService.useClipboardContext {
                            Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                        }
                    }
                }

                Button {
                    enhancementService.useScreenCaptureContext.toggle()
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text(RomaMacOSMenuBarPresentation.contextAwarenessTitle)
                        Spacer()
                        if enhancementService.useScreenCaptureContext {
                            Image(systemName: RomaMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                        }
                    }
                }
            }
            .id("additional-menu-\(menuRefreshTrigger)")
            
            Divider()

            Button(RomaMacOSMenuBarPresentation.retryLastTranscriptionTitle) {
                LastTranscriptionService.retryLastTranscription(
                    from: engine.modelContext,
                    transcriptionModelManager: transcriptionModelManager,
                    serviceRegistry: engine.serviceRegistry,
                    enhancementService: enhancementService
                )
            }

            Button(RomaMacOSMenuBarPresentation.copyLastTranscriptionTitle) {
                LastTranscriptionService.copyLastTranscription(from: engine.modelContext)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button(RomaMacOSMenuBarPresentation.historyTitle) {
                menuBarManager.openHistoryWindow()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button(RomaMacOSMenuBarPresentation.permissionsTitle) {
                openMainWindowAndNavigate(to: RomaMacOSNavigationDestination.permissions.rawValue)
            }
            
            Button(RomaMacOSMenuBarPresentation.settingsTitle) {
                openMainWindowAndNavigate(to: RomaMacOSNavigationDestination.settings.rawValue)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(RomaMacOSMenuBarPresentation.dockIconTitle(showDockIcon: menuBarManager.showDockIcon)) {
                menuBarManager.toggleDockIcon()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(RomaMacOSMenuBarPresentation.hideMenuBarIconTitle) {
                showMenuBarIcon = false
            }
            
            Toggle(
                RomaMacOSMenuBarPresentation.launchAtLoginTitle,
                isOn: $launchAtLoginController.isEnabled
            )
            
            Divider()
            
            Button(RomaMacOSMenuBarPresentation.checkForUpdatesTitle) {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
            
            Button(RomaMacOSMenuBarPresentation.helpAndSupportTitle) {
                EmailSupport.openSupportEmail()
            }
            
            Divider()

            Button(RomaMacOSMenuBarPresentation.quitTitle) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func openMainWindowAndNavigate(to destination: String) {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = WindowManager.shared.showMainWindow()
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: RomaMacOSNavigationRequest.userInfo(destination: destination)
            )
        }
    }
}
