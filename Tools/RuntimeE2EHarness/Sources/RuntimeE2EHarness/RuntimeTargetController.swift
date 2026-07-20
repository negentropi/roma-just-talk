import AppKit
import ApplicationServices
import Foundation
import RuntimeE2ECore

struct RuntimeVisibleTextResult: Codable {
    let text: String?
    let keyUpToVisibleMilliseconds: Double?
    let role: String?
    let error: String?
}

struct RuntimeTargetPreparationInfo: Codable {
    let targetID: String
    let bundleIdentifier: String
    let processIdentifier: Int32
    let testResourcePath: String
    let windowTitleToken: String
    let editableRole: String
    let matchedBy: String
}

struct RuntimeTargetCleanupInfo: Codable {
    let surfaceClosed: Bool
    let temporaryResourceRemoved: Bool
    let terminatedProcessIdentifiers: [Int32]
    let restoredFrontmostApplication: Bool
    let errors: [String]

    var passed: Bool {
        temporaryResourceRemoved
            && restoredFrontmostApplication
            && errors.isEmpty
    }
}

struct RuntimeAbandonedTargetCleanupInfo: Codable {
    let discoveredResources: Int
    let closedSurfaces: Int
    let removedResources: Int
    let unresolvedRunIDs: [String]
    let restoredFrontmostApplication: Bool
    let errors: [String]

    var passed: Bool {
        unresolvedRunIDs.isEmpty && restoredFrontmostApplication && errors.isEmpty
    }
}

final class RuntimePreparedTarget {
    let info: RuntimeTargetPreparationInfo
    private let target: RuntimeTargetApp
    private let appElement: AXUIElement
    private var windowElement: AXUIElement
    private var textElement: AXUIElement
    private let existingProcessIdentifiers: Set<pid_t>
    private let temporaryDirectoryURL: URL
    private let testResourceURL: URL
    private let previousFrontmostApplication: NSRunningApplication?

    init(
        target: RuntimeTargetApp,
        appElement: AXUIElement,
        windowElement: AXUIElement,
        textElement: AXUIElement,
        processIdentifier: pid_t,
        testResourceURL: URL,
        windowTitleToken: String,
        matchedBy: String,
        existingProcessIdentifiers: Set<pid_t>,
        temporaryDirectoryURL: URL,
        previousFrontmostApplication: NSRunningApplication?
    ) {
        self.target = target
        self.appElement = appElement
        self.windowElement = windowElement
        self.textElement = textElement
        self.existingProcessIdentifiers = existingProcessIdentifiers
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.testResourceURL = testResourceURL
        self.previousFrontmostApplication = previousFrontmostApplication
        self.info = RuntimeTargetPreparationInfo(
            targetID: target.id,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: processIdentifier,
            testResourcePath: testResourceURL.path,
            windowTitleToken: windowTitleToken,
            editableRole: RuntimeAX.stringAttribute(kAXRoleAttribute, from: textElement) ?? "unknown",
            matchedBy: matchedBy
        )
    }

    func waitForVisibleText(
        keyUpAtSystemUptime: TimeInterval,
        timeoutSeconds: TimeInterval
    ) -> RuntimeVisibleTextResult {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastError: String?
        while Date() < deadline {
            if let text = RuntimeAX.text(from: textElement),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let latency = max(0, ProcessInfo.processInfo.systemUptime - keyUpAtSystemUptime) * 1_000
                return RuntimeVisibleTextResult(
                    text: text,
                    keyUpToVisibleMilliseconds: latency,
                    role: RuntimeAX.stringAttribute(kAXRoleAttribute, from: textElement),
                    error: nil
                )
            }

            if let refreshedWindow = RuntimeAX.window(containing: info.windowTitleToken, in: appElement) {
                windowElement = refreshedWindow
            }
            if let refreshed = RuntimeAX.editableElement(
                in: windowElement,
                identifying: info.windowTitleToken
            ) ?? RuntimeAX.firstEditableElement(in: windowElement) {
                textElement = refreshed
            } else {
                lastError = "Unique target surface no longer exposes an editable AX element"
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }

        return RuntimeVisibleTextResult(
            text: RuntimeAX.text(from: textElement),
            keyUpToVisibleMilliseconds: nil,
            role: RuntimeAX.stringAttribute(kAXRoleAttribute, from: textElement),
            error: lastError ?? "Visible text timeout"
        )
    }

