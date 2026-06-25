import SwiftUI
import VoiceInkCore

struct MetricsSetupView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @State private var isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    AppIconView()
                        .frame(width: 80, height: 80)
                        .padding(.bottom, 20)
                       
                    VStack(spacing: 4) {
                        Text(VoiceInkMacOSSetupPresentation.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        
                        Text(VoiceInkMacOSSetupPresentation.subtitle)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                // Setup Steps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(VoiceInkMacOSSetupPresentation.steps.enumerated()), id: \.element.id) { index, step in
                        setupStep(step)
                        if index < VoiceInkMacOSSetupPresentation.steps.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                
                Spacer(minLength: 20)
                
                // Action Button
                actionButton
                    .frame(maxWidth: 400)
                
                // Help Text
                helpText
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear(perform: refreshPermissionStates)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appPermissionsDidChange)) { _ in
            refreshPermissionStates()
        }
    }
    
    private func setupStep(_ step: VoiceInkMacOSSetupStepPresentation) -> some View {
        let isCompleted = isStepCompleted(step)

        return HStack(spacing: 16) {
            Image(systemName: step.iconSystemName)
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(stepColor(isCompleted: isCompleted, isOptional: step.isOptional).opacity(0.1))
                .foregroundColor(stepColor(isCompleted: isCompleted, isOptional: step.isOptional))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(step.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCompleted {
                Image(systemName: VoiceInkMacOSSetupPresentation.completedSystemImageName)
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            } else if step.isOptional {
                Image(systemName: VoiceInkMacOSSetupPresentation.optionalSystemImageName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: VoiceInkMacOSSetupPresentation.requiredSystemImageName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(NSColor.separatorColor))
            }
        }
        .padding()
    }
    
    private var actionButton: some View {
        Button(action: handleActionButton) {
            HStack {
                Text(VoiceInkMacOSSetupPresentation.actionButtonTitle(
                    isShortcutConfigured: recordingShortcutManager.isShortcutConfigured,
                    isAccessibilityEnabled: isAccessibilityEnabled,
                    hasTranscriptionModel: transcriptionModelManager.currentTranscriptionModel != nil
                ))
                    .fontWeight(.semibold)
                Image(systemName: VoiceInkMacOSSetupPresentation.actionSystemImageName)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
    }
    
    private func handleActionButton() {
        refreshPermissionStates()

        if isRequiredSetupComplete {
            openModelManagement()
        } else {
            if !recordingShortcutManager.isShortcutConfigured {
                openSettings()
            } else if !isAccessibilityEnabled {
                PermissionGrantCoordinator.grantAccessibility { granted in
                    isAccessibilityEnabled = granted
                }
            }
        }
    }
    
    private var helpText: some View {
        Text(VoiceInkMacOSSetupPresentation.helpText)
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    private var isRequiredSetupComplete: Bool {
        recordingShortcutManager.isShortcutConfigured &&
        isAccessibilityEnabled
    }

    private func refreshPermissionStates() {
        isAccessibilityEnabled = AXIsProcessTrusted()
        isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
    }

    private func isStepCompleted(_ step: VoiceInkMacOSSetupStepPresentation) -> Bool {
        step.isCompleted(
            isShortcutConfigured: recordingShortcutManager.isShortcutConfigured,
            isAccessibilityEnabled: isAccessibilityEnabled,
            isScreenRecordingEnabled: isScreenRecordingEnabled,
            hasCurrentTranscriptionModel: transcriptionModelManager.currentTranscriptionModel != nil
        )
    }

    private func stepColor(isCompleted: Bool, isOptional: Bool) -> Color {
        if isCompleted {
            return .green
        }

        return isOptional ? .secondary : Color.accentColor
    }
    
    private func openSettings() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .settings)
        )
    }
    
    private func openModelManagement() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .aiModels)
        )
    }
}
