import Foundation
import AppKit
import os
import VoiceInkCore

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private let browserURLService = BrowserURLService.shared

    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkPowerModeBrowserDetectionDiagnostics.loggerCategory
    )

    private init() {}

    func resolveConfiguration(
        powerModeId: UUID? = nil,
        updateCurrentApplication: Bool = true
    ) async -> PowerModeConfig? {
        await VoiceInkPowerModeAutomaticResolutionPlan.resolving(
            configurations: PowerModeManager.shared.configurations,
            explicitID: powerModeId
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                      let bundleIdentifier = frontmostApp.bundleIdentifier else {
                    return nil
                }

                if updateCurrentApplication {
                    await MainActor.run {
                        currentApplication = frontmostApp
                    }
                }

                return bundleIdentifier
            },
            readCurrentWebsiteURL: { browser in
                try await browserURLService.getCurrentURL(from: browser)
            },
            logBrowserURLFailure: { message in
                logger.error(
                    "\(message, privacy: .public)"
                )
            }
        )
    }

    func applyResolvedConfiguration(_ config: PowerModeConfig?) async {
        await PowerModeManager.shared.activateConfiguration(config)
    }
}
