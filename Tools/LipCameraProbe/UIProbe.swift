import AppKit
import ApplicationServices
import Foundation

@main
struct UIProbe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { return }
        let attempting = args.count > 2 && args[2] == "approve"
        let targets = Set(["com.obsproject.obs-studio", "com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.CoreServicesUIAgent", "com.apple.LocalAuthentication.UIAgent", "com.apple.systemuiserver"])
        var applications: [[String: Any]] = []
        var actions: [[String: Any]] = []
        let trusted = AXIsProcessTrusted()
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var requiresAuthentication = false
        for app in NSWorkspace.shared.runningApplications where targets.contains(app.bundleIdentifier ?? "") {
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
                let settingsNavigation = isSettings && label == "Camera Extensions" && [kAXButtonRole, "AXLink"].contains(role)
                let allowedButton = role == kAXButtonRole && ((obsContext && ["Open System Settings", "Allow"].contains(label)) || (probeContext && label == "Allow"))
                let offOBSToggle = isSettings && labels.contains("Camera Extensions") && integer == 0 && [kAXCheckBoxRole, "AXSwitch"].contains(role) && isOnlyToggleInOBSRow(element)
                if obsMicrophonePrompt || obsPermissionReview || settingsNavigation || (allowedButton && (cameraContext || label == "Open System Settings")) || offOBSToggle {
                    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                    actions.append(["bundleIdentifier": app.bundleIdentifier ?? "", "label": offOBSToggle ? "OBS Virtual Camera row toggle" : label, "rowIdentityVerified": offOBSToggle, "result": result.rawValue])
                    break
                }
            }
        }
        let report: [String: Any] = ["accessibilityTrusted": trusted, "screenCapturePreflight": CGPreflightScreenCaptureAccess(), "authenticationRequired": requiresAuthentication, "actions": actions, "applications": applications]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
        }
    }
}
