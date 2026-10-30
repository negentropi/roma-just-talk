import AppKit
import ApplicationServices
import Foundation
import Security

@main
struct UIProbe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { return }
        if args.count == 3 && args[2] == "acknowledge-obs-camera-alert" {
            let report = acknowledgeOBSCameraAlert()
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
            }
            return
        }
        let authenticating = args.count > 2 && args[2] == "authenticate-host-autologin"
        let attempting = args.count > 2 && args[2] == "approve"
        let targets = Set(["com.obsproject.obs-studio", "com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.CoreServicesUIAgent", "com.apple.LocalAuthentication.UIAgent", "com.apple.systemuiserver"])
        var applications: [[String: Any]] = []
        var actions: [[String: Any]] = []
        let trusted = AXIsProcessTrusted()
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var requiresAuthentication = false
        let runningApplications = NSWorkspace.shared.runningApplications.sorted { left, right in
            (left.bundleIdentifier == "com.apple.SecurityAgent" ? 0 : 1) < (right.bundleIdentifier == "com.apple.SecurityAgent" ? 0 : 1)
        }
        for app in runningApplications where targets.contains(app.bundleIdentifier ?? "") && (!authenticating || app.bundleIdentifier == "com.apple.SecurityAgent") {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            var nodes: [[String: Any]] = []
            var elements: [(AXUIElement, String, String, Int?)] = []
            var queue: [(AXUIElement, Int)] = [(root, 0)]
            var visited: [AXUIElement] = []
            while !queue.isEmpty && nodes.count < 600 && ProcessInfo.processInfo.systemUptime < deadline {
                let (element, depth) = queue.removeFirst()
                guard depth <= 20, !visited.contains(where: { CFEqual($0, element) }) else { continue }
                visited.append(element)
                AXUIElementSetMessagingTimeout(element, 0.15)
                func read(_ key: String) -> CFTypeRef? {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                    var value: CFTypeRef?
                    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
                }
                let role = read(kAXRoleAttribute) as? String ?? ""
                let title = read(kAXTitleAttribute) as? String ?? ""
                let staticText = role == kAXStaticTextRole ? (read(kAXValueAttribute) as? String ?? "") : ""
                let description = read(kAXDescriptionAttribute) as? String ?? ""
                let label = !title.isEmpty ? title : description
                let secure = role == kAXTextFieldRole && (read(kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole
                requiresAuthentication = requiresAuthentication || secure
                let integer = [kAXCheckBoxRole, "AXSwitch"].contains(role) ? (read(kAXValueAttribute) as? NSNumber)?.intValue : nil
                var node: [String: Any] = ["role": role, "title": title, "description": description, "secureField": secure]
                if let enabled = read(kAXEnabledAttribute) as? NSNumber { node["enabled"] = enabled.boolValue }
                if !staticText.isEmpty { node["staticText"] = staticText }
                if let integer { node["toggleValue"] = integer }
                nodes.append(node)
                elements.append((element, label, role, integer))
                if ![kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuItemRole].contains(role),
                   let children = read(kAXChildrenAttribute) as? [AXUIElement] {
                    queue.append(contentsOf: children.prefix(100).map { ($0, depth + 1) })
                }
            }
            let labels = nodes.map { node in
                let title = node["title"] as? String ?? ""
                let description = node["description"] as? String ?? ""
                let text = node["staticText"] as? String ?? ""
                return [title, description, text].joined(separator: " ")
            }.joined(separator: " ")
            applications.append(["bundleIdentifier": app.bundleIdentifier ?? "", "pid": app.processIdentifier, "nodes": nodes])
            if authenticating, trusted, app.bundleIdentifier == "com.apple.SecurityAgent" {
                let authentication = SystemExtensionAuthentication.submit(application: app, elements: elements.map { $0.0 }, reportURL: URL(fileURLWithPath: args[1]), deadline: deadline)
                actions.append(authentication)
                continue
            }
            guard attempting, trusted, !requiresAuthentication else { continue }
            func isOnlyToggleInOBSRow(_ element: AXUIElement) -> Bool {
                func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                    var result: CFTypeRef?
                    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
                }
                var ancestor = element
                for _ in 0..<3 {
                    guard let parent = value(ancestor, kAXParentAttribute) else { return false }
                    ancestor = parent as! AXUIElement
                    var descendants: [(AXUIElement, Int)] = [(ancestor, 0)]
                    var text = Set<String>()
                    var checkboxCount = 0
                    var visitedCount = 0
                    while !descendants.isEmpty && visitedCount < 80 {
                        let (child, depth) = descendants.removeFirst()
                        guard depth <= 3 else { continue }
                        visitedCount += 1
                        let role = value(child, kAXRoleAttribute) as? String ?? ""
                        if [kAXCheckBoxRole, "AXSwitch"].contains(role) { checkboxCount += 1 }
                        if role == kAXStaticTextRole, let label = value(child, kAXValueAttribute) as? String {
                            text.insert(label)
                        }
                        if let children = value(child, kAXChildrenAttribute) as? [AXUIElement] {
                            descendants.append(contentsOf: children.prefix(30).map { ($0, depth + 1) })
                        }
                    }
                    if checkboxCount == 1 && text.contains("OBS") && text.contains("OBS Virtual Camera") { return true }
                }
                return false
            }
            func clickToggleCenter(_ element: AXUIElement) -> [String: Any] {
                var report: [String: Any] = ["method": "ordinaryPointerClick", "posted": false, "postEventTrusted": CGPreflightPostEventAccess()]
                func value(_ attribute: String) -> CFTypeRef? {
                    var result: CFTypeRef?
                    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
                }
                guard let enabled = value(kAXEnabledAttribute) as? NSNumber, enabled.boolValue else {
                    report["reason"] = "checkboxDisabledOrUnknown"
                    return report
                }
                guard CGPreflightPostEventAccess(),
                      let positionValue = value(kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
                      let sizeValue = value(kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                    report["reason"] = "postEventPermissionOrFrameUnavailable"
                    return report
                }
                var position = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
                      size.width > 0, size.height > 0 else { return report }
                let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
                report["x"] = point.x
                report["y"] = point.y
                for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return report }
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                    event.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.05)
                }
                report["posted"] = true
                return report
            }
            let ordered = elements.sorted { left, right in
                func rank(_ item: (AXUIElement, String, String, Int?)) -> Int {
                    if item.1 == "OBS" && item.3 == 0 { return 0 }
                    if item.1 == "Allow" { return 1 }
                    return 2
                }
                return rank(left) < rank(right)
            }
            for (element, label, role, integer) in ordered {
                let obsContext = labels.localizedCaseInsensitiveContains("OBS")
                let cameraContext = labels.localizedCaseInsensitiveContains("camera") || labels.localizedCaseInsensitiveContains("extension")
                let probeContext = (labels.localizedCaseInsensitiveContains("Lip Camera Probe") || labels.localizedCaseInsensitiveContains("LipCameraProbe")) && labels.localizedCaseInsensitiveContains("camera")
                let isSettings = app.bundleIdentifier == "com.apple.systempreferences"
                let obsMicrophonePrompt = app.bundleIdentifier == "com.apple.UserNotificationCenter" && labels.contains("“OBS”") && labels.localizedCaseInsensitiveContains("microphone") && ["Don’t Allow", "Don't Allow"].contains(label) && role == kAXButtonRole
                let obsPermissionReview = app.bundleIdentifier == "com.obsproject.obs-studio" && labels.contains("Review App Permissions") && label == "Continue" && role == kAXButtonRole
                let obsAutoConfiguration = app.bundleIdentifier == "com.obsproject.obs-studio" && labels.contains("Auto-Configuration Wizard") && label == "Cancel" && role == kAXButtonRole
                let settingsNavigation = isSettings && label == "Camera Extensions" && [kAXButtonRole, "AXLink"].contains(role)
                let allowedButton = role == kAXButtonRole && ((obsContext && ["Open System Settings", "Allow"].contains(label)) || (probeContext && label == "Allow"))
                let offOBSToggle = isSettings && labels.contains("Camera Extensions") && integer == 0 && [kAXCheckBoxRole, "AXSwitch"].contains(role) && isOnlyToggleInOBSRow(element)
                if obsMicrophonePrompt || obsPermissionReview || obsAutoConfiguration || settingsNavigation || (allowedButton && (cameraContext || label == "Open System Settings")) || offOBSToggle {
                    if offOBSToggle {
                        var action = clickToggleCenter(element)
                        action["bundleIdentifier"] = app.bundleIdentifier ?? ""
                        action["label"] = "OBS Virtual Camera row toggle"
                        action["rowIdentityVerified"] = true
                        actions.append(action)
                    } else {
                        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                        actions.append(["bundleIdentifier": app.bundleIdentifier ?? "", "label": label, "rowIdentityVerified": false, "method": "AXPress", "result": result.rawValue])
                    }
                    break
                }
            }
        }
        let report: [String: Any] = ["accessibilityTrusted": trusted, "postEventTrusted": CGPreflightPostEventAccess(), "screenCapturePreflight": CGPreflightScreenCaptureAccess(), "authenticationRequired": requiresAuthentication, "actions": actions, "applications": applications]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
        }
    }

    private static func acknowledgeOBSCameraAlert() -> [String: Any] {
        var report: [String: Any] = ["status": "identityUnavailable", "alertAbsentObserved": false, "actionAttempted": false, "accessibilityTrusted": AXIsProcessTrusted()]
        let environment = ProcessInfo.processInfo.environment
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio")
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_OS"] == "macOS", AXIsProcessTrusted(), apps.count == 1,
              let app = apps.first, app.processIdentifier > 1,
              let bundle = app.bundleURL?.resolvingSymlinksInPath(), bundle.path == "/Applications/OBS.app",
              app.executableURL?.resolvingSymlinksInPath().path == "/Applications/OBS.app/Contents/MacOS/OBS" else { return report }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: 0)
        guard SecStaticCodeCreateWithPath(bundle as CFURL, flags, &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"2MMRE5MTB8\" and identifier \"com.obsproject.obs-studio\"" as CFString, flags, &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            report["status"] = "publisherSignatureRejected"
            return report
        }
        report["signedOBSIdentityVerified"] = true
        report["pid"] = app.processIdentifier
        let expectedText = "The virtual camera is not installed.\n\nPlease allow OBS to install the camera system extension in System Settings → General → Login Items & Extensions → Camera Extensions.\n\nYou may need to restart OBS if this message still appears afterward."
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        var readFailed = false
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { readFailed = true; return nil }
            AXUIElementSetMessagingTimeout(element, 0.15)
            var result: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
            if ![AXError.success, .attributeUnsupported, .noValue].contains(error) { readFailed = true }
            return result
        }
        func inspect() -> (String, AXUIElement?) {
            readFailed = false
            guard let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] else { return ("windowsQueryFailed", nil) }
            var alerts: [AXUIElement] = []
            for window in windows {
                guard value(window, kAXRoleAttribute) as? String == kAXWindowRole,
                      let description = value(window, kAXDescriptionAttribute) as? String else { return ("windowIdentityUnavailable", nil) }
                if description == "alert" { alerts.append(window) }
            }
            report["observedAlertCount"] = alerts.count
            if readFailed { return ("AXReadFailed", nil) }
            if alerts.isEmpty { return ("absent", nil) }
            guard alerts.count == 1 else { return ("unexpectedOBSAlerts", nil) }
            var pending: [(AXUIElement, Int)] = [(alerts[0], 0)]
            var visited: [AXUIElement] = []
            var exactTextCount = 0, criticalImageCount = 0, buttonCount = 0
            var buttons: [AXUIElement] = []
            while !pending.isEmpty && visited.count < 64 {
                let (element, depth) = pending.removeFirst()
                guard depth <= 6 else { return ("alertTreeIncomplete", nil) }
                if visited.contains(where: { CFEqual($0, element) }) { continue }
                visited.append(element)
                let role = value(element, kAXRoleAttribute) as? String ?? ""
                if role == kAXStaticTextRole, value(element, kAXValueAttribute) as? String == expectedText { exactTextCount += 1 }
                if role == kAXImageRole, value(element, kAXDescriptionAttribute) as? String == "OBS critical alert" { criticalImageCount += 1 }
                if role == kAXButtonRole {
                    buttonCount += 1
                    if value(element, kAXTitleAttribute) as? String == "OK", (value(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true { buttons.append(element) }
                }
                if let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                    guard children.count <= 30 else { return ("alertTreeIncomplete", nil) }
                    pending.append(contentsOf: children.map { ($0, depth + 1) })
                }
            }
            report["exactTextCount"] = exactTextCount
            report["criticalImageCount"] = criticalImageCount
            report["buttonCount"] = buttonCount
            report["enabledOKCount"] = buttons.count
            guard !readFailed, pending.isEmpty else { return ("alertTreeIncomplete", nil) }
            guard exactTextCount == 1, criticalImageCount == 1, buttonCount == 1, buttons.count == 1 else { return ("unmatchedOBSAlert", nil) }
            var pid: pid_t = 0
            guard AXUIElementGetPid(buttons[0], &pid) == .success, pid == app.processIdentifier else { return ("buttonProcessMismatch", nil) }
            return ("present", buttons[0])
        }
        let (initial, button) = inspect()
        report["initialState"] = initial
        guard initial == "present", let button else {
            report["status"] = initial
            report["alertAbsentObserved"] = initial == "absent"
            return report
        }
        report["actionAttempted"] = true
        let pressed = AXUIElementPerformAction(button, kAXPressAction as CFString)
        report["pressResult"] = pressed.rawValue
        guard pressed == .success else { report["status"] = "acknowledgementRejected"; return report }
        // One acknowledgement only; subsequent reads verify disappearance without another action.
        var observations = 0
        repeat {
            let (state, _) = inspect()
            observations += 1
            report["absenceObservationCount"] = observations
            report["finalState"] = state
            if state == "absent" {
                report["status"] = "acknowledged"
                report["alertAbsentObserved"] = true
                return report
            }
            guard state == "present" else { report["status"] = state; return report }
            Thread.sleep(forTimeInterval: 0.1)
        } while ProcessInfo.processInfo.systemUptime < deadline
        report["status"] = "alertRemainedAfterAcknowledgement"
        return report
    }
}
