import Foundation
import AppKit
import os
import VoiceInkCore

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private var enhancementService: AIEnhancementService?
    private let browserURLService = BrowserURLService.shared

    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: "browser.detection"
    )

    private init() {}

    func configure(with enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }
    
    func resolveConfiguration(
        powerModeId: UUID? = nil,
        updateCurrentApplication: Bool = true
    ) async -> PowerModeConfig? {
        let powerModeManager = PowerModeManager.shared
        let configurations = powerModeManager.configurations

        if let config = configurations.resolvedPowerModeConfiguration(explicitID: powerModeId) {
            return config
        }

        guard configurations.hasEnabledAutomaticRules else {
            return nil
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return nil
        }

        if updateCurrentApplication {
            await MainActor.run {
                currentApplication = frontmostApp
            }
        }

        var currentWebsiteURL: String?

        if configurations.hasEnabledURLRules,
           let browserType = VoiceInkPowerModeBrowser.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            do {
                currentWebsiteURL = try await browserURLService.getCurrentURL(from: browserType)
            } catch {
                logger.error("❌ Failed to get URL from \(browserType.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return configurations.resolvedPowerModeConfiguration(
            websiteURL: currentWebsiteURL,
            appBundleIdentifier: bundleIdentifier
        )
    }

    func applyResolvedConfiguration(_ config: PowerModeConfig?) async {
        guard let config else { return }

        let powerModeManager = PowerModeManager.shared
        await MainActor.run {
            powerModeManager.setActiveConfiguration(config)
        }
        await PowerModeSessionManager.shared.beginSession(with: config)
    }

    func applyConfiguration(powerModeId: UUID? = nil) async {
        let config = await resolveConfiguration(powerModeId: powerModeId)
        await applyResolvedConfiguration(config)
    }
}
