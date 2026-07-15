//
//  VoiceInk_iosApp.swift
//  VoiceInk-ios
//
//  Created by Prakash Joshi on 12/08/2025.
//

import SwiftUI
import SwiftData
import OSLog
import VoiceInkCore

@main
struct VoiceInk_iosApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasCompletedOnboarding = VoiceInkOnboardingPreference.hasCompletedOnboarding()
    @State private var launchRecordingRequestState = VoiceInkLaunchRecordingRequestState()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var modelPrewarmService = IOSModelPrewarmService.shared
    @StateObject private var announcementsStore = IOSAnnouncementsStore.shared
    @AppStorage(VoiceInkAnnouncementPreference.isEnabledKey)
    private var announcementsEnabled = VoiceInkAnnouncementPreference.defaultIsEnabled
    
    init() {
        VoiceInkDefaultSettings.iOS.registerUserDefaults()
        UserDefaults.standard.register(
            defaults: VoiceInkPlatformAudioInputPolicy.registeredDefaults(for: .iOS)
        )
        UserDefaults.standard.register(defaults: VoiceInkAnnouncementPreference.registeredDefaults)
        VoiceInkStartupPreferenceMigration.migrateLegacyPreferences(for: .iOS)

        // Clear any stale recording state on app launch
        AppGroupCoordinator.shared.updateRecordingState(false)
        VoiceInkIOSLogger.app.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.clearedStaleRecordingStateOnLaunchMessage, privacy: .public)")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError(VoiceInkStorageStartupDiagnostics.iOSModelContainerCreationFailedMessage(
                errorDescription: String(describing: error)
            ))
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    NotesListView()
                    .environmentObject(recordingManager)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onAppear {
                        recordingManager.preparePreRollIfPermitted()
                        launchRecordingRequestState.consumePendingRecordingIfReady(
                            hasCompletedOnboarding: hasCompletedOnboarding
                        ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
                    }
                } else {
                    OnboardingView(
                        isOnboardingComplete: $hasCompletedOnboarding,
                        recordingManager: recordingManager
                    )
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onChange(of: hasCompletedOnboarding) { _, completed in
                        if completed {
                            recordingManager.preparePreRollIfPermitted()
                            launchRecordingRequestState.consumePendingRecordingIfReady(
                                hasCompletedOnboarding: hasCompletedOnboarding
                            ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if hasCompletedOnboarding,
                   let announcement = announcementsStore.currentAnnouncement {
                    IOSAnnouncementBannerView(
                        presentation: announcement,
                        onDismiss: announcementsStore.dismissCurrentAnnouncement
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .task {
                if announcementsEnabled {
                    announcementsStore.start()
                }
            }
            .onChange(of: announcementsEnabled) { _, enabled in
                announcementsStore.setEnabled(enabled)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if hasCompletedOnboarding {
                        recordingManager.preparePreRollIfPermitted()
                    }
                case .inactive, .background:
                    recordingManager.suspendPreRollIfIdle()
                @unknown default:
                    break
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleURL(_ url: URL) {
        if url.isFileURL, VoiceInkSupportedMedia.isSupported(url: url) {
            Task {
                await IOSAudioImportManager.shared.add(urls: [url])
            }
            return
        }

        guard let deepLink = VoiceInkAppDeepLink(url: url) else { return }

        deepLink.applyRuntimeState {
            VoiceInkIOSLogger.app.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.recordDeepLinkOpenedMessage, privacy: .public)")
            recordingManager.prepareKeyboardDictationRequest()
            launchRecordingRequestState.requestRecording(
                hasCompletedOnboarding: hasCompletedOnboarding
            ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
            VoiceInkIOSLogger.app.notice("\(VoiceInkIOSRecordingCoordinationDiagnostics.keyboardRecordingRequestOpenedMessage, privacy: .public)")
        }
    }

    private func startRecordingAfterLaunchDelay() {
        // Allow the opened scene to settle before presenting recording permission/UI.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VoiceInkKeyboardRecordingTiming.appLaunchRecordingStartDelay
        ) {
            self.recordingManager.startRecordingFlow()
        }
    }
}
