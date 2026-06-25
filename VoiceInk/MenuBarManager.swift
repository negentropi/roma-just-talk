import SwiftUI
import SwiftData
import AppKit
import OSLog
import VoiceInkCore

class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkMacOSLogCategory.menuBarManager)
    @Published var isMenuBarOnly: Bool {
        didSet {
            VoiceInkMenuBarPreference.saveIsMenuBarOnly(isMenuBarOnly)
            updateAppActivationPolicy()
        }
    }

    private var modelContainer: ModelContainer?
    private var engine: VoiceInkEngine?

    init() {
        self.isMenuBarOnly = VoiceInkMenuBarPreference.isMenuBarOnly()
        updateAppActivationPolicy()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard isMenuBarOnly else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let hasVisibleWindows = NSApplication.shared.windows.contains {
                $0.isVisible && $0.level == .normal && !$0.styleMask.contains(.nonactivatingPanel)
            }
            if !hasVisibleWindows && NSApplication.shared.activationPolicy() != .accessory {
                self?.logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.windowDidCloseAccessoryPolicyMessage, privacy: .public)")
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func configure(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    func applyActivationPolicy() {
        updateAppActivationPolicy()
    }
    
    func focusMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.focusMainWindowActivationPolicyMessage, privacy: .public)")
        if WindowManager.shared.showMainWindow() == nil {
            logger.error("\(VoiceInkMacOSMenuBarDiagnostics.focusMainWindowFailedMessage, privacy: .public)")
        }
    }
    
    private func updateAppActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                self.logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.updateActivationPolicyAccessoryMessage, privacy: .public)")
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            } else {
                self.logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.updateActivationPolicyRegularMessage, privacy: .public)")
                application.setActivationPolicy(.regular)
                WindowManager.shared.showMainWindow()
            }
        }

        if Thread.isMainThread {
            applyPolicy()
        } else {
            DispatchQueue.main.async(execute: applyPolicy)
        }
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        let requestedMessage = VoiceInkMacOSMenuBarDiagnostics.openMainWindowRequestedMessage(
            destination: destination,
            isMenuBarOnly: isMenuBarOnly
        )
        logger.notice("\(requestedMessage, privacy: .public)")

        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.openMainWindowActivationPolicyMessage, privacy: .public)")

        guard WindowManager.shared.showMainWindow() != nil else {
            let failureMessage = VoiceInkMacOSMenuBarDiagnostics.openMainWindowFailedMessage(
                destination: destination
            )
            logger.error("\(failureMessage, privacy: .public)")
            return
        }

        let postingMessage = VoiceInkMacOSMenuBarDiagnostics.openMainWindowPostingNavigationMessage(
            destination: destination
        )
        logger.notice("\(postingMessage, privacy: .public)")

        // Post a notification to navigate to the desired destination
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: destination)
            )
            let postedMessage = VoiceInkMacOSMenuBarDiagnostics.openMainWindowNavigationPostedMessage(
                destination: destination
            )
            self?.logger.notice("\(postedMessage, privacy: .public)")
        }
    }

    func openHistoryWindow() {
        guard let modelContainer = modelContainer,
              let engine = engine else {
            let failureMessage = VoiceInkMacOSMenuBarDiagnostics.openHistoryWindowDependenciesMissingMessage(
                hasModelContainer: self.modelContainer != nil,
                hasEngine: self.engine != nil
            )
            logger.error("\(failureMessage, privacy: .public)")
            return
        }
        logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.openHistoryWindowOpeningMessage, privacy: .public)")
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(VoiceInkMacOSMenuBarDiagnostics.openHistoryWindowActivationPolicyMessage, privacy: .public)")
        HistoryWindowController.shared.showHistoryWindow(
            modelContainer: modelContainer,
            engine: engine
        )
    }
}
