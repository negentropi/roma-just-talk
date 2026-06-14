import AppKit
import Foundation

enum CursorTextContextReader {
    private static let defaultMaximumLength = 240
    private static let textInputRoles = Set([
        kAXComboBoxRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String
    ])

    @MainActor
    static func textBeforeCursor(maximumLength: Int = defaultMaximumLength) -> String? {
        guard maximumLength > 0,
              AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = focusedElement(from: systemWideElement),
              let prefix = textBeforeCursor(in: focusedElement, maximumLength: maximumLength) else {
            return nil
        }

        return prefix
    }

    private static func textBeforeCursor(in focusedElement: AXUIElement, maximumLength: Int) -> String? {
        let elements = contextCandidateElements(startingAt: focusedElement)

        for element in elements {
            guard let selectedRange = selectedTextRange(from: element),
                  selectedRange.location != kCFNotFound else {
                continue
            }

            guard selectedRange.location > 0 else { return "" }

            let prefixLength = min(maximumLength, selectedRange.location)
            let prefixRange = CFRange(
                location: selectedRange.location - prefixLength,
                length: prefixLength
            )

            if let prefix = stringForRange(prefixRange, in: element)
                ?? valuePrefix(prefixRange, in: element) {
                return prefix
            }
        }

        for element in elements {
            if let suffix = valueSuffix(in: element, maximumLength: maximumLength) {
                return suffix
            }
        }

        return nil
    }

    private static func contextCandidateElements(startingAt element: AXUIElement) -> [AXUIElement] {
        var elements = [element]
        var currentElement = element

        for _ in 0..<4 {
            guard let parent = parentElement(from: currentElement) else {
                break
            }

            elements.append(parent)
            currentElement = parent
        }

        return elements
    }

    private static func parentElement(from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
              let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func stringForRange(_ range: CFRange, in element: AXUIElement) -> String? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }

        return value as? String
    }

    private static func valuePrefix(_ range: CFRange, in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
              let text = value as? String,
              let stringRange = Range(NSRange(location: range.location, length: range.length), in: text) else {
            return nil
        }

        return String(text[stringRange])
    }

    private static func valueSuffix(in element: AXUIElement, maximumLength: Int) -> String? {
        guard isTextInput(element) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
              let text = value as? String else {
            return nil
        }

        guard text.count > maximumLength else {
            return text
        }

        return String(text.suffix(maximumLength))
    }

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success,
              let role = value as? String else {
            return false
        }

        return textInputRoles.contains(role)
    }
}
