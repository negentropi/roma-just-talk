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
        updateCurrentApplication: Bool = true,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) async -> PowerModeConfig? {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "power_mode.resolve.enter",
            details: "explicitID=\(powerModeId != nil) configurations=\(PowerModeManager.shared.configurations.count)",
            token: traceToken
        )
        return await VoiceInkPowerModeAutomaticResolutionPlan.resolving(
            configurations: PowerModeManager.shared.configurations,
            explicitID: powerModeId
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                let span = latencyTrace.begin("power_mode.frontmost_application", token: traceToken)
                guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                      let bundleIdentifier = frontmostApp.bundleIdentifier else {
                    latencyTrace.end(span, details: "found=false")
                    return nil
                }

                if updateCurrentApplication {
                    await MainActor.run {
                        currentApplication = frontmostApp
                    }
                }

                latencyTrace.end(
                    span,
                    details: "found=true bundle=\(bundleIdentifier)"
                )
                return bundleIdentifier
            },
            readCurrentWebsiteURL: { browser in
                let span = latencyTrace.begin("power_mode.browser_url", token: traceToken)
                do {
                    let url = try await browserURLService.getCurrentURL(from: browser)
                    latencyTrace.end(
                        span,
                        details: "browser=\(String(describing: browser)) result=success"
                    )
                    return url
                } catch {
                    latencyTrace.end(
                        span,
                        details: "browser=\(String(describing: browser)) result=failure error=\(String(describing: type(of: error)))"
                    )
                    throw error
                }
            },
            logBrowserURLFailure: { message in
                logger.error(
                    "\(message, privacy: .public)"
                )
            }
        )
    }
}