    func cleanup() -> RuntimeTargetCleanupInfo {
        var errors: [String] = []
        let application = NSRunningApplication(processIdentifier: info.processIdentifier)
        if let application {
            RuntimeAX.focus(
                application: application,
                windowElement: windowElement,
                textElement: textElement
            )
        }

        if target.kind == .document {
            if !RuntimeAX.clear(textElement: textElement) {
                errors.append("Could not clear the temporary document before closing it")
            } else {
                RuntimeAX.postKey(keyCode: 1, flags: .maskCommand)
                if !RuntimeAX.waitForFileToBecomeEmpty(testResourceURL, timeoutSeconds: 2) {
                    errors.append("Temporary document did not save an empty value before cleanup")
                }
            }
        }

        RuntimeAX.postKey(keyCode: 13, flags: .maskCommand)
        let surfaceClosed = RuntimeAX.waitForSurfaceToClose(
            token: info.windowTitleToken,
            in: appElement,
            timeoutSeconds: 3
        )

        var terminatedProcessIdentifiers: [Int32] = []
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
        for application in running where !existingProcessIdentifiers.contains(application.processIdentifier) {
            if application.terminate(),
               RuntimeAX.waitForTermination(application, timeoutSeconds: 3) {
                terminatedProcessIdentifiers.append(application.processIdentifier)
            } else {
                errors.append("Could not terminate newly launched target process \(application.processIdentifier)")
            }
        }

        let temporaryResourceRemoved: Bool
        do {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
            temporaryResourceRemoved = true
        } catch {
            temporaryResourceRemoved = !FileManager.default.fileExists(atPath: temporaryDirectoryURL.path)
            if !temporaryResourceRemoved {
                errors.append("Could not remove temporary target resource: \(error)")
            }
        }

        let restoredFrontmostApplication: Bool
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            restoredFrontmostApplication = previousFrontmostApplication.activate()
        } else {
            restoredFrontmostApplication = true
        }

        return RuntimeTargetCleanupInfo(
            surfaceClosed: surfaceClosed,
            temporaryResourceRemoved: temporaryResourceRemoved,
            terminatedProcessIdentifiers: terminatedProcessIdentifiers,
            restoredFrontmostApplication: restoredFrontmostApplication,
            errors: errors
        )
    }
}

enum RuntimeTargetController {
    static let temporaryTargetsRootURL = URL(
        fileURLWithPath: "/tmp/roma-runtime-e2e-targets",
        isDirectory: true
    )

    private struct TestResource {
        let url: URL
        let windowTitleToken: String
    }

    private struct TargetSurface {
        let application: NSRunningApplication
        let appElement: AXUIElement
        let windowElement: AXUIElement
        let textElement: AXUIElement
        let matchedBy: String
    }

