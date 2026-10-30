import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import ImageIO
import Security

enum RuntimeScreenCaptureCheck {
    private static let notificationID = "com.apple.UserNotificationCenter"
    private static let notificationPath = "/System/Library/CoreServices/UserNotificationCenter.app"
    private static let ownedHelpers: [String: Set<String>] = [
        "com.happyf.roma-just-talk.RuntimeE2EHarness": ["RuntimeE2EHarness"],
        "com.negentropi.LipDictationE2E": ["LipDictationE2E", "Lip Dictation E2E"]
    ]

    static func capture(reportURL: URL, consentResultURL: URL) -> Bool {
        let consentDeadline = Date().addingTimeInterval(50)
        var report: [String: Any] = ["passed": false, "captureComplete": false, "pid": getpid()]
        do {
            try requireDisposableHost()
            guard let identifier = Bundle.main.bundleIdentifier, ownedHelpers[identifier] != nil,
                  let executable = Bundle.main.executableURL else { throw CheckError.helperIdentity }
            report["bundleID"] = identifier
            report["bundlePath"] = Bundle.main.bundleURL.path
            report["consentResultPath"] = consentResultURL.path
            report["executableSHA256"] = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
            report["cgPreflightScreenCaptureAccess"] = CGPreflightScreenCaptureAccess()
            try write(report, to: reportURL)
            let pngURL = reportURL.deletingPathExtension().appendingPathExtension("png")
            var image: CGImage?
            var attemptErrors: [String] = []
            // A first request can wait for ordinary OS consent; retry only this real capture.
            for _ in 0..<3 {
                do { image = try RuntimeRenderedTextObserver.captureScreenForPreflight(); break }
                catch {
                    attemptErrors.append(String(describing: error))
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
            }
            report["captureAttemptErrors"] = attemptErrors
            guard let image, image.width > 0, image.height > 0,
                  let destination = CGImageDestinationCreateWithURL(pngURL as CFURL, "public.png" as CFString, 1, nil) else {
                throw CheckError.capture
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CheckError.capture }
            let png = try Data(contentsOf: pngURL)
            guard !png.isEmpty else { throw CheckError.capture }
            report["width"] = image.width
            report["height"] = image.height
            report["pngBytes"] = png.count
            report["pngSHA256"] = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            report["screenshot"] = pngURL.lastPathComponent
            report["passed"] = true
        } catch { report["error"] = String(describing: error) }
        report["captureComplete"] = true
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        do { try write(report, to: reportURL) }
        catch { fputs("Screen capture receipt failed: \(error)\n", stderr); return false }
        guard report["passed"] as? Bool == true else { return false }
        do {
            // Keep the actual requester alive while its delayed OS prompt is handled.
            while Date() < consentDeadline {
                if let data = try? Data(contentsOf: consentResultURL),
                   let consent = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    guard consent["expectedBundleID"] as? String == report["bundleID"] as? String,
                          consent["expectedBundlePath"] as? String == report["bundlePath"] as? String,
                          consent["passed"] as? Bool == true,
                          consent["allowPressCount"] as? Int == 1,
                          consent["promptGone"] as? Bool == true else { throw CheckError.consentFailed }
                    report["consentAcknowledged"] = true
                    report["requesterFinishedAt"] = ISO8601DateFormatter().string(from: Date())
                    try write(report, to: reportURL)
                    return true
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            throw CheckError.deadline
        } catch {
            report["passed"] = false
            report["consentAcknowledged"] = false
            report["error"] = String(describing: error)
            report["requesterFinishedAt"] = ISO8601DateFormatter().string(from: Date())
            try? write(report, to: reportURL)
            return false
        }
    }

    static func approveConsent(configurationURL: URL, reportURL: URL) -> Bool {
        var report: [String: Any] = ["passed": false, "allowPressCount": 0]
        defer {
            report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            try? write(report, to: reportURL)
        }
        do {
            try requireDisposableHost()
            guard AXIsProcessTrusted(), Bundle.main.bundleIdentifier == "com.negentropi.LipDictationE2E" else {
                throw CheckError.driverPermission
            }
            let configuration = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: configurationURL))
            guard let appPath = configuration["appPath"], let capturePath = configuration["captureReport"],
                  let readyPath = configuration["readyReport"],
                  let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
                  let identifier = bundle.bundleIdentifier, let allowedNames = ownedHelpers[identifier],
                  let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                  allowedNames.contains(executableName), validSignature(at: bundle.bundleURL) else {
                throw CheckError.helperIdentity
            }
            let names = allowedNames.intersection([
                executableName,
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
            ])
            report["expectedBundleID"] = identifier
            report["expectedBundlePath"] = bundle.bundleURL.path
            report["allowedRequesterNames"] = names.sorted()
            try write(["ready": true, "pid": getpid(), "bundlePath": Bundle.main.bundleURL.path, "accessibilityGranted": true], to: URL(fileURLWithPath: readyPath))
            let deadline = Date().addingTimeInterval(45)
            var pressed = false
            var quietSince: Date?
            while Date() < deadline {
                let candidates: [Prompt]
                do { candidates = try matchingPrompts(requesterNames: names) }
                catch CheckError.notificationAXUnreadable {
                    quietSince = nil
                    report["notificationAXReadRetried"] = true
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    continue
                }
                guard candidates.count <= 1 else { throw CheckError.ambiguousPrompt }
                if let prompt = candidates.first {
                    quietSince = nil
                    if !pressed, enabled(prompt.allow) {
                        guard AXUIElementPerformAction(prompt.allow, kAXPressAction as CFString) == .success else {
                            throw CheckError.allowFailed
                        }
                        pressed = true
                        report["allowPressCount"] = 1
                        report["matchedRequesterName"] = prompt.requesterName
                        report["notificationPID"] = prompt.pid
                        report["notificationBundleID"] = notificationID
                        report["notificationBundlePath"] = notificationPath
                        report["matchedPrompt"] = promptTitle(prompt.requesterName)
                        report["allowPressedAt"] = ISO8601DateFormatter().string(from: Date())
                    }
                } else if pressed,
                          let data = try? Data(contentsOf: URL(fileURLWithPath: capturePath)),
                          let capture = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          capture["captureComplete"] as? Bool == true {
                    guard capture["bundleID"] as? String == identifier,
                          capture["bundlePath"] as? String == bundle.bundleURL.path else { throw CheckError.helperIdentity }
                    if quietSince == nil { quietSince = Date() }
                    if Date().timeIntervalSince(quietSince!) >= 2 {
                        report["promptGone"] = true
                        report["promptFreeSettleSeconds"] = 2
                        report["capturePassed"] = capture["passed"] as? Bool == true
                        guard capture["passed"] as? Bool == true else { throw CheckError.capture }
                        report["passed"] = true
                        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
                        return true
                    }
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if !pressed { throw CheckError.consentNotObserved }
            throw CheckError.deadline
        } catch { report["error"] = String(describing: error); return false }
    }

    private struct Prompt {
        let allow: AXUIElement
        let requesterName: String
        let pid: pid_t
    }

    private static func matchingPrompts(requesterNames: Set<String>) throws -> [Prompt] {
        var matches: [Prompt] = []
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: notificationID) {
            guard application.bundleURL?.path == notificationPath, validAppleProcess(application.processIdentifier) else {
                throw CheckError.notificationIdentity
            }
            let root = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { throw CheckError.notificationAXUnreadable }
            for window in windows {
                var queue: [(AXUIElement, Int)] = [(window, 0)]
                var visited: [AXUIElement] = []
                var texts: [String] = []
                var buttons: [(AXUIElement, String)] = []
                let scanDeadline = Date().addingTimeInterval(1)
                while !queue.isEmpty, visited.count < 300, Date() < scanDeadline {
                    let (element, depth) = queue.removeFirst()
                    guard depth <= 16, !visited.contains(where: { CFEqual($0, element) }) else { continue }
                    visited.append(element)
                    AXUIElementSetMessagingTimeout(element, 0.1)
                    let role = string(kAXRoleAttribute, element)
                    guard role != nil else { throw CheckError.notificationAXUnreadable }
                    if role == kAXStaticTextRole {
                        texts.append(string(kAXValueAttribute, element) ?? string(kAXTitleAttribute, element) ?? "")
                    }
                    if role == kAXButtonRole {
                        let title = normalized(string(kAXTitleAttribute, element) ?? string(kAXDescriptionAttribute, element) ?? "")
                        if !title.isEmpty { buttons.append((element, title)) }
                    }
                    var childrenValue: CFTypeRef?
                    let childrenStatus = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
                    if childrenStatus == .success, let children = childrenValue as? [AXUIElement] {
                        queue.append(contentsOf: children.map { ($0, depth + 1) })
                    } else if childrenStatus != .noValue, childrenStatus != .attributeUnsupported {
                        throw CheckError.notificationAXUnreadable
                    }
                }
                guard queue.isEmpty else { throw CheckError.incompletePromptScan }
                let text = normalized(texts.joined(separator: " "))
                let matchingNames = requesterNames.filter {
                    text.contains(normalized(promptTitle($0))) && text.contains(normalized(promptBody($0)))
                }
                if matchingNames.isEmpty {
                    guard buttons.isEmpty else { throw CheckError.unexpectedPrompt }
                    continue
                }
                let allow = buttons.filter { $0.1 == "Allow" }
                guard allow.count == 1,
                      buttons.filter({ $0.1 == "Open System Settings" }).count == 1,
                      Set(buttons.map(\.1)) == ["Allow", "Open System Settings"] else { throw CheckError.unexpectedPrompt }
                for name in matchingNames {
                    matches.append(Prompt(allow: allow[0].0, requesterName: name, pid: application.processIdentifier))
                }
            }
        }
        return matches
    }

    private static func promptTitle(_ name: String) -> String {
        "\"\(name)\" is requesting to bypass the system private window picker and directly access your screen and audio."
    }

    private static func promptBody(_ name: String) -> String {
        "This will allow \(name) to record your screen and system audio, including personal or sensitive information that may be visible or audible."
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func string(_ attribute: String, _ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func enabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success
            && (value as? NSNumber)?.boolValue == true
    }

    private static func validAppleProcess(_ pid: pid_t) -> Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: 0)
        return SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary, flags, &code) == errSecSuccess
            && SecRequirementCreateWithString("anchor apple and identifier \"com.apple.UserNotificationCenter\"" as CFString, flags, &requirement) == errSecSuccess
            && code.map { SecCodeCheckValidity($0, flags, requirement) == errSecSuccess } == true
    }

    private static func validSignature(at url: URL) -> Bool {
        var code: SecStaticCode?
        let flags = SecCSFlags(rawValue: 0)
        return SecStaticCodeCreateWithPath(url as CFURL, flags, &code) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, flags, nil) == errSecSuccess } == true
    }

    private static func requireDisposableHost() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              getuid() != 0 else { throw CheckError.disposableHost }
    }

    private static func write(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private enum CheckError: Error {
        case disposableHost, helperIdentity, driverPermission, notificationIdentity, notificationAXUnreadable, ambiguousPrompt
        case incompletePromptScan, unexpectedPrompt, allowFailed, consentNotObserved, consentFailed, capture, deadline
    }
}
