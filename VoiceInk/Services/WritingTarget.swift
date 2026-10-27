import AppKit
import Carbon
import Foundation

/// Owns one external editor/range. A delayed writing result must never follow
/// focus or overwrite text the user changed while it was being generated.
@MainActor
final class WritingTarget {
    enum Failure: LocalizedError, Equatable {
        case accessibilityPermission
        case unsupportedEditor
        case protectedField
        case missingSelection
        case targetChanged
        case replacementFailed
        case replacementUnconfirmed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermission:
                return "Allow Accessibility access for Roma Just Talk before editing text in another app."
            case .unsupportedEditor:
                return "Choose an editable text field in another app. This field does not support safe text replacement."
            case .protectedField:
                return "Roma Just Talk does not read or edit protected text fields."
            case .missingSelection:
                return "Select the text you want to edit before starting."
            case .targetChanged:
                return "The original text or selection changed. Your result is still available to copy."
            case .replacementFailed:
                return "This app could not replace the text. Your result is still available to copy."
            case .replacementUnconfirmed:
                return "The app did not confirm the replacement. Check the original field before trying again."
            }
        }
    }

    /// Accessibility uses UTF-16 ranges, not Swift character offsets.
    struct TextSnapshot: Equatable {
        let value: String
        let range: NSRange
        let selectedText: String

        init?(value: String, range: NSRange) {
            let source = value as NSString
            let count = source.length
            guard range.location >= 0,
                  range.length >= 0,
                  range.location <= count,
                  range.length <= count - range.location,
                  Self.isScalarBoundary(range.location, in: source),
                  Self.isScalarBoundary(range.location + range.length, in: source) else {
                return nil
            }
            self.value = value
            self.range = range
            selectedText = source.substring(with: range)
        }

        private static func isScalarBoundary(_ offset: Int, in source: NSString) -> Bool {
            guard offset > 0, offset < source.length else { return true }
            return !(0xD800...0xDBFF).contains(source.character(at: offset - 1))
                || !(0xDC00...0xDFFF).contains(source.character(at: offset))
        }

        func replacement(_ text: String) -> String {
            (value as NSString).replacingCharacters(in: range, with: text)
        }

        func matches(value: String, range: NSRange, selectedText: String?) -> Bool {
            guard self.value.utf16.elementsEqual(value.utf16),
                  self.range == range,
                  let current = Self(value: value, range: range),
                  current.selectedText.utf16.elementsEqual(self.selectedText.utf16) else {
                return false
            }
            return selectedText.map { $0.utf16.elementsEqual(self.selectedText.utf16) } ?? true
        }
    }

    @MainActor
    protocol Access: AnyObject {
        func validate() throws
        func readSnapshot() -> TextSnapshot?
        func readValue() -> String?
        func replaceSelection(_ text: String) -> AXError?
    }

    let selectedText: String
    private let snapshot: TextSnapshot
    private let access: any Access

    init(snapshot: TextSnapshot, access: any Access) {
        self.snapshot = snapshot
        self.access = access
        selectedText = snapshot.selectedText
    }

    static func capture(requiresSelection: Bool) throws -> WritingTarget {
        guard AXIsProcessTrusted() else { throw Failure.accessibilityPermission }
        guard !IsSecureEventInputEnabled() else { throw Failure.protectedField }
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID != ProcessInfo.processInfo.processIdentifier,
              let element = focusedElement() else {
            throw Failure.unsupportedEditor
        }
        var pid = pid_t()
        guard AXUIElementGetPid(element, &pid) == .success,
              pid == frontmostPID else {
            throw Failure.unsupportedEditor
        }
        let access = AXAccess(processIdentifier: pid, element: element)
        try access.validate()
        guard let snapshot = access.readSnapshot() else {
            throw Failure.unsupportedEditor
        }
        if requiresSelection && snapshot.range.length == 0 {
            throw Failure.missingSelection
        }
        return WritingTarget(snapshot: snapshot, access: access)
    }

    func replace(with text: String) throws {
        try validateCurrentTarget()
        let expected = snapshot.replacement(text)

        guard let result = access.replaceSelection(text) else {
            throw Failure.replacementFailed
        }
        if observeValue(expected) { return }
        throw result == .success || !matchesCurrentSnapshot()
            ? Failure.replacementUnconfirmed : Failure.replacementFailed
    }

    nonisolated static func targetMatches(
        capturedPID: pid_t,
        currentPID: pid_t?,
        isSameElement: Bool
    ) -> Bool {
        capturedPID > 0 && currentPID == capturedPID && isSameElement
    }

    private func validateCurrentTarget() throws {
        try access.validate()
        guard matchesCurrentSnapshot() else { throw Failure.targetChanged }
    }

    private func matchesCurrentSnapshot() -> Bool {
        guard let current = access.readSnapshot() else { return false }
        return snapshot.matches(value: current.value, range: current.range, selectedText: current.selectedText)
    }

    private func observeValue(_ expected: String) -> Bool {
        for attempt in 0..<3 {
            if let value = access.readValue(),
               value.utf16.elementsEqual(expected.utf16) { return true }
            if attempt < 2 {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            }
        }
        return false
    }

    private final class AXAccess: Access {
        let processIdentifier: pid_t
        let element: AXUIElement

        init(processIdentifier: pid_t, element: AXUIElement) {
            self.processIdentifier = processIdentifier
            self.element = element
        }

        func validate() throws {
            guard AXIsProcessTrusted() else { throw Failure.accessibilityPermission }
            guard !IsSecureEventInputEnabled(), !WritingTarget.isProtected(element) else {
                throw Failure.protectedField
            }
            let current = WritingTarget.focusedElement()
            guard WritingTarget.targetMatches(
                capturedPID: processIdentifier,
                currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                isSameElement: current.map { CFEqual($0, element) } ?? false
            ) else {
                throw Failure.targetChanged
            }
            guard WritingTarget.isEditable(element) else { throw Failure.unsupportedEditor }
        }

        func readSnapshot() -> TextSnapshot? { WritingTarget.readSnapshot(from: element) }
        func readValue() -> String? { WritingTarget.string(kAXValueAttribute as CFString, from: element) }

        func replaceSelection(_ text: String) -> AXError? {
            guard WritingTarget.isSettable(kAXSelectedTextAttribute as CFString, on: element) else { return nil }
            // Setting the full AXValue can flatten formatting outside the
            // selection. Unsupported editors must keep their document intact.
            return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        }
    }

    private static func readSnapshot(from element: AXUIElement) -> TextSnapshot? {
        guard let value = string(kAXValueAttribute as CFString, from: element),
              let range = selectedRange(from: element),
              let snapshot = TextSnapshot(value: value, range: range) else {
            return nil
        }
        if let selected = string(kAXSelectedTextAttribute as CFString, from: element),
           !selected.utf16.elementsEqual(snapshot.selectedText.utf16) {
            return nil
        }
        return snapshot
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        guard let role = string(kAXRoleAttribute as CFString, from: element),
              [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role),
              boolean(kAXEnabledAttribute as CFString, from: element) != false,
              boolean("AXEditable" as CFString, from: element) != false else {
            return false
        }
        return isSettable(kAXSelectedTextAttribute as CFString, on: element)
    }

    private static func isProtected(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var visited: [AXUIElement] = []
        for _ in 0..<64 {
            guard let candidate = current else { return false }
            if visited.contains(where: { CFEqual($0, candidate) }) { return true }
            visited.append(candidate)
            if string(kAXSubroleAttribute as CFString, from: candidate) == kAXSecureTextFieldSubrole as String
                || boolean("AXProtectedContent" as CFString, from: candidate) == true {
                return true
            }
            current = elementAttribute(kAXParentAttribute as CFString, from: candidate)
        }
        return true
    }

    private static func focusedElement() -> AXUIElement? {
        elementAttribute(kAXFocusedUIElementAttribute as CFString, from: AXUIElementCreateSystemWide())
    }

    private static func elementAttribute(_ name: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ name: CFString, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private static func boolean(_ name: CFString, from element: AXUIElement) -> Bool? {
        attribute(name, from: element) as? Bool
    }

    private static func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static func selectedRange(from element: AXUIElement) -> NSRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute as CFString, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func isSettable(_ name: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name, &settable) == .success && settable.boolValue
    }
}
