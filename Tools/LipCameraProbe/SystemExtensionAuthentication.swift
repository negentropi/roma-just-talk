import AppKit
import ApplicationServices
import Darwin
import Foundation
import OpenDirectory
import Security

struct SystemExtensionAuthentication {
    static func submit(
        application: NSRunningApplication,
        elements: [AXUIElement],
        reportURL: URL,
        deadline: TimeInterval
    ) -> [String: Any] {
        var result: [String: Any] = [
            "method": "normalSecurityAgentAuthentication", "accountVerified": false,
            "authenticationAttempted": false, "submitted": false
        ]
        let githubActions = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        let macOSRunner = ProcessInfo.processInfo.environment["RUNNER_OS"] == "macOS"
        let bundleURL = application.bundleURL?.resolvingSymlinksInPath()
        let executableURL = application.executableURL?.resolvingSymlinksInPath()
        result["githubActionsHost"] = githubActions
        result["macOSRunnerHost"] = macOSRunner
        result["securityAgentBundlePath"] = bundleURL?.path ?? ""
        result["securityAgentExecutablePath"] = executableURL?.path ?? ""
        result["postEventTrusted"] = CGPreflightPostEventAccess()
        guard githubActions, macOSRunner,
              application.bundleIdentifier == "com.apple.SecurityAgent",
              let bundleURL, bundleURL.path.hasPrefix("/System/Library/"),
              let executableURL, executableURL.path.hasPrefix(bundleURL.path + "/Contents/MacOS/"),
              CGPreflightPostEventAccess() else {
            result["reason"] = "disposableHostOrSecurityAgentIdentityUnavailable"
            return result
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: 0)
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, flags, &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.SecurityAgent\"" as CFString, flags, &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            result["reason"] = "securityAgentSignatureRejected"
            return result
        }
        result["securityAgentIdentityVerified"] = true
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
        }
        func center(_ element: AXUIElement) -> CGPoint? {
            guard let positionValue = value(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  let sizeValue = value(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
            return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        }
        func click(_ point: CGPoint) -> Bool {
            for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return false }
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.05)
            }
            return true
        }
        let text = Set(elements.compactMap { element -> String? in
            guard value(element, kAXRoleAttribute) as? String == kAXStaticTextRole else { return nil }
            return value(element, kAXValueAttribute) as? String
        })
        guard text.contains("System Extensions"),
              text.contains("System Extensions is trying to modify a System Extension."),
              text.contains("Enter your password to allow this.") else {
            result["reason"] = "unmatchedAuthenticationPrompt"
            return result
        }
        let fields = elements.filter { value($0, kAXRoleAttribute) as? String == kAXTextFieldRole }
        let secureFields = fields.filter { value($0, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole }
        let userFields = fields.filter { value($0, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole }
        let buttons = elements.filter {
            value($0, kAXRoleAttribute) as? String == kAXButtonRole && value($0, kAXTitleAttribute) as? String == "OK"
        }
        guard secureFields.count == 1, userFields.count == 1, buttons.count == 1,
              let shownUser = value(userFields[0], kAXValueAttribute) as? String,
              [NSUserName(), NSFullUserName()].contains(where: { !$0.isEmpty && $0.caseInsensitiveCompare(shownUser) == .orderedSame }) else {
            result["reason"] = "authenticationAccountOrFieldsDoNotMatch"
            return result
        }
        result["currentAccountMatchesPrompt"] = true
        let marker = reportURL.deletingLastPathComponent().appendingPathComponent(".host-auth-attempted")
        let descriptor = Darwin.open(marker.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else {
            result["reason"] = "authenticationAlreadyAttempted"
            return result
        }
        close(descriptor)
        do {
            let credentialURL = URL(fileURLWithPath: "/etc/kcpassword")
            let metadata = try FileManager.default.attributesOfItem(atPath: credentialURL.path)
            guard metadata[.type] as? FileAttributeType == .typeRegular,
                  (metadata[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let permissions = metadata[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0,
                  let credentialSize = metadata[.size] as? NSNumber, credentialSize.intValue > 0, credentialSize.intValue <= 1024 else {
                result["reason"] = "documentedHostCredentialUnavailable"
                return result
            }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", "/bin/cat", credentialURL.path]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            var encoded = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            defer { encoded.resetBytes(in: encoded.startIndex..<encoded.endIndex) }
            guard process.terminationStatus == 0, !encoded.isEmpty, encoded.count <= 1024 else {
                result["reason"] = "documentedHostCredentialReadDenied"
                return result
            }
            let key: [UInt8] = [125, 137, 82, 35, 210, 188, 221, 234, 163, 185, 31]
            var decoded = encoded.enumerated().map { $0.element ^ key[$0.offset % key.count] }
            defer { _ = decoded.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
            let end = decoded.firstIndex(of: 0) ?? decoded.endIndex
            guard let password = String(bytes: decoded[..<end], encoding: .utf8), !password.isEmpty else {
                result["reason"] = "documentedHostCredentialFormatRejected"
                return result
            }
            let node = try ODNode(session: ODSession.default(), name: "/Local/Default")
            let account = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: [kODAttributeTypeUniqueID])
            let identifiers = try account.values(forAttribute: kODAttributeTypeUniqueID) as? [String]
            guard identifiers?.contains(String(geteuid())) == true else {
                result["reason"] = "localAccountIdentifierMismatch"
                return result
            }
            try account.verifyPassword(password)
            result["accountVerified"] = true
            guard let submitPoint = center(buttons[0]), let securePoint = center(secureFields[0]) else {
                result["reason"] = "authenticationControlFrameUnavailable"
                return result
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                result["reason"] = "authenticationDeadlinePassed"
                return result
            }
            guard click(securePoint) else {
                result["reason"] = "secureFieldPointerFocusFailed"
                return result
            }
            Thread.sleep(forTimeInterval: 0.2)
            var focused: CFTypeRef?
            let focusStatus = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
            var focusProbe: [String: Any] = ["globalFocusError": focusStatus.rawValue, "expectedPID": application.processIdentifier]
            if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let focusedElement = focused as! AXUIElement
                var pid: pid_t = 0
                focusProbe["focusedPIDError"] = AXUIElementGetPid(focusedElement, &pid).rawValue
                focusProbe["focusedPID"] = pid
                focusProbe["role"] = value(focusedElement, kAXRoleAttribute) as? String ?? ""
                focusProbe["subrole"] = value(focusedElement, kAXSubroleAttribute) as? String ?? ""
                focusProbe["sameElement"] = CFEqual(focused, secureFields[0])
            }
            result["focusProbe"] = focusProbe
            guard focusStatus == .success, let focused, CFEqual(focused, secureFields[0]) else {
                result["reason"] = "secureFieldFocusNotConfirmed"
                return result
            }
            var units = Array(password.utf16)
            defer { _ = units.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return result }
            units.withUnsafeBufferPointer { down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!) }
            result["authenticationAttempted"] = true
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.15)
            result["submitted"] = click(submitPoint)
        } catch {
            let error = error as NSError
            result["reason"] = "localCredentialVerificationFailed"
            result["errorDomain"] = error.domain
            result["errorCode"] = error.code
        }
        return result
    }
}
