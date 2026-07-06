import SwiftUI
import AVFoundation
import Cocoa
import CoreGraphics
import PermissionFlow
import VoiceInkCore

@MainActor
class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isInputMonitoringEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var inputMonitoringNeedsRelaunch = false
    @Published var screenRecordingNeedsRelaunch = false
    private let permissionFlowGuide = PermissionFlowGuide()
    private var permissionRefreshTimer: Timer?
    private var permissionRefreshPollingState = VoiceInkMacOSPermissionPollingState.stopped
    
    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()
        
        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        permissionRefreshTimer?.invalidate()
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appPermissionsDidChange),
            name: .appPermissionsDidChange,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }

    @objc private func appPermissionsDidChange() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkInputMonitoringPermission()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        isAccessibilityEnabled = accessibilityEnabled
    }
    
    func checkScreenRecordingPermission() {
        isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
        if isScreenRecordingEnabled {
            screenRecordingNeedsRelaunch = false
        }
    }
    
    func requestScreenRecordingPermission() {
        screenRecordingNeedsRelaunch = false
        permissionFlowGuide.open(.screenRecording)
        startPermissionRefreshPolling()
        markRelaunchNeededIfPermissionStillInactive(.screenRecording)
    }
    
    func checkAudioPermissionStatus() {
        audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestAudioPermission() {
        PermissionGrantCoordinator.grantMicrophone { [weak self] status in
            self?.audioPermissionStatus = status
            self?.startPermissionRefreshPolling()
        }
    }

    func openMicrophoneSettings() {
        requestAudioPermission()
    }

    func checkInputMonitoringPermission() {
        isInputMonitoringEnabled = ShortcutMonitor.preflightListenEventAccess()
        if isInputMonitoringEnabled {
            inputMonitoringNeedsRelaunch = false
        }
    }

    func requestInputMonitoringPermission() {
        inputMonitoringNeedsRelaunch = false
        PermissionGrantCoordinator.grantInputMonitoring { [weak self] granted in
            self?.isInputMonitoringEnabled = granted
        }
        startPermissionRefreshPolling()
        markRelaunchNeededIfPermissionStillInactive(.inputMonitoring)
    }

    func requestAccessibilityPermission() {
        PermissionGrantCoordinator.grantAccessibility { [weak self] granted in
            self?.isAccessibilityEnabled = granted
        }
        startPermissionRefreshPolling()
    }
    
    private func startPermissionRefreshPolling() {
        PermissionRefreshCenter.shared.beginPolling()
        permissionRefreshTimer?.invalidate()
        permissionRefreshPollingState = .started()
        permissionRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: VoiceInkMacOSPermissionTimingPolicy.pollingInterval,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.checkAllPermissions()

                if self.permissionRefreshPollingState.consumePollAndShouldStop() {
                    timer.invalidate()
                    self.permissionRefreshTimer = nil
                }
            }
        }
    }

    private enum RelaunchSensitivePermission {
        case inputMonitoring
        case screenRecording
    }

    private func markRelaunchNeededIfPermissionStillInactive(_ permission: RelaunchSensitivePermission) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VoiceInkMacOSPermissionTimingPolicy.relaunchRequiredDelay
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch permission {
                case .inputMonitoring:
                    self.checkInputMonitoringPermission()
                    if !self.isInputMonitoringEnabled {
                        self.inputMonitoringNeedsRelaunch = true
                    }
                case .screenRecording:
                    self.checkScreenRecordingPermission()
                    if !self.isScreenRecordingEnabled {
                        self.screenRecordingNeedsRelaunch = true
                    }
                }
            }
        }
    }
}

struct PermissionCard: View {
    let presentation: VoiceInkMacOSPermissionSettingsCardPresentation
    let isGranted: Bool
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var relaunchRequired: Bool = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? presentation.grantedIconSystemName : presentation.iconSystemName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(presentation.title)
                            .font(.headline)
                        if let message = presentation.infoTipMessage {
                            if let link = presentation.infoTipURLString, !link.isEmpty {
                                InfoTip(message, learnMoreURL: link)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                    Text(presentation.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator with refresh
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        
                        // Reset the animation after a delay
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + VoiceInkMacOSPermissionTimingPolicy.manualRefreshAnimationResetDelay
                        ) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: VoiceInkMacOSPermissionSettingsPresentation.refreshButtonSystemImageName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    
                    if isGranted {
                        Image(systemName: VoiceInkMacOSPermissionSettingsPresentation.grantedStatusSystemImageName)
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Image(systemName: VoiceInkMacOSPermissionSettingsPresentation.deniedStatusSystemImageName)
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            
            if !isGranted {
                if relaunchRequired {
                    Text(VoiceInkMacOSPermissionSettingsPresentation.relaunchRequiredMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: buttonAction) {
                    HStack {
                        Text(presentation.buttonTitle(requiresRelaunch: relaunchRequired))
                        Spacer()
                        Image(systemName: VoiceInkMacOSPermissionSettingsPresentation.actionSystemImageName)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(CardBackground(isSelected: false, cornerRadius: 18))
    }
}

struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                CompactHeroSection(
                    icon: VoiceInkMacOSPermissionSettingsPresentation.headerIconSystemName,
                    title: VoiceInkMacOSPermissionSettingsPresentation.headerTitle,
                    description: VoiceInkMacOSPermissionSettingsPresentation.headerDescription
                )
                
                // Permission Cards
                VStack(spacing: 16) {
                    // Input Monitoring Permission
                    PermissionCard(
                        presentation: VoiceInkMacOSPermissionSettingsPresentation.inputMonitoringCard,
                        isGranted: permissionManager.isInputMonitoringEnabled,
                        buttonAction: {
                            if permissionManager.inputMonitoringNeedsRelaunch {
                                AppRelauncher.relaunch()
                            } else {
                                permissionManager.requestInputMonitoringPermission()
                            }
                        },
                        checkPermission: { permissionManager.checkInputMonitoringPermission() },
                        relaunchRequired: permissionManager.inputMonitoringNeedsRelaunch
                    )
                    
                    // Audio Permission
                    PermissionCard(
                        presentation: VoiceInkMacOSPermissionSettingsPresentation.microphoneCard,
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonAction: {
                            permissionManager.requestAudioPermission()
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        presentation: VoiceInkMacOSPermissionSettingsPresentation.accessibilityCard,
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonAction: {
                            permissionManager.requestAccessibilityPermission()
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() }
                    )
                    
                    // Screen Recording Permission
                    PermissionCard(
                        presentation: VoiceInkMacOSPermissionSettingsPresentation.screenContextCard,
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonAction: {
                            if permissionManager.screenRecordingNeedsRelaunch {
                                AppRelauncher.relaunch()
                            } else {
                                permissionManager.requestScreenRecordingPermission()
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() },
                        relaunchRequired: permissionManager.screenRecordingNeedsRelaunch
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            permissionManager.checkAllPermissions()
        }
        .suppressesPermissionPromptNotifications()
    }
}

#Preview {
    PermissionsView()
} 
