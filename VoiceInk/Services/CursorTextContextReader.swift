import AppKit
import Foundation
import VoiceInkCore

enum CursorTextContextReader {
    private static let webAreaRole = "AXWebArea"
    // Bound malformed Accessibility parent chains without missing deeply nested web editors.
    private static let insertionAncestorTraversalLimit = 64
    private static let commandVMenuTraversalLimit = 2_048
    // Give cold web-editor Accessibility menu discovery one bounded retry.
    private static let commandVMenuTraversalAttempts = 2
    private static let commandVMenuTraversalRetryDelay: TimeInterval = 0.25
    private static let commandVMenuTraversalTimeout: TimeInterval = 0.25
    private static let targetKeyboardEventDelay: TimeInterval = 0.01

    enum SelectedTextInsertionResult: String {
        case inserted
        case insertedWithoutSelection
        case insertedViaValue
        case insertedViaValueWithoutSelection
        case unsupported
        case notApplied

        var didInsert: Bool {
            switch self {
            case .inserted, .insertedWithoutSelection, .insertedViaValue,
                 .insertedViaValueWithoutSelection:
                true
            case .unsupported, .notApplied:
                false
            }
        }

        var method: String? {
            switch self {
            case .inserted:
                "accessibilitySelectedText"
            case .insertedWithoutSelection:
                "accessibilitySelectedTextSelectionUnverified"
            case .insertedViaValue:
                "accessibilityValue"
            case .insertedViaValueWithoutSelection:
                "accessibilityValueSelectionUnverified"
            case .unsupported, .notApplied:
                nil
            }
        }

        var shouldRetryCommandVMenuDiscovery: Bool {
            self == .unsupported
        }
    }

    enum CommandVKeyEventPostDisposition: String, Equatable {
        case commandPosted
        case deliveryUncertain
    }

    enum CommandVKeyEvent: String, Hashable {
        case commandDown = "cmdDown"
        case vDown
        case vUp
        case commandUp = "cmdUp"

        var virtualKey: CGKeyCode {
            switch self {
            case .commandDown, .commandUp: 0x37
            case .vDown, .vUp: 0x09
            }
        }

        var keyDown: Bool {
            self == .commandDown || self == .vDown
        }

        var isRelease: Bool {
            !keyDown
        }
    }

    struct CommandVKeyEventAttempt {
        let event: CommandVKeyEvent
        let result: AXError
    }

    struct CommandVReleaseFallback {
        let event: CommandVKeyEvent
        let posted: Bool
    }

    struct CommandVKeyEventPostResult {
        let processIdentifier: pid_t
        let disposition: CommandVKeyEventPostDisposition
        let initialAttempts: [CommandVKeyEventAttempt]
        let cleanupAttempts: [CommandVKeyEventAttempt]
        let releaseFallbacks: [CommandVReleaseFallback]
    }

    @MainActor
    final class PreparedContext: Sendable {
        fileprivate let focusedElement: AXUIElement
        fileprivate let selectedRange: CFRange?
        fileprivate let text: String?

        fileprivate init(
            focusedElement: AXUIElement,
            selectedRange: CFRange?,
            text: String?
        ) {
            self.focusedElement = focusedElement
            self.selectedRange = selectedRange
            self.text = text
        }
    }

    @MainActor
    static func textBeforeCursor(
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> String? {
        guard VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: maximumLength),
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

    @MainActor
    static func prepareTextBeforeCursor(
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> PreparedContext? {
        guard VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: maximumLength),
              AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = focusedElement(from: systemWideElement) else {
            return nil
        }
        return PreparedContext(
            focusedElement: focusedElement,
            selectedRange: selectedTextRange(from: focusedElement),
            text: textBeforeCursor(in: focusedElement, maximumLength: maximumLength)
        )
    }

    @MainActor
    static func textBeforeCursor(
        preparedContext: PreparedContext?,
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> String? {
        guard let preparedContext,
              AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()),
              CFEqual(focusedElement, preparedContext.focusedElement),
              preparedContext.selectedRange != nil,
              preparedContext.text != nil,
              sameRange(
                selectedTextRange(from: focusedElement),
                preparedContext.selectedRange
              ) else {
            return textBeforeCursor(maximumLength: maximumLength)
        }
        return preparedContext.text
    }

    @MainActor
    static func focusedProcessIdentifierForPaste() -> pid_t? {
        guard AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return nil
        }
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(focusedElement, &processIdentifier) == .success else {
            return nil
        }
        guard processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return processIdentifier
    }

