import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

extension VoiceInkTests {
    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetTextEditPreservesUnicodeOutsideSelection() async throws {
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        try await editor.selectOriginalPassage()

        let target = try WritingTarget.capture(requiresSelection: true)
        #expect(target.selectedText.utf16.elementsEqual(LiveWritingEditor.passage.utf16))
        let replacement = "Rewritten 台灣\nSecond line"
        try target.replace(with: replacement)
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        try await editor.waitForValue(expected)
        #expect(editor.value?.utf16.elementsEqual(expected.utf16) == true)
        editor.record("textedit-replacement", expected: expected)
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetTextEditRefusesRangeTextAndFocusDrift() async throws {
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        try await editor.selectOriginalPassage()
        let rangeTarget = try WritingTarget.capture(requiresSelection: true)
        try await editor.select(NSRange(location: 0, length: 3))
        expectLiveTargetChanged(rangeTarget)
        #expect(editor.value == LiveWritingEditor.original)
        editor.record("textedit-range-drift", expected: LiveWritingEditor.original)

        try await editor.selectOriginalPassage()
        let textTarget = try WritingTarget.capture(requiresSelection: true)
        try editor.replaceSelection("User's edit")
        let userEdited = LiveWritingEditor.prefix + "User's edit" + LiveWritingEditor.suffix
        try await editor.waitForValue(userEdited)
        expectLiveTargetChanged(textTarget)
        #expect(editor.value == userEdited)
        editor.record("textedit-text-drift", expected: userEdited)

        try await editor.select(NSRange(location: 0, length: userEdited.utf16.count))
        try editor.replaceSelection(LiveWritingEditor.original)
        try await editor.waitForValue(LiveWritingEditor.original)
        try await editor.selectOriginalPassage()
        let focusTarget = try WritingTarget.capture(requiresSelection: true)
        let other = try await LiveWritingEditor.open(.textEdit)
        defer { other.close() }
        try await other.selectOriginalPassage()
        expectLiveTargetChanged(focusTarget)
        #expect(editor.value == LiveWritingEditor.original)
        #expect(other.value == LiveWritingEditor.original)
        editor.record("textedit-focus-drift", expected: LiveWritingEditor.original)
    }

    @Test(.enabled(if: LiveWritingEditor.isEnabled))
    @MainActor func liveWritingTargetSafariTextareaReplacesOnlySelection() async throws {
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        try await editor.selectOriginalPassage()

        let target = try WritingTarget.capture(requiresSelection: true)
        #expect(target.selectedText.utf16.elementsEqual(LiveWritingEditor.passage.utf16))
        let replacement = "Translated 日本語\nNext paragraph"
        try target.replace(with: replacement)
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        try await editor.waitForValue(expected)
        #expect(editor.value?.utf16.elementsEqual(expected.utf16) == true)
        editor.record("safari-replacement", expected: expected)
    }

    @MainActor private func expectLiveTargetChanged(_ target: WritingTarget) {
        do {
            try target.replace(with: "MUST NOT BE INSERTED")
            Issue.record("A stale live editor accepted a writing replacement.")
        } catch {
            #expect(error as? WritingTarget.Failure == .targetChanged)
        }
    }
}

private enum LiveWritingFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): message }
    }
}

@MainActor
private final class LiveWritingEditor {
    enum Kind {
        case textEdit, safari
        var bundleIdentifier: String {
            self == .textEdit ? "com.apple.TextEdit" : "com.apple.Safari"
        }
    }

