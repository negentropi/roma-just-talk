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
    @State private var hasCompletedOnboarding = VoiceInkOnboardingPreference.hasCompletedOnboarding()
    @State private var launchRecordingRequestState = VoiceInkLaunchRecordingRequestState()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var modelPrewarmService = IOSModelPrewarmService.shared
    
    init() {
        VoiceInkDefaultSettings.iOS.registerUserDefaults()
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
            if hasCompletedOnboarding {
                NotesListView()
                    .environmentObject(recordingManager)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onAppear {
                        launchRecordingRequestState.consumePendingRecordingIfReady(
                            hasCompletedOnboarding: hasCompletedOnboarding
                        ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
                    }
            } else {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onChange(of: hasCompletedOnboarding) { _, completed in
                        if completed {
                            launchRecordingRequestState.consumePendingRecordingIfReady(
                                hasCompletedOnboarding: hasCompletedOnboarding
                            ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
                        }
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
