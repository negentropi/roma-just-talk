# Integrating Keyboard Kit with VoiceInk for Recording

This document outlines the steps to integrate Keyboard Kit into the VoiceInk application to allow users to trigger a recording in the main app directly from the keyboard.

## Phase 1: Project Setup and Configuration

- [x] **Create an App Group for Data Sharing:**
    - In Xcode, open your project settings by selecting the `VoiceInk-ios` project in the Project Navigator.
    - Go to the `Signing & Capabilities` tab for the `VoiceInk-ios` target.
    - Click the `+ Capability` button and add `App Groups`.
    - In the App Groups section, click the `+` button to create a new group. The name should be something like `group.com.yourcompany.voiceink`. Make sure to note this name down.

- [x] **Create a New Keyboard Extension Target:**
    - In Xcode, go to `File` > `New` > `Target...`.
    - Select `Custom Keyboard Extension` from the `iOS` tab and click `Next`.
    - Give your extension a name (e.g., `VoiceInkKeyboard`) and make sure the `Project` and `Embed in Application` are set to your main app.
    - Click `Finish`. Xcode will ask if you want to activate the new scheme; click `Activate`.

- [x] **Configure the Keyboard Extension:**
    - A new folder for your keyboard extension will be created. Select the new target (e.g., `VoiceInkKeyboard`).
    - Go to its `Signing & Capabilities` tab.
    - Add the `App Groups` capability, just like you did for the main app.
    - Select the same App Group you created earlier.

- [x] **Add Keyboard Kit Dependency:**
    - Go to `File` > `Add Packages...`.
    - In the search bar, paste this URL: `https://github.com/KeyboardKit/KeyboardKit.git`.
    - Select the `KeyboardKit` package, and for the `Add to Target` dropdown, make sure you select your new keyboard extension target (`VoiceInkKeyboard`).
    - Click `Add Package`.

## Phase 2: Building the Keyboard and Communication

- [x] **Request Full Access for the Keyboard:**
    - In the project navigator, find the `Info.plist` file inside your keyboard extension's folder.
    - Right-click and choose `Open As` > `Source Code`.
    - Inside the `NSExtension` dictionary, add the following key-value pair to request open access, which is necessary for the keyboard to interact with the App Group.
        ```xml
        <key>RequestsOpenAccess</key>
        <true/>
        ```
- [x] **Design the Keyboard with a Record Button:**
    - In `KeyboardViewController.swift`, use Keyboard Kit to create a custom layout that includes a "Record" button.
    - ✅ **COMPLETED**: Red capsule-shaped record button implemented with proper styling, constraints, and haptic feedback. Button toggles between "🎤 Record" and "⏹️ Stop" states with visual feedback.

- [x] **Implement Keyboard-to-App Signaling:**
    - Create shared iOS shell files to manage keyboard/app communication.
    - Start requests use `iOS/Shared/VoiceInkAppDeepLink.swift`; the keyboard opens `voiceink://record` so the main app can own recording permissions and UI.
    - Stop requests and recording-state feedback use `iOS/Shared/AppGroupCoordinator.swift` with App Groups + Darwin Notifications.
    - ✅ **COMPLETED**: `iOS/Shared/AppGroupCoordinator.swift` is wired into both the main app target and keyboard extension target.
    - ✅ **COMPLETED**: `iOS/Shared/VoiceInkAppDeepLink.swift` is wired through the same shared target group.
    - When the user taps the Record button, the keyboard will:
        1. Open `VoiceInkAppDeepLink.record`.
        2. Show Stop while `AppGroupCoordinator.isRecording` is true.

## Phase 3: Implementing Recording in the Main App

- [x] **Listen for Signals in the Main App:**
    - In your main app, likely within your `RecordingManager` or a similar central class, use the `AppGroupCoordinator` to:
        1. Register a Darwin notification observer for the stop-recording signal.
        2. When a Darwin notification is received, immediately check the corresponding flag in the shared `UserDefaults`.
    - Start requests are handled by `VoiceInk_iosApp` through `VoiceInkAppDeepLink.record`.

- [x] **Handle Recording Lifecycle:**
    - When the main app receives `VoiceInkAppDeepLink.record`, it starts the recording flow after launch. If onboarding is still active, the app preserves that request and starts after onboarding completes.
    - The keyboard Stop button:
        1. Sets a `shouldStopRecording` flag in shared `UserDefaults`.
        2. Posts a Darwin notification to immediately notify the main app to stop and save the recording.

- [x] **Provide User Feedback:**
    - The keyboard UI should update to indicate that a recording is in progress (e.g., the record button changes to a stop icon). This state can also be managed via a flag in the shared `UserDefaults` (e.g., `isRecording`). The keyboard will read this flag to update its UI.