    static func prepare(
        target: RuntimeTargetApp,
        runID: String,
        settleSeconds: TimeInterval,
        availabilityPolicy: RuntimeHarnessConfiguration.TargetAvailabilityPolicy
    ) throws -> RuntimePreparedTarget {
        guard AXIsProcessTrusted() else {
            throw RuntimeTargetControllerError.accessibilityNotGranted
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            throw RuntimeTargetControllerError.applicationNotFound(target.bundleIdentifier)
        }

        let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        let existingApplications = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
        if availabilityPolicy == .runningOnly, existingApplications.isEmpty {
            throw RuntimeTargetControllerError.targetNotRunning(target.bundleIdentifier)
        }
        let existingProcessIdentifiers = Set(existingApplications.map(\.processIdentifier))
        let temporaryDirectoryURL = temporaryTargetsRootURL
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        let resource = try createTestResource(
            target: target,
            title: "Roma Runtime E2E \(runID)",
            directoryURL: temporaryDirectoryURL
        )
        do {
            try launch(
                appURL: appURL,
                appName: appURL.lastPathComponent,
                bundleIdentifier: target.bundleIdentifier,
                resourceURL: resource.url
            )
            let surface = try waitForTargetSurface(
                bundleIdentifier: target.bundleIdentifier,
                windowTitleToken: resource.windowTitleToken,
                timeoutSeconds: 15
            )
            RuntimeAX.focus(
                application: surface.application,
                windowElement: surface.windowElement,
                textElement: surface.textElement
            )
            guard RuntimeAX.clear(textElement: surface.textElement) else {
                throw RuntimeTargetControllerError.couldNotClearTarget
            }
            Thread.sleep(forTimeInterval: settleSeconds)
            guard RuntimeAX.text(from: surface.textElement)?.isEmpty == true else {
                throw RuntimeTargetControllerError.couldNotClearTarget
            }

            return RuntimePreparedTarget(
                target: target,
                appElement: surface.appElement,
                windowElement: surface.windowElement,
                textElement: surface.textElement,
                processIdentifier: surface.application.processIdentifier,
                testResourceURL: resource.url,
                windowTitleToken: resource.windowTitleToken,
                matchedBy: surface.matchedBy,
                existingProcessIdentifiers: existingProcessIdentifiers,
                temporaryDirectoryURL: temporaryDirectoryURL,
                previousFrontmostApplication: previousFrontmostApplication
            )
        } catch {
            cleanupFailedPreparation(
                target: target,
                bundleIdentifier: target.bundleIdentifier,
                windowTitleToken: resource.windowTitleToken,
                existingProcessIdentifiers: existingProcessIdentifiers,
                temporaryDirectoryURL: temporaryDirectoryURL,
                previousFrontmostApplication: previousFrontmostApplication
            )
            throw error
        }
    }

