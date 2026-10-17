import Foundation
import AppKit
import os
import RomaCore

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
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaPowerModeBrowserURLDiagnostics.loggerCategory
    )
    
    private init() {}
    
    func getCurrentURL(from browser: RomaPowerModeBrowser) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            logger.error("\(RomaPowerModeBrowserURLDiagnostics.scriptNotFoundMessage(scriptName: browser.scriptName), privacy: .public)")
            throw BrowserURLError.scriptNotFound
        }
        
        logger.debug("\(RomaPowerModeBrowserURLDiagnostics.attemptingExecutionMessage(browserDisplayName: browser.displayName), privacy: .public)")
        
        // Check if browser is running
        if !isRunning(browser) {
            logger.error("\(RomaPowerModeBrowserURLDiagnostics.browserNotRunningMessage(browserDisplayName: browser.displayName), privacy: .public)")
            throw BrowserURLError.browserNotRunning
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            logger.debug("\(RomaPowerModeBrowserURLDiagnostics.executingScriptMessage(browserDisplayName: browser.displayName), privacy: .public)")
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty {
                    logger.error("\(RomaPowerModeBrowserURLDiagnostics.emptyOutputMessage(browserDisplayName: browser.displayName), privacy: .public)")
                    throw BrowserURLError.noActiveTab
                }
                
                // Check if output contains error messages
                if output.lowercased().contains("error") {
                    logger.error("\(RomaPowerModeBrowserURLDiagnostics.scriptErrorMessage(browserDisplayName: browser.displayName, output: output), privacy: .public)")
                    throw BrowserURLError.executionFailed
                }
                
                logger.debug("\(RomaPowerModeBrowserURLDiagnostics.successMessage(browserDisplayName: browser.displayName, output: output), privacy: .public)")
                return output
            } else {
                logger.error("\(RomaPowerModeBrowserURLDiagnostics.outputDecodeFailedMessage(browserDisplayName: browser.displayName), privacy: .public)")
                throw BrowserURLError.executionFailed
            }
        } catch {
            logger.error("\(RomaPowerModeBrowserURLDiagnostics.executionFailedMessage(browserDisplayName: browser.displayName, localizedDescription: error.localizedDescription), privacy: .public)")
            throw BrowserURLError.executionFailed
        }
    }
    
    func isRunning(_ browser: RomaPowerModeBrowser) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleIdentifier }
        logger.debug("\(RomaPowerModeBrowserURLDiagnostics.runningStatusMessage(browserDisplayName: browser.displayName, isRunning: isRunning), privacy: .public)")
        return isRunning
    }
} 
