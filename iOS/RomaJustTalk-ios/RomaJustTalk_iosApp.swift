//
//  RomaJustTalk_iosApp.swift
//  RomaJustTalk-ios
//
//  Created by Prakash Joshi on 12/08/2025.
//

import SwiftUI
import SwiftData
import OSLog
import RomaCore

@main
struct RomaJustTalk_iosApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasCompletedOnboarding = RomaOnboardingPreference.hasCompletedOnboarding()
    @State private var launchRecordingRequestState = RomaLaunchRecordingRequestState()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var modelPrewarmService = IOSModelPrewarmService.shared
    
    init() {
        RomaDefaultSettings.iOS.registerUserDefaults()
        UserDefaults.standard.register(
            defaults: RomaPlatformAudioInputPolicy.registeredDefaults(for: .iOS)
        )
        RomaStartupPreferenceMigration.migrateLegacyPreferences(for: .iOS)

        // Clear any stale recording state on app launch
        AppGroupCoordinator.shared.updateRecordingState(false)
        RomaIOSLogger.app.notice("\(RomaIOSRecordingCoordinationDiagnostics.clearedStaleRecordingStateOnLaunchMessage, privacy: .public)")
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
            fatalError(RomaStorageStartupDiagnostics.iOSModelContainerCreationFailedMessage(
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
        if url.isFileURL, RomaSupportedMedia.isSupported(url: url) {
            Task {
                await IOSAudioImportManager.shared.add(urls: [url])
            }
            return
        }

        guard let deepLink = RomaAppDeepLink(url: url) else { return }

        deepLink.applyRuntimeState {
            RomaIOSLogger.app.notice("\(RomaIOSRecordingCoordinationDiagnostics.recordDeepLinkOpenedMessage, privacy: .public)")
            recordingManager.prepareKeyboardDictationRequest()
            launchRecordingRequestState.requestRecording(
                hasCompletedOnboarding: hasCompletedOnboarding
            ).applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
            RomaIOSLogger.app.notice("\(RomaIOSRecordingCoordinationDiagnostics.keyboardRecordingRequestOpenedMessage, privacy: .public)")
        }
    }

    private func startRecordingAfterLaunchDelay() {
        // Allow the opened scene to settle before presenting recording permission/UI.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RomaKeyboardRecordingTiming.appLaunchRecordingStartDelay
        ) {
            self.recordingManager.startRecordingFlow()
        }
    }
}
