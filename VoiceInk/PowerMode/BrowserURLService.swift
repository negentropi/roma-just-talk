import Foundation
import AppKit
import os
import VoiceInkCore

enum BrowserURLError: Error {
    case scriptNotFound
    case executionFailed
    case browserNotRunning
    case noActiveWindow
    case noActiveTab
}

class BrowserURLService {
    static let shared = BrowserURLService()
    
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkPowerModeBrowserURLDiagnostics.loggerCategory
    )
    
    private init() {}
    
    func getCurrentURL(from browser: VoiceInkPowerModeBrowser) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.scriptNotFoundMessage(scriptName: browser.scriptName), privacy: .public)")
            throw BrowserURLError.scriptNotFound
        }
        
        logger.debug("\(VoiceInkPowerModeBrowserURLDiagnostics.attemptingExecutionMessage(browserDisplayName: browser.displayName), privacy: .public)")
        
        // Check if browser is running
        if !isRunning(browser) {
            logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.browserNotRunningMessage(browserDisplayName: browser.displayName), privacy: .public)")
            throw BrowserURLError.browserNotRunning
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            logger.debug("\(VoiceInkPowerModeBrowserURLDiagnostics.executingScriptMessage(browserDisplayName: browser.displayName), privacy: .public)")
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty {
                    logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.emptyOutputMessage(browserDisplayName: browser.displayName), privacy: .public)")
                    throw BrowserURLError.noActiveTab
                }
                
                // Check if output contains error messages
                if output.lowercased().contains("error") {
                    logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.scriptErrorMessage(browserDisplayName: browser.displayName, output: output), privacy: .public)")
                    throw BrowserURLError.executionFailed
                }
                
                logger.debug("\(VoiceInkPowerModeBrowserURLDiagnostics.successMessage(browserDisplayName: browser.displayName, output: output), privacy: .public)")
                return output
            } else {
                logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.outputDecodeFailedMessage(browserDisplayName: browser.displayName), privacy: .public)")
                throw BrowserURLError.executionFailed
            }
        } catch {
            logger.error("\(VoiceInkPowerModeBrowserURLDiagnostics.executionFailedMessage(browserDisplayName: browser.displayName, localizedDescription: error.localizedDescription), privacy: .public)")
            throw BrowserURLError.executionFailed
        }
    }
    
    func isRunning(_ browser: VoiceInkPowerModeBrowser) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleIdentifier }
        logger.debug("\(VoiceInkPowerModeBrowserURLDiagnostics.runningStatusMessage(browserDisplayName: browser.displayName, isRunning: isRunning), privacy: .public)")
        return isRunning
    }
} 