    nonisolated static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["RJT_LIVE_WRITING_TARGET_CHECKS"] == "1"
            || environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS"] == "1"
    }

    static let prefix = "Before 👩🏽‍💻 "
    static let passage = "target e\u{301}"
    static let suffix = " after 🧑‍🚀.\n"
    static var original: String { prefix + passage + suffix }

    let token: String
    let kind: Kind
    let directory: URL
    let resource: URL
    let application: NSRunningApplication
    let appElement: AXUIElement
    let window: AXUIElement
    let editor: AXUIElement
    let previousApplication: NSRunningApplication?
    let previousWindows: [AXUIElement]

    private init(
        token: String, kind: Kind, directory: URL, resource: URL,
        application: NSRunningApplication, window: AXUIElement, editor: AXUIElement,
        previousApplication: NSRunningApplication?, previousWindows: [AXUIElement]
    ) {
        self.token = token
        self.kind = kind
        self.directory = directory
        self.resource = resource
        self.application = application
        appElement = AXUIElementCreateApplication(application.processIdentifier)
        self.window = window
        self.editor = editor
        self.previousApplication = previousApplication
        self.previousWindows = previousWindows
    }

    var value: String? { Self.string(kAXValueAttribute, from: editor) }

    static func open(_ kind: Kind) async throws -> LiveWritingEditor {
        guard AXIsProcessTrusted() else {
            throw LiveWritingFailure.failed("Live writing checks require Accessibility for the exact test-host signature.")
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleIdentifier) else {
            throw LiveWritingFailure.failed("Missing live editor \(kind.bundleIdentifier).")
        }
        var windowsBeforeLaunch: [pid_t: [AXUIElement]] = [:]
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier) {
            guard let windows = windows(in: AXUIElementCreateApplication(application.processIdentifier)) else {
                throw LiveWritingFailure.failed("Cannot inventory existing editor windows before the live check.")
            }
            windowsBeforeLaunch[application.processIdentifier] = windows
        }
        let previous = NSWorkspace.shared.frontmostApplication
        let token = "RJT-Writing-Live-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resource = directory.appendingPathComponent(token + (kind == .textEdit ? ".txt" : ".html"))
        let content: String
        if kind == .textEdit {
            content = original
        } else {
            let escaped = original.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            content = """
            <!doctype html><meta charset="utf-8"><title>\(token)</title>
            <label for="editor">\(token)</label>
            <textarea id="editor" aria-label="\(token)" autofocus
              style="display:block;width:800px;height:300px;font:20px monospace">\(escaped)</textarea>
            """
        }
        try content.write(to: resource, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.open(
            [resource], withApplicationAt: applicationURL, configuration: configuration
        )
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let priorWindows = windowsBeforeLaunch[application.processIdentifier] ?? []
        var surface: (AXUIElement, AXUIElement)?
        do {
            try await wait("The owned \(kind.bundleIdentifier) editor did not become accessible.") {
                guard let windows = windows(in: appElement) else { return false }
                for window in windows where identifies(window, token: token) {
                    if kind == .textEdit, priorWindows.contains(where: { CFEqual($0, window) }) { continue }
                    if let editor = descendants(of: window).first(where: {
                        string(kAXRoleAttribute, from: $0) == kAXTextAreaRole as String
                            && string(kAXValueAttribute, from: $0)?.utf16.elementsEqual(original.utf16) == true
                    }) {
                        surface = (window, editor)
                        return true
                    }
                }
                return false
            }
        } catch {
            recordSetupFailure(
                kind: kind, token: token, resource: resource, application: application,
                appElement: appElement, previousWindows: priorWindows
            )
            Issue.record("Could not claim the live editor; preserved fixture \(directory.path).")
            if let previous, !previous.isTerminated { previous.activate() }
            throw error
        }
        guard let (window, editor) = surface else {
            throw LiveWritingFailure.failed("The owned editor disappeared before capture.")
        }
        let fixture = LiveWritingEditor(
            token: token, kind: kind, directory: directory, resource: resource,
            application: application, window: window, editor: editor,
            previousApplication: previous, previousWindows: priorWindows
        )
        do {
            try await fixture.focus()
            return fixture
        } catch {
            fixture.close()
            throw error
        }
    }

    func selectOriginalPassage() async throws {
        try await select(NSRange(location: Self.prefix.utf16.count, length: Self.passage.utf16.count))
    }

    func select(_ range: NSRange) async throws {
        try await focus()
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw LiveWritingFailure.failed("The owned editor did not accept its test selection.")
        }
        let expected = range
        try await Self.wait("The owned editor did not confirm its test selection.") {
            guard let actual = Self.range(from: self.editor) else { return false }
            return actual.location == expected.location && actual.length == expected.length
        }
    }

    func replaceSelection(_ text: String) throws {
        guard AXUIElementSetAttributeValue(editor, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            throw LiveWritingFailure.failed("The owned editor did not accept the fixture's selected-text mutation.")
        }
    }

    func waitForValue(_ expected: String) async throws {
        try await Self.wait("The owned editor did not display the expected text.") {
            self.value?.utf16.elementsEqual(expected.utf16) == true
        }
    }

    private func focus() async throws {
        guard Self.elements(kAXWindowsAttribute, from: appElement).contains(where: { CFEqual($0, window) }),
              Self.identifies(window, token: token) else {
            throw LiveWritingFailure.failed("The fixture no longer owns its editor window.")
        }
        application.activate(options: [.activateAllWindows])
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await Self.wait("The owned editor did not receive focus.") {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == self.application.processIdentifier,
                  let focused = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide()) else { return false }
            return CFEqual(focused, self.editor)
        }
    }

    func close() {
        guard Self.elements(kAXWindowsAttribute, from: appElement).contains(where: { CFEqual($0, window) }),
              Self.identifies(window, token: token) else {
            Issue.record("Live writing cleanup lost ownership; preserved fixture \(directory.path).")
            return
        }
        application.activate(options: [.activateAllWindows])
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard Self.poll(seconds: 2, {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == self.application.processIdentifier,
                  let focused = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide()) else { return false }
            return CFEqual(focused, self.editor)
        }) else {
            Issue.record("Live writing cleanup could not focus its owned editor; preserved \(directory.path).")
            return
        }
        if kind == .textEdit {
            guard let expected = value else {
                Issue.record("Live writing cleanup could not read its owned document.")
                return
            }
            Self.key(kVK_ANSI_S, pid: application.processIdentifier, flags: .maskCommand)
            guard Self.poll(seconds: 3, {
                (try? String(contentsOf: self.resource, encoding: .utf8))?.utf16.elementsEqual(expected.utf16) == true
            }) else {
                Issue.record("Live writing cleanup could not save its owned document; preserved \(directory.path).")
                return
            }
            guard let close = Self.element(kAXCloseButtonAttribute, from: window),
                  AXUIElementPerformAction(close, kAXPressAction as CFString) == .success else {
                Issue.record("Live writing cleanup could not close its owned document.")
                return
            }
        } else {
            Self.key(kVK_ANSI_W, pid: application.processIdentifier, flags: .maskCommand)
        }
        let closed = Self.poll(seconds: 3) {
            guard let windows = Self.windows(in: self.appElement) else {
                return self.application.isTerminated && self.previousWindows.isEmpty
            }
            guard self.previousWindows.allSatisfy({ previous in
                windows.contains { CFEqual($0, previous) }
            }) else { return false }
            return !windows.contains { candidate in
                Self.identifies(candidate, token: self.token)
            }
        }
        record("cleanup", expected: closed ? "owned surface closed" : "owned surface still open")
        guard closed else {
            Issue.record("Live writing cleanup did not prove its owned surface closed; preserved \(directory.path).")
            return
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Live writing cleanup could not remove its owned fixture: \(error)") }
        if let previousApplication, !previousApplication.isTerminated { previousApplication.activate() }
    }

    func record(_ name: String, expected: String) {
        guard let output = Self.evidenceDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let receipt: [String: Any] = [
                "checkpoint": name, "token": token, "bundleIdentifier": kind.bundleIdentifier,
                "processIdentifier": application.processIdentifier, "expected": expected,
                "observed": value ?? "<unavailable>", "date": ISO8601DateFormatter().string(from: Date())
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-\(name).json"))
        } catch { Issue.record("Could not write live writing evidence: \(error)") }
    }

    private static var evidenceDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        return (environment["RJT_LIVE_WRITING_TARGET_EVIDENCE"]
            ?? environment["TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE"])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func recordSetupFailure(
        kind: Kind, token: String, resource: URL, application: NSRunningApplication,
        appElement: AXUIElement, previousWindows: [AXUIElement]
    ) {
        guard let output = evidenceDirectory else { return }
        _ = AXUIElementSetMessagingTimeout(appElement, 0.2)
        let currentWindows = windows(in: appElement)
        let focused = element(kAXFocusedUIElementAttribute, from: appElement)
        let deadline = Date().addingTimeInterval(5)
        let focusedMetadata = focused.map { diagnosticNode($0, token: token, resource: resource, deadline: deadline) } ?? [:]
        let focusedWindow = focused.flatMap { element(kAXWindowAttribute, from: $0) }
        var ownedWindows: [AXUIElement] = []
        var summaries: [[String: Any]] = []
        for window in currentWindows ?? [] {
            guard Date() < deadline else { break }
            let tree = diagnosticTree(window, deadline: min(deadline, Date().addingTimeInterval(2)))
            let owned = tree.nodes.contains { node in
                guard Date() < deadline else { return false }
                return [kAXTitleAttribute, kAXDescriptionAttribute, kAXDocumentAttribute].contains {
                    string($0, from: node)?.contains(token) == true
                }
            }
            if owned { ownedWindows.append(window) }
            var summary: [String: Any] = [
                "owned": owned,
                "existedBeforeLaunch": previousWindows.contains { CFEqual($0, window) },
                "title": scopedString(kAXTitleAttribute, from: window, token: token),
                "document": scopedURL(kAXDocumentAttribute, from: window, resource: resource),
                "visitedNodes": tree.nodes.count, "traversalTruncated": tree.truncated,
                "childrenAXErrors": tree.errors, "roleCounts": tree.roles
            ]
            if owned {
                var nodes: [[String: Any]] = []
                for (index, node) in tree.nodes.enumerated() {
                    guard Date() < deadline else { break }
                    var metadata = diagnosticNode(node, token: token, resource: resource, deadline: deadline)
                    metadata["index"] = index
                    metadata["focused"] = focused.map { CFEqual($0, node) } ?? false
                    nodes.append(metadata)
                }
                summary["nodes"] = nodes
                summary["metadataTruncated"] = nodes.count != tree.nodes.count
            }
            summaries.append(summary)
        }
        let focusedOwned = focusedWindow.map { candidate in
            ownedWindows.contains { CFEqual($0, candidate) }
        } ?? false
        let screenshotWindow = ownedWindows.first { window in
            !previousWindows.contains { CFEqual($0, window) }
        }
        let screenshot: String
        if ownedWindows.count == 1, let screenshotWindow, Date() < deadline {
            screenshot = captureOwnedWindow(
                screenshotWindow, application: application, token: token, resource: resource, output: output
            )
        } else {
            screenshot = "not captured; no unique new token-owned window within AX deadline"
        }
        let receipt: [String: Any] = [
            "checkpoint": "setup-failure", "token": token, "bundleIdentifier": kind.bundleIdentifier,
            "processIdentifier": application.processIdentifier, "resource": resource.absoluteString,
            "windowsReadable": currentWindows != nil, "windows": summaries,
            "windowsTruncated": summaries.count != currentWindows?.count,
            "focusedElementInOwnedWindow": focusedOwned,
            "focusedElement": focusedMetadata,
            "screenshot": screenshot, "date": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(token)-setup-failure.json"))
        } catch { Issue.record("Could not write live editor setup diagnostics: \(error)") }
    }

    private static func diagnosticNode(_ node: AXUIElement, token: String, resource: URL, deadline: Date) -> [String: Any] {
        _ = AXUIElementSetMessagingTimeout(node, 0.1)
        func read(_ name: String) -> CFTypeRef? {
            Date() < deadline ? attribute(name, from: node) : nil
        }
        let title = read(kAXTitleAttribute) as? String
        let description = read(kAXDescriptionAttribute) as? String
        var metadata: [String: Any] = [
            "role": read(kAXRoleAttribute) as? String ?? "<unavailable>",
            "subrole": read(kAXSubroleAttribute) as? String ?? "<unavailable>",
            "title": title.flatMap { $0.contains(token) ? $0 : nil } ?? "<unrelated text redacted>",
            "description": description.flatMap { $0.contains(token) ? $0 : nil } ?? "<unrelated text redacted>",
            "url": Date() < deadline ? scopedURL(kAXURLAttribute, from: node, resource: resource) : "<AX deadline reached>"
        ]
        guard Date() < deadline,
              title?.contains(token) == true || description?.contains(token) == true else { return metadata }
        let value = read(kAXValueAttribute) as? String
        var settable = DarwinBoolean(false)
        guard Date() < deadline else { return metadata }
        let writableResult = AXUIElementIsAttributeSettable(node, kAXSelectedTextAttribute as CFString, &settable)
        metadata["fixtureValue"] = value ?? "<unavailable>"
        metadata["expectedValue"] = original
        metadata["valueUTF16Count"] = value?.utf16.count ?? -1
        metadata["expectedUTF16Count"] = original.utf16.count
        metadata["prefixUTF16Count"] = prefix.utf16.count
        metadata["passageUTF16Count"] = passage.utf16.count
        metadata["suffixUTF16Count"] = suffix.utf16.count
        metadata["exactUTF16Equal"] = value?.utf16.elementsEqual(original.utf16) ?? false
        metadata["canonicalEqual"] = value == original
        metadata["selectedRangeReadable"] = Date() < deadline && range(from: node) != nil
        metadata["selectedTextWritable"] = writableResult == .success && settable.boolValue
        metadata["selectedTextWritableAXError"] = writableResult.rawValue
        return metadata
    }

    private static func diagnosticTree(
        _ root: AXUIElement, deadline: Date
    ) -> (nodes: [AXUIElement], truncated: Bool, errors: [String: Int], roles: [String: Int]) {
        var queue = [root]
        var index = 0
        var errors: [String: Int] = [:]
        var roles: [String: Int] = [:]
        while index < queue.count, queue.count < 512, Date() < deadline {
            let candidate = queue[index]
            index += 1
            _ = AXUIElementSetMessagingTimeout(candidate, 0.1)
            roles[string(kAXRoleAttribute, from: candidate) ?? "<unavailable>", default: 0] += 1
            guard Date() < deadline else { break }
            var rawChildren: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(candidate, kAXChildrenAttribute as CFString, &rawChildren)
            if result != .success { errors[String(result.rawValue), default: 0] += 1 }
            for child in rawChildren as? [AXUIElement] ?? []
                where !queue.contains(where: { CFEqual($0, child) }) {
                if queue.count == 512 { break }
                queue.append(child)
            }
        }
        return (Array(queue.prefix(index)), index < queue.count, errors, roles)
    }

    private static func scopedString(_ name: String, from node: AXUIElement, token: String) -> String {
        guard let value = string(name, from: node) else { return "<unavailable>" }
        return value.contains(token) ? value : "<unrelated text redacted>"
    }

    private static func scopedURL(_ name: String, from node: AXUIElement, resource: URL) -> String {
        let raw = attribute(name, from: node)
        let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
        guard let url else { return "<unavailable>" }
        return url.isFileURL && url.standardizedFileURL == resource.standardizedFileURL
            ? url.absoluteString : "<unrelated URL redacted>"
    }

    private static func captureOwnedWindow(
        _ window: AXUIElement, application: NSRunningApplication, token: String, resource: URL, output: URL
    ) -> String {
        guard CGPreflightScreenCaptureAccess() else { return "not captured; Screen Recording unavailable" }
        guard string(kAXTitleAttribute, from: window)?.contains(token) == true
                || scopedURL(kAXDocumentAttribute, from: window, resource: resource) == resource.absoluteString else {
            return "not captured; active document ownership unproven"
        }
        guard
              let position = attribute(kAXPositionAttribute, from: window),
              let size = attribute(kAXSizeAttribute, from: window),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return "not captured; owned window bounds unavailable"
        }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              let inventory = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return "not captured; window inventory unavailable" }
        let matches = inventory.filter {
            guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application.processIdentifier,
                  let rawBounds = $0[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return false }
            return abs(bounds.minX - origin.x) < 1 && abs(bounds.minY - origin.y) < 1
                && abs(bounds.width - dimensions.width) < 1 && abs(bounds.height - dimensions.height) < 1
        }
        guard matches.count == 1, let number = matches[0][kCGWindowNumber as String] as? NSNumber else {
            return "not captured; no unique owned window number"
        }
        let image = output.appendingPathComponent("\(token)-setup-failure.png")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", number.stringValue, "-t", "png", image.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            guard poll(seconds: 2, { !process.isRunning }) else {
                process.terminate()
                return "capture timed out"
            }
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: image.path)
                ? image.lastPathComponent : "capture failed (\(process.terminationStatus))"
        } catch { return "capture failed (\(error))" }
    }

    private static func wait(_ failure: String, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(30))
        } while Date() < deadline
        throw LiveWritingFailure.failed(failure)
    }

    private static func poll(seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        } while Date() < deadline
        return predicate()
    }

    private static func identifies(_ window: AXUIElement, token: String) -> Bool {
        string(kAXTitleAttribute, from: window)?.contains(token) == true
            || string(kAXDocumentAttribute, from: window)?.contains(token) == true
            || descendants(of: window).contains {
                string(kAXDescriptionAttribute, from: $0)?.contains(token) == true
                    || string(kAXTitleAttribute, from: $0)?.contains(token) == true
            }
    }

    private static func descendants(of root: AXUIElement) -> [AXUIElement] {
        var queue = [root]
        var index = 0
        let deadline = Date().addingTimeInterval(2)
        while index < queue.count, queue.count < 512, Date() < deadline {
            let candidate = queue[index]
            index += 1
            for child in elements(kAXChildrenAttribute, from: candidate)
                where !queue.contains(where: { CFEqual($0, child) }) {
                queue.append(child)
            }
        }
        return queue
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private static func elements(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        attribute(name, from: element) as? [AXUIElement] ?? []
    }

    private static func windows(in application: AXUIElement) -> [AXUIElement]? {
        attribute(kAXWindowsAttribute, from: application) as? [AXUIElement]
    }

    private static func element(_ name: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func range(from element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func key(_ code: Int, pid: pid_t, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }
}
