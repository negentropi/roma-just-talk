//
//  VoiceInk_iosApp.swift
//  VoiceInk-ios
//
//  Created by Prakash Joshi on 12/08/2025.
//

import SwiftUI
import SwiftData

@main
struct VoiceInk_iosApp: App {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var shouldStartRecordingAfterOnboarding = false
    @StateObject private var recordingManager = RecordingManager()
    
    init() {
        // Clear any stale recording state on app launch
        AppGroupCoordinator.shared.updateRecordingState(false)
        print("🧹 Cleared stale recording state on app launch")
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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(recordingManager)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onAppear {
                        startPendingRecordingIfNeeded()
                    }
            } else {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onChange(of: hasCompletedOnboarding) { _, completed in
                        if completed {
                            startPendingRecordingIfNeeded()
                        }
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleURL(_ url: URL) {
        guard let deepLink = VoiceInkAppDeepLink(url: url) else { return }

        switch deepLink {
        case .record:
            print("🔗 URL scheme triggered: open app for recording")
            requestRecordingFromDeepLink()
            print("📱 App opened via keyboard extension - recording requested")
        }
    }

    private func requestRecordingFromDeepLink() {
        guard hasCompletedOnboarding else {
            shouldStartRecordingAfterOnboarding = true
            return
        }

        startRecordingAfterLaunchDelay()
    }

    private func startPendingRecordingIfNeeded() {
        guard shouldStartRecordingAfterOnboarding else { return }
        shouldStartRecordingAfterOnboarding = false
        startRecordingAfterLaunchDelay()
    }

    private func startRecordingAfterLaunchDelay() {
        // Allow the opened scene to settle before presenting recording permission/UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.recordingManager.startRecordingFlow()
        }
    }
}