    static func restoreAbandonedTargets(
        targets: [RuntimeTargetApp]
    ) -> RuntimeAbandonedTargetCleanupInfo {
        guard AXIsProcessTrusted() else {
            return RuntimeAbandonedTargetCleanupInfo(
                discoveredResources: 0,
                closedSurfaces: 0,
                removedResources: 0,
                unresolvedRunIDs: [],
                restoredFrontmostApplication: false,
                errors: ["Accessibility is not granted; abandoned target surfaces were not inspected"]
            )
        }

        let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        let resourceURLs = (try? FileManager.default.contentsOfDirectory(
            at: temporaryTargetsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var closedSurfaces = 0
        var removedResources = 0
        var unresolvedRunIDs: [String] = []
        var errors: [String] = []

        for resourceURL in resourceURLs {
            let runID = resourceURL.lastPathComponent
            guard let target = targets.first(where: { runID.contains("-\($0.id)-r") }) else {
                unresolvedRunIDs.append(runID)
                continue
            }
            let tokens = [
                "Roma Runtime E2E \(runID)",
                "Roma-Runtime-E2E-\(runID)"
            ]
            var matchedSurface: TargetSurface?
            var matchedToken: String?
            for token in tokens {
                if let surface = try? waitForTargetSurface(
                    bundleIdentifier: target.bundleIdentifier,
                    windowTitleToken: token,
                    timeoutSeconds: 0.5
                ) {
                    matchedSurface = surface
                    matchedToken = token
                    break
                }
            }

            if let surface = matchedSurface, let matchedToken {
                RuntimeAX.focus(
                    application: surface.application,
                    windowElement: surface.windowElement,
                    textElement: surface.textElement
                )
                if target.kind == .document {
                    _ = RuntimeAX.clear(textElement: surface.textElement)
                    RuntimeAX.postKey(keyCode: 1, flags: .maskCommand)
                }
                RuntimeAX.postKey(keyCode: 13, flags: .maskCommand)
                if RuntimeAX.waitForSurfaceToClose(
                    token: matchedToken,
                    in: surface.appElement,
                    timeoutSeconds: 2
                ) {
                    closedSurfaces += 1
                }
            }

            do {
                try FileManager.default.removeItem(at: resourceURL)
                removedResources += 1
            } catch {
                unresolvedRunIDs.append(runID)
                errors.append("Could not remove abandoned target \(runID): \(error)")
            }
        }

        let restoredFrontmostApplication: Bool
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            restoredFrontmostApplication = previousFrontmostApplication.activate()
        } else {
            restoredFrontmostApplication = true
        }

        return RuntimeAbandonedTargetCleanupInfo(
            discoveredResources: resourceURLs.count,
            closedSurfaces: closedSurfaces,
            removedResources: removedResources,
            unresolvedRunIDs: unresolvedRunIDs.sorted(),
            restoredFrontmostApplication: restoredFrontmostApplication,
            errors: errors
        )
    }

    private static func createTestResource(
        target: RuntimeTargetApp,
        title: String,
        directoryURL: URL
    ) throws -> TestResource {
        switch target.kind {
        case .browser:
            let url = directoryURL.appendingPathComponent("target.html")
            let escapedTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let editableLabel = RuntimeTargetIsolationPlan.browserEditableLabel(
                windowTitleToken: title
            )
            let html = """
            <!doctype html>
            <meta charset="utf-8">
            <title>\(escapedTitle)</title>
            <style>
              body { margin: 40px; font: 18px -apple-system, sans-serif; }
              textarea { width: 900px; height: 420px; font: 20px -apple-system, sans-serif; }
            </style>
            <label for="target">\(editableLabel)</label>
            <textarea id="target" aria-label="\(editableLabel)" autofocus spellcheck="false"></textarea>
            <script>
              const target = document.getElementById('target');
              addEventListener('load', () => { target.value = ''; target.focus(); });
            </script>
            """
            try Data(html.utf8).write(to: url, options: .atomic)
            return TestResource(url: url, windowTitleToken: title)
        case .document:
            let filename = RuntimeTargetIsolationPlan.documentFilename(windowTitleToken: title)
            let url = directoryURL.appendingPathComponent(filename)
            try Data().write(to: url, options: .atomic)
            return TestResource(url: url, windowTitleToken: title)
        }
    }

    private static func launch(
        appURL: URL,
        appName: String,
        bundleIdentifier: String,
        resourceURL: URL
    ) throws {
        let process = Process()
        if bundleIdentifier == "com.microsoft.VSCode" {
            let launcherURL = appURL.appendingPathComponent("Contents/Resources/app/bin/code")
            guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
                throw RuntimeTargetControllerError.launcherNotFound(appName, launcherURL.path)
            }
            process.executableURL = launcherURL
            process.arguments = ["--reuse-window", resourceURL.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = RuntimeTargetIsolationPlan.openArguments(
                bundleIdentifier: bundleIdentifier,
                resourcePath: resourceURL.path
            )
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeTargetControllerError.launchFailed(appName, process.terminationStatus)
        }
    }

    private static func waitForTargetSurface(
        bundleIdentifier: String,
        windowTitleToken: String,
        timeoutSeconds: TimeInterval
    ) throws -> TargetSurface {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let applications = orderedApplications(bundleIdentifier: bundleIdentifier)
            for application in applications {
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                if let windowElement = RuntimeAX.window(containing: windowTitleToken, in: appElement),
                   let textElement = RuntimeAX.firstEditableElement(in: windowElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "windowTitle"
                    )
                }

                if let textElement = RuntimeAX.editableElement(
                    in: appElement,
                    identifying: windowTitleToken
                ), let windowElement = RuntimeAX.window(for: textElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "editableIdentifier"
                    )
                }

                if let markerElement = RuntimeAX.element(
                    in: appElement,
                    identifying: windowTitleToken
                ), let windowElement = RuntimeAX.window(for: markerElement),
                   let textElement = RuntimeAX.focusedEditableElement(
                       in: appElement,
                       matchingWindow: windowElement
                   ) ?? RuntimeAX.firstEditableElement(in: windowElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "surfaceMarker"
                    )
                }
            }

            if let application = applications.first {
                _ = application.activate(options: [.activateAllWindows])
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeTargetControllerError.targetSurfaceTimedOut(bundleIdentifier)
    }

    private static func orderedApplications(bundleIdentifier: String) -> [NSRunningApplication] {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier == bundleIdentifier else {
            return Array(applications.reversed())
        }
        return [frontmost] + Array(
            applications
                .filter { $0.processIdentifier != frontmost.processIdentifier }
                .reversed()
        )
    }

    private static func cleanupFailedPreparation(
        target: RuntimeTargetApp,
        bundleIdentifier: String,
        windowTitleToken: String,
        existingProcessIdentifiers: Set<pid_t>,
        temporaryDirectoryURL: URL,
        previousFrontmostApplication: NSRunningApplication?
    ) {
        if let surface = try? waitForTargetSurface(
            bundleIdentifier: bundleIdentifier,
            windowTitleToken: windowTitleToken,
            timeoutSeconds: 1
        ) {
            RuntimeAX.focus(
                application: surface.application,
                windowElement: surface.windowElement,
                textElement: surface.textElement
            )
            if target.kind == .document {
                _ = RuntimeAX.clear(textElement: surface.textElement)
                RuntimeAX.postKey(keyCode: 1, flags: .maskCommand)
            }
            RuntimeAX.postKey(keyCode: 13, flags: .maskCommand)
            _ = RuntimeAX.waitForSurfaceToClose(
                token: windowTitleToken,
                in: surface.appElement,
                timeoutSeconds: 2
            )
        }

        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        where !existingProcessIdentifiers.contains(application.processIdentifier) {
            _ = application.terminate()
            _ = RuntimeAX.waitForTermination(application, timeoutSeconds: 3)
        }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            _ = previousFrontmostApplication.activate()
        }
    }
}