    @MainActor
    static func pressFocusedCommandVMenuItem(
        retryIfUnavailable: Bool,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> pid_t? {
        guard AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return nil
        }
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(focusedElement, &processIdentifier) == .success,
              processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let application = AXUIElementCreateApplication(processIdentifier)

        let traversalAttempts = retryIfUnavailable ? commandVMenuTraversalAttempts : 1
        for attempt in 0..<traversalAttempts {
            guard focusedProcessIdentifierForPaste() == processIdentifier else {
                return nil
            }
            guard let menuBar = elementAttribute(
                kAXMenuBarAttribute as CFString,
                from: application
            ) else {
                VoiceInkLatencyTrace.shared.event(
                    "paste_command_v_menu_lookup",
                    details: "attempt=\(attempt + 1) result=noMenuBar",
                    token: latencyTraceToken
                )
                guard attempt < traversalAttempts - 1 else {
                    return nil
                }
                // Let the Accessibility server process cold menu discovery before retrying.
                try? await Task.sleep(
                    nanoseconds: UInt64(commandVMenuTraversalRetryDelay * 1_000_000_000)
                )
                continue
            }
            let searchResult = plainCommandVMenuItem(in: menuBar)
            VoiceInkLatencyTrace.shared.event(
                "paste_command_v_menu_lookup",
                details: "attempt=\(attempt + 1) result=\(searchResult.menuItem == nil ? "missing" : "found") visited=\(searchResult.visitedNodes) enqueued=\(searchResult.enqueuedNodes) candidates=\(searchResult.shortcutCandidates) disabled=\(searchResult.disabledShortcutCandidates) limitExhausted=\(searchResult.limitExhausted) timeout=\(searchResult.timedOut)",
                token: latencyTraceToken
            )
            if let menuItem = searchResult.menuItem {
                // The app's plain Cmd-V command is target-affine, unlike a global key event.
                guard focusedProcessIdentifierForPaste() == processIdentifier else {
                    return nil
                }
                guard AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success else {
                    return nil
                }
                return processIdentifier
            }
            guard attempt < traversalAttempts - 1 else {
                return nil
            }
            // Let the Accessibility server process cold menu discovery before retrying.
            try? await Task.sleep(
                nanoseconds: UInt64(commandVMenuTraversalRetryDelay * 1_000_000_000)
            )
        }
        return nil
    }

