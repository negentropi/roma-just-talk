import Foundation
import AppKit
import os

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private var enhancementService: AIEnhancementService?
    private let browserURLService = BrowserURLService.shared

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "browser.detection"
    )

    private init() {}

    func configure(with enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }
    
    func applyConfiguration(powerModeId: UUID? = nil) async {
        let powerModeManager = PowerModeManager.shared

        if let powerModeId = powerModeId,
           let config = powerModeManager.getConfiguration(with: powerModeId) {
            await MainActor.run {
                powerModeManager.setActiveConfiguration(config)
            }
            await PowerModeSessionManager.shared.beginSession(with: config)
            return
        }

        let configurations = powerModeManager.configurations
        guard configurations.hasEnabledAutomaticRules else {
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return
        }

        await MainActor.run {
            currentApplication = frontmostApp
        }

        var configToApply: PowerModeConfig?

        if configurations.hasEnabledURLRules,
           let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            do {
                let currentURL = try await browserURLService.getCurrentURL(from: browserType)
                if let config = powerModeManager.getConfigurationForURL(currentURL) {
                    configToApply = config
                }
            } catch {
                logger.error("❌ Failed to get URL from \(browserType.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if configToApply == nil {
            configToApply = powerModeManager.getConfigurationForApp(bundleIdentifier)
        }

        if configToApply == nil {
            configToApply = powerModeManager.getDefaultConfiguration()
        }

        if let config = configToApply {
            await MainActor.run {
                powerModeManager.setActiveConfiguration(config)
            }
            await PowerModeSessionManager.shared.beginSession(with: config)
        }
    }
} 