enum RuntimeAX {
    private static let editableRoles = Set([kAXTextAreaRole as String, kAXTextFieldRole as String])

    static func firstEditableElement(in root: AXUIElement) -> AXUIElement? {
        editableElement(in: root, identifying: nil)
    }

    static func editableElement(in root: AXUIElement, identifying token: String?) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0
        var visited = 0
        var best: (score: Int, element: AXUIElement)?
        while nextIndex < queue.count && visited < 10_000 {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1
            if isEditable(element) {
                let identifyingText = identifyingText(from: element)
                if let token,
                   identifyingText.localizedCaseInsensitiveContains(token) {
                    return element
                }
                if token == nil {
                    let score = editableScore(element)
                    if best == nil || score > best!.score {
                        best = (score, element)
                    }
                }
            }
            guard depth < 24 else { continue }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
        }
        return best?.element
    }

    static func element(in root: AXUIElement, identifying token: String) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0
        var visited = 0
        while nextIndex < queue.count && visited < 10_000 {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1
            if identifyingText(from: element).localizedCaseInsensitiveContains(token) {
                return element
            }
            guard depth < 24 else { continue }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
        }
        return nil
    }

    static func focusedEditableElement(
        in appElement: AXUIElement,
        matchingWindow windowElement: AXUIElement
    ) -> AXUIElement? {
        guard let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: appElement),
              isEditable(focusedElement),
              let focusedWindow = window(for: focusedElement),
              CFEqual(focusedWindow, windowElement) else {
            return nil
        }
        return focusedElement
    }

    static func text(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let value else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        return (value as? NSAttributedString)?.string
    }

    static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func window(for element: AXUIElement) -> AXUIElement? {
        if let window = elementAttribute(kAXWindowAttribute, from: element) {
            return window
        }

        var current = element
        for _ in 0..<24 {
            if stringAttribute(kAXRoleAttribute, from: current) == kAXWindowRole as String {
                return current
            }
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else {
                return nil
            }
            current = parent
        }
        return nil
    }

    static func window(containing token: String, in appElement: AXUIElement) -> AXUIElement? {
        elementArrayAttribute(kAXWindowsAttribute, from: appElement).first { window in
            stringAttribute(kAXTitleAttribute, from: window)?
                .localizedCaseInsensitiveContains(token) == true
        }
    }

    static func focus(
        application: NSRunningApplication,
        windowElement: AXUIElement,
        textElement: AXUIElement
    ) {
        _ = application.activate(options: [.activateAllWindows])
        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            windowElement,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            windowElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            textElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    static func clear(textElement: AXUIElement) -> Bool {
        if AXUIElementSetAttributeValue(
            textElement,
            kAXValueAttribute as CFString,
            "" as CFString
        ) == .success,
        waitForEmptyText(textElement, timeoutSeconds: 1) {
            return true
        }

        postKey(keyCode: 0, flags: .maskCommand)
        postKey(keyCode: 51, flags: [])
        return waitForEmptyText(textElement, timeoutSeconds: 2)
    }

    static func waitForFileToBecomeEmpty(_ url: URL, timeoutSeconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url), data.isEmpty {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return false
    }

    static func waitForSurfaceToClose(
        token: String,
        in appElement: AXUIElement,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !surfaceExistsInWindows(token: token, in: appElement) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return !surfaceExistsInWindows(token: token, in: appElement)
    }

    static func waitForTermination(
        _ application: NSRunningApplication,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if application.isTerminated {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return application.isTerminated
    }

    static func postKey(keyCode: UInt16, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, from: element),
              editableRoles.contains(role) else {
            return false
        }
        return boolAttribute(kAXEnabledAttribute, from: element) != false
    }

    private static func editableScore(_ element: AXUIElement) -> Int {
        let role = stringAttribute(kAXRoleAttribute, from: element)
        var score = role == kAXTextAreaRole as String ? 20 : 10
        if identifyingText(from: element).localizedCaseInsensitiveContains("Roma Runtime E2E") {
            score += 100
        }
        return score
    }

    private static func identifyingText(from element: AXUIElement) -> String {
        [
            stringAttribute(kAXDescriptionAttribute, from: element),
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXIdentifierAttribute, from: element),
            stringAttribute(kAXHelpAttribute, from: element)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func waitForEmptyText(
        _ element: AXUIElement,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if text(from: element)?.isEmpty == true {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return text(from: element)?.isEmpty == true
    }

    private static func surfaceExistsInWindows(token: String, in appElement: AXUIElement) -> Bool {
        elementArrayAttribute(kAXWindowsAttribute, from: appElement).contains { windowElement in
            stringAttribute(kAXTitleAttribute, from: windowElement)?
                .localizedCaseInsensitiveContains(token) == true
                || editableElement(in: windowElement, identifying: token) != nil
                || element(in: windowElement, identifying: token) != nil
        }
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        return value as? Bool
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }
}

enum RuntimeTargetControllerError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case applicationNotFound(String)
    case targetNotRunning(String)
    case launcherNotFound(String, String)
    case launchFailed(String, Int32)
    case targetSurfaceTimedOut(String)
    case couldNotClearTarget

    var description: String {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility is not granted to the runtime harness"
        case .applicationNotFound(let identifier):
            return "Target app is not installed: \(identifier)"
        case .targetNotRunning(let identifier):
            return "Target app closed after preflight and running-only policy forbids launching it: \(identifier)"
        case .launcherNotFound(let name, let path):
            return "Target app launcher is missing for \(name): \(path)"
        case .launchFailed(let name, let exitCode):
            return "Could not open the test resource in target app \(name) (open exit \(exitCode))"
        case .targetSurfaceTimedOut(let identifier):
            return "Target app did not expose the uniquely identified test surface: \(identifier)"
        case .couldNotClearTarget:
            return "Could not establish an empty target-text baseline"
        }
    }
}
