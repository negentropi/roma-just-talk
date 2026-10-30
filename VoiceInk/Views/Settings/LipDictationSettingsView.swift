import AppKit
import SwiftUI
import VoiceInkCore

enum LipDictationReadiness: Equatable {
    case needsSetup
    case preparing
    case ready
    case cameraDenied
    case failed(message: String)
    case unavailable
}

struct LipDictationSettingsView: View {
    let readiness: LipDictationReadiness
    let downloadDescription: String
    let isCapturing: Bool
    // Must stay metadata-only: no model load, camera, or network.
    let refresh: @MainActor () async -> Void
    // Only the Set Up button calls this, so the recording shortcut never
    // triggers a download or camera permission prompt.
    let setUp: @MainActor () async -> Void

    @AppStorage(VoiceInkLipDictationPreference.enabledKey) private var isEnabled = false
    @AppStorage(VoiceInkLipDictationPreference.lipOnlyKey) private var isLipOnly = false
    @State private var isRunningSetup = false

    var body: some View {
        Section {
            Toggle(isOn: masterBinding) {
                Text("Read Lips While Dictating")
                Text(masterSubtitle)
            }
            .disabled(!canChangeMaster)

            statusRow

            if isEnabled {
                Toggle(isOn: $isLipOnly) {
                    Text("Lips Only")
                    Text("Turns the microphone off and uses only the camera.")
                }
                .disabled(isCapturing)
                .help(isCapturing ? "Can't be changed while recording." : "")
            }
        } header: {
            Text("Lip Dictation")
        } footer: {
            Text("Experimental. English only, best with short phrases, up to 60 seconds per recording. Face the camera in good light, with only you in view. Uses your usual recording shortcut; the camera is on only while you record.")
                .foregroundStyle(.secondary)
        }
        .animation(.default, value: isEnabled)
        .task { await refresh() }
        // Picks up camera access granted in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var masterSubtitle: String {
        switch (isEnabled, isLipOnly) {
        case (true, true): "Reads your lips with the camera. The microphone stays off."
        case (true, false): "Records your voice and the camera. Lip reading is used when no speech is heard."
        case (false, _): "Use the camera to dictate by reading your lips."
        }
    }

    // Turning on needs a working setup and no recording in flight. Turning off
    // is always allowed: it's how a user leaves a broken setup or cancels lip
    // capture mid-recording.
    private var canChangeMaster: Bool {
        isEnabled || (readiness == .ready && !isCapturing)
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard !newValue || canChangeMaster else { return }
                isEnabled = newValue
            }
        )
    }

    @ViewBuilder
    private var statusRow: some View {
        switch readiness {
        case .needsSetup:
            LabeledContent {
                setUpButton("Set Up…")
            } label: {
                statusLabel("Setup required", systemImage: "arrow.down.circle", tint: .secondary)
                Text(setupDetail)
            }
        case .preparing:
            LabeledContent {
                ProgressView().controlSize(.small)
            } label: {
                statusLabel("Setting up…", systemImage: "hourglass", tint: .secondary)
                if !downloadDescription.isEmpty {
                    Text(downloadDescription)
                }
            }
        case .ready:
            LabeledContent {
                EmptyView()
            } label: {
                statusLabel("Ready", systemImage: "checkmark.circle.fill", tint: .green)
            }
        case .cameraDenied:
            LabeledContent {
                Button("Open System Settings…", action: openCameraPrivacySettings)
            } label: {
                statusLabel("Camera access is off", systemImage: "video.slash", tint: .orange)
                Text("Allow camera access in Privacy & Security to use lip dictation.")
            }
        case .failed(let message):
            LabeledContent {
                setUpButton("Try Again")
            } label: {
                statusLabel("Couldn't set up", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                Text(message)
            }
        case .unavailable:
            LabeledContent {
                EmptyView()
            } label: {
                statusLabel("Not available yet", systemImage: "clock", tint: .secondary)
                Text("Lip dictation isn't available in this version.")
            }
        }
    }

    private var setupDetail: String {
        downloadDescription.isEmpty
            ? "Downloads lip reading and asks for camera access."
            : "\(downloadDescription) Asks for camera access."
    }

    private func statusLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }

    private func setUpButton(_ title: String) -> some View {
        Button(title) {
            isRunningSetup = true
            Task {
                await setUp()
                isRunningSetup = false
            }
        }
        // Blocks a second click before the parent reports .preparing.
        .disabled(isRunningSetup)
    }

    private func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}

// Each preview gets its own throwaway suite so toggling never touches the
// app's real preferences or another preview's state.
private func lipDictationPreviewDefaults(_ name: String, isEnabled: Bool, isLipOnly: Bool) -> UserDefaults {
    let suiteName = "LipDictationSettingsPreview.\(name)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    VoiceInkLipDictationPreference.saveIsEnabled(isEnabled, to: defaults)
    VoiceInkLipDictationPreference.saveLipOnly(isLipOnly, to: defaults)
    return defaults
}

private func lipDictationPreview(
    _ name: String,
    readiness: LipDictationReadiness,
    isEnabled: Bool = false,
    isLipOnly: Bool = false,
    isCapturing: Bool = false
) -> some View {
    Form {
        LipDictationSettingsView(
            readiness: readiness,
            downloadDescription: "Downloads 1.98 GB. Uses 1.36 GB on this Mac.",
            isCapturing: isCapturing,
            refresh: {},
            setUp: {}
        )
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .defaultAppStorage(lipDictationPreviewDefaults(name, isEnabled: isEnabled, isLipOnly: isLipOnly))
}

#Preview("Needs Setup") {
    lipDictationPreview("needsSetup", readiness: .needsSetup)
}

#Preview("Ready, Voice + Lips") {
    lipDictationPreview("readyVoiceAndLips", readiness: .ready, isEnabled: true)
}

#Preview("Ready, Lips Only, Recording") {
    lipDictationPreview("readyLipsOnly", readiness: .ready, isEnabled: true, isLipOnly: true, isCapturing: true)
}

#Preview("Failed While Enabled") {
    lipDictationPreview("failed", readiness: .failed(message: "The download was interrupted."), isEnabled: true)
}

#Preview("Unavailable") {
    lipDictationPreview("unavailable", readiness: .unavailable)
}
