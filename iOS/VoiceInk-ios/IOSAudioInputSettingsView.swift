import SwiftUI
import VoiceInkCore

struct IOSAudioInputSettingsView: View {
    @ObservedObject private var audioSession = AudioSessionManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Follow System Audio Routing",
                    isOn: Binding(
                        get: { audioSession.inputMode == .systemDefault },
                        set: updateSystemRouting
                    )
                )
            } footer: {
                Text("On by default on iPhone. Turn it off to keep a preferred microphone when that input is available.")
            }

            if audioSession.inputMode == .custom {
                Section("Preferred Microphone") {
                    if audioSession.availableInputs.isEmpty {
                        Text("No microphone inputs are currently available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioSession.availableInputs) { input in
                            Button {
                                selectInput(input.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(input.name)
                                            .foregroundStyle(.primary)
                                        Text(input.kind)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedInputUID == input.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let currentInput = audioSession.availableInputs.first(where: {
                $0.id == audioSession.currentInputUID
            }) {
                Section("Current Input") {
                    Text(currentInput.name)
                }
            }

            if let message = audioSession.routeFallbackMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Audio Routing")
        .onAppear(perform: audioSession.refreshRouteState)
    }

    private var selectedInputUID: String? {
        VoiceInkAudioInputPreference.selectedDeviceUID()
    }

    private func updateSystemRouting(_ enabled: Bool) {
        audioSession.setUsesSystemManagedRouting(enabled)
    }

    private func selectInput(_ uid: String) {
        audioSession.selectInput(uid: uid)
    }
}