    @MainActor
    static func postFocusedCommandVKeyEvents(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> CommandVKeyEventPostResult? {
        guard AXIsProcessTrusted(),
              let processIdentifier = focusedProcessIdentifierForPaste() else {
            return nil
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        let postResult = await postCommandVKeyEvents(
            processIdentifier: processIdentifier,
            eventDelay: targetKeyboardEventDelay,
            postTargetEvent: { event in
                VoiceInkPostTargetVirtualKey(
                    application,
                    event.virtualKey,
                    event.keyDown
                )
            },
            postReleaseFallback: { event in
                postTargetReleaseEvent(event, to: processIdentifier)
            }
        )
        let initialDetails = postResult.initialAttempts
            .map { "initial.\($0.event.rawValue)=\($0.result.rawValue)" }
            .joined(separator: " ")
        let cleanupDetails = postResult.cleanupAttempts
            .map { "cleanup.\($0.event.rawValue)=\($0.result.rawValue)" }
            .joined(separator: " ")
        let fallbackDetails = postResult.releaseFallbacks
            .map { "fallback.\($0.event.rawValue)=\($0.posted ? "posted" : "failed")" }
            .joined(separator: " ")
        VoiceInkLatencyTrace.shared.event(
            "paste_target_keyboard_events",
            details: "targetPid=\(processIdentifier) \(initialDetails) cleanup=\(cleanupDetails.isEmpty ? "none" : cleanupDetails) fallback=\(fallbackDetails.isEmpty ? "none" : fallbackDetails)",
            token: latencyTraceToken
        )
        return postResult
    }

    @MainActor
    static func postCommandVKeyEvents(
        processIdentifier: pid_t,
        eventDelay: TimeInterval,
        postTargetEvent: (CommandVKeyEvent) -> AXError,
        postReleaseFallback: (CommandVKeyEvent) -> Bool
    ) async -> CommandVKeyEventPostResult {
        var initialAttempts: [CommandVKeyEventAttempt] = []
        let commandDownResult = postTargetEvent(.commandDown)
        initialAttempts.append(CommandVKeyEventAttempt(
            event: .commandDown,
            result: commandDownResult
        ))

        let remainingEvents: [CommandVKeyEvent] = commandDownResult == .success
            ? [.vDown, .vUp, .commandUp]
            : [.vUp, .commandUp]
        for event in remainingEvents {
            await waitForTargetKeyboardEventDelay(eventDelay)
            initialAttempts.append(CommandVKeyEventAttempt(
                event: event,
                result: postTargetEvent(event)
            ))
        }

        let failedReleases = initialAttempts.filter {
            $0.event.isRelease && $0.result != .success
        }
        var cleanupAttempts: [CommandVKeyEventAttempt] = []
        for failedRelease in failedReleases {
            await waitForTargetKeyboardEventDelay(eventDelay)
            cleanupAttempts.append(CommandVKeyEventAttempt(
                event: failedRelease.event,
                result: postTargetEvent(failedRelease.event)
            ))
        }

        let hasUnresolvedRelease = cleanupAttempts.contains { $0.result != .success }
        let releaseFallbacks: [CommandVReleaseFallback] = hasUnresolvedRelease
            ? [CommandVKeyEvent.vUp, .commandUp].map { event in
                CommandVReleaseFallback(
                    event: event,
                    posted: postReleaseFallback(event)
                )
            }
            : []
        let completeEventSequence: [CommandVKeyEvent] = [
            .commandDown, .vDown, .vUp, .commandUp
        ]
        let commandPosted = initialAttempts.map(\.event) == completeEventSequence
            && initialAttempts.allSatisfy { $0.result == .success }
        return CommandVKeyEventPostResult(
            processIdentifier: processIdentifier,
            disposition: commandPosted ? .commandPosted : .deliveryUncertain,
            initialAttempts: initialAttempts,
            cleanupAttempts: cleanupAttempts,
            releaseFallbacks: releaseFallbacks
        )
    }

    private static func waitForTargetKeyboardEventDelay(_ delay: TimeInterval) async {
        guard delay > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private static func postTargetReleaseEvent(
        _ event: CommandVKeyEvent,
        to processIdentifier: pid_t
    ) -> Bool {
        guard event.isRelease,
              let keyboardEvent = CGEvent(
                  keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
                  virtualKey: event.virtualKey,
                  keyDown: false
              ) else {
            return false
        }
        if event == .vUp {
            keyboardEvent.flags = .maskCommand
        }
        keyboardEvent.postToPid(processIdentifier)
        return true
    }

    private struct CommandVMenuSearchResult {
        let menuItem: AXUIElement?
        let visitedNodes: Int
        let enqueuedNodes: Int
        let shortcutCandidates: Int
        let disabledShortcutCandidates: Int
        let limitExhausted: Bool
        let timedOut: Bool
    }

    private static func plainCommandVMenuItem(in menuBar: AXUIElement) -> CommandVMenuSearchResult {
        let deadline = Date().addingTimeInterval(commandVMenuTraversalTimeout)
        var queue = [menuBar]
        var index = 0
        var shortcutCandidates = 0
        var disabledShortcutCandidates = 0
        while index < queue.count,
              index < commandVMenuTraversalLimit,
              Date() < deadline {
            let element = queue[index]
            index += 1
            let elementRole = role(from: element)
            if elementRole == kAXMenuItemRole as String {
                let commandCharacter = stringAttribute(
                    kAXMenuItemCmdCharAttribute as CFString,
                    from: element
                )
                let virtualKey = numberAttribute(
                    kAXMenuItemCmdVirtualKeyAttribute as CFString,
                    from: element
                )?.intValue
                let modifiers = numberAttribute(
                    kAXMenuItemCmdModifiersAttribute as CFString,
                    from: element
                )?.uint32Value
                let enabled = numberAttribute(
                    kAXEnabledAttribute as CFString,
                    from: element
                )?.boolValue == true
                if isPlainCommandVShortcut(
                    commandCharacter: commandCharacter,
                    virtualKey: virtualKey,
                    modifiers: modifiers
                ) {
                    shortcutCandidates += 1
                    if enabled {
                        return CommandVMenuSearchResult(
                            menuItem: element,
                            visitedNodes: index,
                            enqueuedNodes: queue.count,
                            shortcutCandidates: shortcutCandidates,
                            disabledShortcutCandidates: disabledShortcutCandidates,
                            limitExhausted: false,
                            timedOut: false
                        )
                    }
                    disabledShortcutCandidates += 1
                }
            }

            let remainingCapacity = commandVMenuTraversalLimit - queue.count
            guard remainingCapacity > 0 else { continue }
            queue.append(contentsOf: childElements(from: element).prefix(remainingCapacity))
        }
        let hasUnvisitedNodes = index < queue.count
        return CommandVMenuSearchResult(
            menuItem: nil,
            visitedNodes: index,
            enqueuedNodes: queue.count,
            shortcutCandidates: shortcutCandidates,
            disabledShortcutCandidates: disabledShortcutCandidates,
            limitExhausted: hasUnvisitedNodes && index >= commandVMenuTraversalLimit,
            timedOut: hasUnvisitedNodes && Date() >= deadline
        )
    }

    static func isPlainCommandVMenuItem(
        commandCharacter: String?,
        virtualKey: Int?,
        modifiers: UInt32?,
        enabled: Bool
    ) -> Bool {
        enabled && isPlainCommandVShortcut(
            commandCharacter: commandCharacter,
            virtualKey: virtualKey,
            modifiers: modifiers
        )
    }

    static func isPlainCommandVShortcut(
        commandCharacter: String?,
        virtualKey: Int?,
        modifiers: UInt32?
    ) -> Bool {
        guard modifiers == 0 else { return false }
        return commandCharacter?.caseInsensitiveCompare("v") == .orderedSame
            || virtualKey == 0x09
    }

    @MainActor
    static func insertSelectedText(
        _ text: String,
        preparedContext: PreparedContext?
    ) -> SelectedTextInsertionResult {
        guard !text.isEmpty,
              AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()),
              let selectedRange = selectedTextRange(from: focusedElement),
              let role = role(from: focusedElement),
              VoiceInkCursorTextContextPolicy.isTextInputRole(role),
              shouldUseDirectAccessibilityInsertion(
                  ancestorRoles: insertionAncestorRoles(startingAt: focusedElement)
              ) else {
            return .unsupported
        }

        if let preparedContext {
            guard CFEqual(focusedElement, preparedContext.focusedElement),
                  sameRange(selectedRange, preparedContext.selectedRange) else {
                return .unsupported
            }
        }

        let textBeforeInsertion = textValue(from: focusedElement)
        let canSetSelectedText = isAttributeSettable(
            kAXSelectedTextAttribute as CFString,
            on: focusedElement
        )
        if canSetSelectedText,
           AXUIElementSetAttributeValue(
               focusedElement,
               kAXSelectedTextAttribute as CFString,
               text as CFString
           ) == .success {
            if insertionWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement),
                rangeAfterInsertion: selectedTextRange(from: focusedElement)
            ) {
                return .inserted
            }
            let textWasInsertedImmediately = replacementTextWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement)
            )

            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            if insertionWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement),
                rangeAfterInsertion: selectedTextRange(from: focusedElement)
            ) {
                return .inserted
            }
            if textWasInsertedImmediately || replacementTextWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement)
            ) {
                return .insertedWithoutSelection
            }
        }

        guard let textBeforeInsertion,
              textValue(from: focusedElement) == textBeforeInsertion,
              sameRange(selectedTextRange(from: focusedElement), selectedRange),
              let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text
              ),
              isAttributeSettable(kAXValueAttribute as CFString, on: focusedElement),
              setSelectedTextRange(selectedRange, on: focusedElement),
              AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                replacement.text as CFString
              ) == .success else {
            return canSetSelectedText ? .notApplied : .unsupported
        }

        if textValue(from: focusedElement) != replacement.text {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        guard textValue(from: focusedElement) == replacement.text else {
            return .notApplied
        }

        if valueReplacementWasObserved(
            text: replacement.text,
            selectedRange: replacement.selectedRange,
            textAfterInsertion: textValue(from: focusedElement),
            rangeAfterInsertion: selectedTextRange(from: focusedElement)
        ) || setSelectedTextRange(replacement.selectedRange, on: focusedElement) {
            return .insertedViaValue
        }

        // Text is already present. Never post a fallback paste that could duplicate it.
        return .insertedViaValueWithoutSelection
    }

    static func valueReplacement(
        textBeforeInsertion: String,
        rangeBeforeInsertion: CFRange,
        insertedText: String
    ) -> (text: String, selectedRange: CFRange)? {
        let source = textBeforeInsertion as NSString
        guard rangeBeforeInsertion.location >= 0,
              rangeBeforeInsertion.length >= 0,
              rangeBeforeInsertion.location <= source.length,
              rangeBeforeInsertion.length <= source.length - rangeBeforeInsertion.location else {
            return nil
        }

        return (
            source.replacingCharacters(
                in: NSRange(
                    location: rangeBeforeInsertion.location,
                    length: rangeBeforeInsertion.length
                ),
                with: insertedText
            ),
            CFRange(
                location: rangeBeforeInsertion.location + insertedText.utf16.count,
                length: 0
            )
        )
    }

    static func valueReplacementWasObserved(
        text: String,
        selectedRange: CFRange,
        textAfterInsertion: String?,
        rangeAfterInsertion: CFRange?
    ) -> Bool {
        textAfterInsertion == text && sameRange(rangeAfterInsertion, selectedRange)
    }

    static func insertionWasObserved(
        textBeforeInsertion: String?,
        rangeBeforeInsertion: CFRange,
        insertedText: String,
        textAfterInsertion: String?,
        rangeAfterInsertion: CFRange?
    ) -> Bool {
        if let textBeforeInsertion,
           let textAfterInsertion {
            guard let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: rangeBeforeInsertion,
                insertedText: insertedText
            ) else {
                return false
            }
            return valueReplacementWasObserved(
                text: replacement.text,
                selectedRange: replacement.selectedRange,
                textAfterInsertion: textAfterInsertion,
                rangeAfterInsertion: rangeAfterInsertion
            )
        }

        guard !insertedText.isEmpty,
              let rangeAfterInsertion else {
            return false
        }
        return rangeAfterInsertion.location
                == rangeBeforeInsertion.location + insertedText.utf16.count
            && rangeAfterInsertion.length == 0
    }

    static func replacementTextWasObserved(
        textBeforeInsertion: String?,
        rangeBeforeInsertion: CFRange,
        insertedText: String,
        textAfterInsertion: String?
    ) -> Bool {
        guard let textBeforeInsertion,
              let textAfterInsertion,
              let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: rangeBeforeInsertion,
                insertedText: insertedText
              ) else {
            return false
        }
        return textAfterInsertion == replacement.text
    }

    static func shouldUseDirectAccessibilityInsertion(ancestorRoles: [String]) -> Bool {
        // Web editors need Cmd-V so their DOM paste/input handlers update application state.
        !ancestorRoles.contains(webAreaRole)
    }

    private static func textBeforeCursor(in focusedElement: AXUIElement, maximumLength: Int) -> String? {
        let elements = contextCandidateElements(startingAt: focusedElement)

        for element in elements {
            guard let selectedRange = selectedTextRange(from: element),
                  let prefixLength = VoiceInkCursorTextContextPolicy.prefixLength(
                    cursorLocation: selectedRange.location,
                    maximumLength: maximumLength
                  ) else {
                continue
            }

            guard prefixLength > 0 else { return "" }

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

        for _ in 0..<VoiceInkCursorTextContextPolicy.parentTraversalLimit {
            guard let parent = parentElement(from: currentElement) else {
                break
            }

            elements.append(parent)
            currentElement = parent
        }

        return elements
    }

    private static func insertionAncestorRoles(startingAt element: AXUIElement) -> [String] {
        var roles: [String] = []
        var currentElement: AXUIElement? = element

        for _ in 0..<insertionAncestorTraversalLimit {
            guard let element = currentElement else { break }
            if let role = role(from: element) {
                roles.append(role)
            }
            currentElement = parentElement(from: element)
        }

        return roles
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

    private static func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func childElements(from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }

    private static func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func numberAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? NSNumber
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

    private static func setSelectedTextRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        guard isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: element) else {
            return false
        }

        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else {
            return false
        }
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success else {
            return false
        }
        if sameRange(selectedTextRange(from: element), range) {
            return true
        }

        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        return sameRange(selectedTextRange(from: element), range)
    }

    private static func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &isSettable) == .success
            && isSettable.boolValue
    }

    private static func sameRange(_ lhs: CFRange?, _ rhs: CFRange?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case (.some(let lhs), .some(let rhs)):
            lhs.location == rhs.location && lhs.length == rhs.length
        default:
            false
        }
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
        guard let text = textValue(from: element),
              let stringRange = Range(NSRange(location: range.location, length: range.length), in: text) else {
            return nil
        }

        return String(text[stringRange])
    }

    private static func valueSuffix(in element: AXUIElement, maximumLength: Int) -> String? {
        guard let role = role(from: element),
              VoiceInkCursorTextContextPolicy.isTextInputRole(role),
              let text = textValue(from: element) else {
            return nil
        }

        return VoiceInkCursorTextContextPolicy.valueSuffix(
            from: text,
            role: role,
            maximumLength: maximumLength
        )
    }

    private static func textValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
              let text = value as? String else {
            return nil
        }
        return text
    }

    private static func role(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success,
              let role = value as? String else {
            return nil
        }

        return role
    }
}
