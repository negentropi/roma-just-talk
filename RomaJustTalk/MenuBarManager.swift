import SwiftUI
import SwiftData
import AppKit
import OSLog
import RomaCore

class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaMacOSLogCategory.menuBarManager)
    @Published var showDockIcon: Bool {
        didSet {
            RomaMenuBarPreference.saveShowDockIcon(showDockIcon)
            updateAppActivationPolicy()
        }
    }

    private var modelContainer: ModelContainer?
    private var engine: RomaEngine?

    init() {
        self.showDockIcon = RomaMenuBarPreference.shouldShowDockIcon()
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
        guard !showDockIcon else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let hasVisibleWindows = NSApplication.shared.windows.contains {
                $0.isVisible && $0.level == .normal && !$0.styleMask.contains(.nonactivatingPanel)
            }
            if !hasVisibleWindows && NSApplication.shared.activationPolicy() != .accessory {
                self?.logger.notice("\(RomaMacOSMenuBarDiagnostics.windowDidCloseAccessoryPolicyMessage, privacy: .public)")
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func configure(modelContainer: ModelContainer, engine: RomaEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
    }
    
    func toggleDockIcon() {
        showDockIcon.toggle()
    }
    
    func applyActivationPolicy() {
        updateAppActivationPolicy()
    }
    
    func focusMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(RomaMacOSMenuBarDiagnostics.focusMainWindowActivationPolicyMessage, privacy: .public)")
        if WindowManager.shared.showMainWindow() == nil {
            logger.error("\(RomaMacOSMenuBarDiagnostics.focusMainWindowFailedMessage, privacy: .public)")
        }
    }
    
    private func updateAppActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }
            let application = NSApplication.shared
            if self.showDockIcon {
                self.logger.notice("\(RomaMacOSMenuBarDiagnostics.updateActivationPolicyRegularMessage, privacy: .public)")
                application.setActivationPolicy(.regular)
                WindowManager.shared.showMainWindow()
            } else {
                self.logger.notice("\(RomaMacOSMenuBarDiagnostics.updateActivationPolicyAccessoryMessage, privacy: .public)")
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            }
        }

        if Thread.isMainThread {
            applyPolicy()
        } else {
            DispatchQueue.main.async(execute: applyPolicy)
        }
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        let requestedMessage = RomaMacOSMenuBarDiagnostics.openMainWindowRequestedMessage(
            destination: destination,
            showDockIcon: showDockIcon
        )
        logger.notice("\(requestedMessage, privacy: .public)")

        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(RomaMacOSMenuBarDiagnostics.openMainWindowActivationPolicyMessage, privacy: .public)")

        guard WindowManager.shared.showMainWindow() != nil else {
            let failureMessage = RomaMacOSMenuBarDiagnostics.openMainWindowFailedMessage(
                destination: destination
            )
            logger.error("\(failureMessage, privacy: .public)")
            return
        }

        let postingMessage = RomaMacOSMenuBarDiagnostics.openMainWindowPostingNavigationMessage(
            destination: destination
        )
        logger.notice("\(postingMessage, privacy: .public)")

        // Post a notification to navigate to the desired destination
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: RomaMacOSNavigationRequest.userInfo(destination: destination)
            )
            let postedMessage = RomaMacOSMenuBarDiagnostics.openMainWindowNavigationPostedMessage(
                destination: destination
            )
            self?.logger.notice("\(postedMessage, privacy: .public)")
        }
    }

    func openHistoryWindow() {
        guard let modelContainer = modelContainer,
              let engine = engine else {
            let failureMessage = RomaMacOSMenuBarDiagnostics.openHistoryWindowDependenciesMissingMessage(
                hasModelContainer: self.modelContainer != nil,
                hasEngine: self.engine != nil
            )
            logger.error("\(failureMessage, privacy: .public)")
            return
        }
        logger.notice("\(RomaMacOSMenuBarDiagnostics.openHistoryWindowOpeningMessage, privacy: .public)")
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("\(RomaMacOSMenuBarDiagnostics.openHistoryWindowActivationPolicyMessage, privacy: .public)")
        HistoryWindowController.shared.showHistoryWindow(
            modelContainer: modelContainer,
            engine: engine
        )
    }
}
