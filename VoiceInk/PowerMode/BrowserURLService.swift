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
        category: "browser.applescript"
    )
    
    private init() {}
    
    func getCurrentURL(from browser: VoiceInkPowerModeBrowser) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            logger.error("❌ AppleScript file not found: \(browser.scriptName, privacy: .public).scpt")
            throw BrowserURLError.scriptNotFound
        }
        
        logger.debug("🔍 Attempting to execute AppleScript for \(browser.displayName, privacy: .public)")
        
        // Check if browser is running
        if !isRunning(browser) {
            logger.error("❌ Browser not running: \(browser.displayName, privacy: .public)")
            throw BrowserURLError.browserNotRunning
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            logger.debug("▶️ Executing AppleScript for \(browser.displayName, privacy: .public)")
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty {
                    logger.error("❌ Empty output from AppleScript for \(browser.displayName, privacy: .public)")
                    throw BrowserURLError.noActiveTab
                }
                
                // Check if output contains error messages
                if output.lowercased().contains("error") {
                    logger.error("❌ AppleScript error for \(browser.displayName, privacy: .public): \(output, privacy: .public)")
                    throw BrowserURLError.executionFailed
                }
                
                logger.debug("✅ Successfully retrieved URL from \(browser.displayName, privacy: .public): \(output, privacy: .public)")
                return output
            } else {
                logger.error("❌ Failed to decode output from AppleScript for \(browser.displayName, privacy: .public)")
                throw BrowserURLError.executionFailed
            }
        } catch {
            logger.error("❌ AppleScript execution failed for \(browser.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw BrowserURLError.executionFailed
        }
    }
    
    func isRunning(_ browser: VoiceInkPowerModeBrowser) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleIdentifier }
        logger.debug("\(browser.displayName, privacy: .public) running status: \(isRunning, privacy: .public)")
        return isRunning
    }
} 
