import AppKit
import ApplicationServices
import Foundation

private struct HarnessConfig {
    var expectedText: String?
    var sampleCount = 5
    var trigger = Trigger.leftShift
    var thresholdMs = 440.0
    var bestMs = 220.0
    var timeoutMs = 5_000.0
    var pollMs = 10.0
    var jsonOutputPath: String?
}

private enum Trigger: Equatable {
    case anyKeyUp
    case keyCode(UInt16)
    case modifier(name: String, keyCode: UInt16, flag: CGEventFlags)

    static let leftShift = Trigger.modifier(name: "left-shift", keyCode: 56, flag: .maskShift)

    var description: String {
        switch self {
        case .anyKeyUp:
            return "any-key-up"
        case .keyCode(let keyCode):
            return "key-code:\(keyCode)"
        case .modifier(let name, _, _):
            return name
        }
    }

    func matchesRelease(type: CGEventType, event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch self {
        case .anyKeyUp:
            return type == .keyUp || isModifierRelease(type: type, event: event)
        case .keyCode(let keyCode):
            return type == .keyUp && eventKeyCode == keyCode
        case .modifier(_, let keyCode, let flag):
            return type == .flagsChanged && eventKeyCode == keyCode && !event.flags.contains(flag)
        }
    }

    private func isModifierRelease(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .flagsChanged else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case 54, 55:
            return !event.flags.contains(.maskCommand)
        case 56, 60:
            return !event.flags.contains(.maskShift)
        case 58, 61:
            return !event.flags.contains(.maskAlternate)
        case 59, 62:
            return !event.flags.contains(.maskControl)
        default:
            return false
        }
    }

    static func parse(_ rawValue: String) -> Trigger? {
        switch rawValue {
        case "any-key-up":
            return .anyKeyUp
        case "left-shift":
            return .modifier(name: rawValue, keyCode: 56, flag: .maskShift)
        case "right-shift":
            return .modifier(name: rawValue, keyCode: 60, flag: .maskShift)
        case "left-command":
            return .modifier(name: rawValue, keyCode: 55, flag: .maskCommand)
        case "right-command":
            return .modifier(name: rawValue, keyCode: 54, flag: .maskCommand)
        case "left-option":
            return .modifier(name: rawValue, keyCode: 58, flag: .maskAlternate)
        case "right-option":
            return .modifier(name: rawValue, keyCode: 61, flag: .maskAlternate)
        case "left-control":
            return .modifier(name: rawValue, keyCode: 59, flag: .maskControl)
        case "right-control":
            return .modifier(name: rawValue, keyCode: 62, flag: .maskControl)
        default:
            if rawValue.hasPrefix("key-code:"),
               let keyCode = UInt16(rawValue.dropFirst("key-code:".count)) {
                return .keyCode(keyCode)
            }
            return nil
        }
    }
}

private struct SampleResult: Encodable {
    let index: Int
    let status: String
    let latencyMs: Double?
    let baselineOccurrenceCount: Int
    let visibleOccurrenceCount: Int
    let focusedTextSource: String
    let focusedTextRole: String?
    let focusedTextError: String?
    let clipboardContainedExpectedText: Bool
}

private struct HarnessReport: Encodable {
    let expectedText: String
    let trigger: String
    let thresholdMs: Double
    let bestMs: Double
    let timeoutMs: Double
    let samples: [SampleResult]
    let passedCount: Int
    let missedCount: Int
    let p50Ms: Double?
    let p95Ms: Double?
    let maxMs: Double?
    let passed: Bool
}

private final class KeyReleaseWaiter {
    private let trigger: Trigger
    private var releaseTime: DispatchTime?

    init(trigger: Trigger) {
        self.trigger = trigger
    }

    func wait(timeoutMs: Double) -> DispatchTime? {
        let eventMask = (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("Could not create keyboard event tap. Grant Accessibility/Input Monitoring and retry.\n", stderr)
            return nil
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        let deadline = DispatchTime.now() + .milliseconds(Int(timeoutMs.rounded()))
        while releaseTime == nil && DispatchTime.now() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFMachPortInvalidate(eventTap)

        return releaseTime
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        guard releaseTime == nil, trigger.matchesRelease(type: type, event: event) else { return }
        releaseTime = .now()
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let waiter = Unmanaged<KeyReleaseWaiter>.fromOpaque(refcon).takeUnretainedValue()
    waiter.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private enum FocusedTextReader {
    struct Snapshot {
        let text: String?
        let source: String
        let role: String?
        let error: String?
    }

    static func text() -> String? {
        snapshot().text
    }

    static func snapshot() -> Snapshot {
        let systemWideElement = AXUIElementCreateSystemWide()
        var errors: [String] = []

        if let focusedElement = axElementAttribute(
            kAXFocusedUIElementAttribute,
            from: systemWideElement,
            source: "system",
            errors: &errors
        ) {
            return snapshot(for: focusedElement, source: "system.focusedUIElement")
        }

        if let focusedApplication = axElementAttribute(
            kAXFocusedApplicationAttribute,
            from: systemWideElement,
            source: "system",
            errors: &errors
        ) {
            if let focusedElement = axElementAttribute(
                kAXFocusedUIElementAttribute,
                from: focusedApplication,
                source: "focusedApplication",
                errors: &errors
            ) {
                return snapshot(for: focusedElement, source: "focusedApplication.focusedUIElement")
            }
        }

        return Snapshot(
            text: nil,
            source: "none",
            role: nil,
            error: errors.joined(separator: "; ")
        )
    }

    private static func axElementAttribute(
        _ attribute: String,
        from element: AXUIElement,
        source: String,
        errors: inout [String]
    ) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &focusedValue)
        guard result == .success else {
            errors.append("\(source).\(attribute) failed \(result.rawValue)")
            return nil
        }

        guard let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            errors.append("\(source).\(attribute) was not an AXUIElement")
            return nil
        }

        return (focusedValue as! AXUIElement)
    }

    private static func snapshot(for element: AXUIElement, source: String) -> Snapshot {
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let text = stringAttribute(kAXValueAttribute, from: element)
        return Snapshot(
            text: text,
            source: source,
            role: role,
            error: text == nil ? "\(source).\(kAXValueAttribute) unreadable" : nil
        )
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }
}

private enum AccessibilityTrust {
    static func isGranted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private enum Percentiles {
    static func value(_ percentile: Double, in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(ceil((percentile / 100.0) * Double(sorted.count))) - 1
        return sorted[max(0, min(index, sorted.count - 1))]
    }
}

private func parseArguments(_ arguments: [String]) throws -> HarnessConfig {
    var config = HarnessConfig()
    var index = 1

    func requireValue(after option: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw HarnessError.missingValue(option)
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let option = arguments[index]
        switch option {
        case "--expected":
            config.expectedText = try requireValue(after: option)
        case "--samples":
            config.sampleCount = try positiveInt(try requireValue(after: option), option: option)
        case "--trigger":
            let rawValue = try requireValue(after: option)
            guard let trigger = Trigger.parse(rawValue) else {
                throw HarnessError.invalidValue(option, rawValue)
            }
            config.trigger = trigger
        case "--threshold-ms":
            config.thresholdMs = try positiveDouble(try requireValue(after: option), option: option)
        case "--best-ms":
            config.bestMs = try positiveDouble(try requireValue(after: option), option: option)
        case "--timeout-ms":
            config.timeoutMs = try positiveDouble(try requireValue(after: option), option: option)
        case "--poll-ms":
            config.pollMs = try positiveDouble(try requireValue(after: option), option: option)
        case "--json-output":
            config.jsonOutputPath = try requireValue(after: option)
        case "--help", "-h":
            printUsageAndExit(0)
        default:
            throw HarnessError.unknownOption(option)
        }
        index += 1
    }

    guard config.expectedText?.isEmpty == false else {
        throw HarnessError.missingValue("--expected")
    }

    return config
}

private enum HarnessError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownOption(String)

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidValue(let option, let value):
            return "Invalid value for \(option): \(value)."
        case .unknownOption(let option):
            return "Unknown option: \(option)."
        }
    }
}

private func positiveInt(_ rawValue: String, option: String) throws -> Int {
    guard let value = Int(rawValue), value > 0 else {
        throw HarnessError.invalidValue(option, rawValue)
    }
    return value
}

private func positiveDouble(_ rawValue: String, option: String) throws -> Double {
    guard let value = Double(rawValue), value > 0 else {
        throw HarnessError.invalidValue(option, rawValue)
    }
    return value
}

private func clipboardContains(_ expectedText: String) -> Bool {
    NSPasteboard.general.string(forType: .string)?.contains(expectedText) == true
}

private struct VisibleTextObservation {
    let latencyMs: Double
    let occurrenceCount: Int
    let snapshot: FocusedTextReader.Snapshot
}

private func occurrenceCount(of needle: String, in haystack: String?) -> Int {
    guard let haystack, !needle.isEmpty else { return 0 }
    var count = 0
    var searchStart = haystack.startIndex
    while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
        count += 1
        searchStart = range.upperBound
    }
    return count
}

private func waitForVisibleText(
    expectedText: String,
    baselineOccurrenceCount: Int,
    releaseTime: DispatchTime,
    timeoutMs: Double,
    pollMs: Double
) -> VisibleTextObservation? {
    let deadline = DispatchTime.now() + .milliseconds(Int(timeoutMs.rounded()))
    while DispatchTime.now() < deadline {
        let snapshot = FocusedTextReader.snapshot()
        let occurrenceCount = occurrenceCount(of: expectedText, in: snapshot.text)
        if occurrenceCount > baselineOccurrenceCount {
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - releaseTime.uptimeNanoseconds
            return VisibleTextObservation(
                latencyMs: Double(elapsedNs) / 1_000_000.0,
                occurrenceCount: occurrenceCount,
                snapshot: snapshot
            )
        }
        Thread.sleep(forTimeInterval: pollMs / 1_000.0)
    }
    return nil
}

private func status(for latencyMs: Double?, thresholdMs: Double, bestMs: Double) -> String {
    guard let latencyMs else { return "missed" }
    if latencyMs <= bestMs { return "best" }
    if latencyMs <= thresholdMs { return "ok" }
    return "slow"
}

private func runHarness(config: HarnessConfig) -> HarnessReport {
    let expectedText = config.expectedText!
    var sampleResults: [SampleResult] = []

    print("Visible text latency harness")
    print("Expected text: \(expectedText)")
    print("Trigger release: \(config.trigger.description)")
    print("Threshold: \(Int(config.thresholdMs))ms, best target: \(Int(config.bestMs))ms")
    print("Focus the target text field, use Roma normally, and make the transcript include the expected text.")

    for sampleIndex in 1...config.sampleCount {
        print("")
        print("Sample \(sampleIndex)/\(config.sampleCount): waiting for trigger release...")
        let waiter = KeyReleaseWaiter(trigger: config.trigger)
        guard let releaseTime = waiter.wait(timeoutMs: config.timeoutMs) else {
            let clipboardHit = clipboardContains(expectedText)
            let snapshot = FocusedTextReader.snapshot()
            let visibleOccurrenceCount = occurrenceCount(of: expectedText, in: snapshot.text)
            sampleResults.append(SampleResult(
                index: sampleIndex,
                status: "no-trigger",
                latencyMs: nil,
                baselineOccurrenceCount: visibleOccurrenceCount,
                visibleOccurrenceCount: visibleOccurrenceCount,
                focusedTextSource: snapshot.source,
                focusedTextRole: snapshot.role,
                focusedTextError: snapshot.error,
                clipboardContainedExpectedText: clipboardHit
            ))
            print("FAIL no trigger release observed")
            continue
        }

        let baselineSnapshot = FocusedTextReader.snapshot()
        let baselineOccurrenceCount = occurrenceCount(of: expectedText, in: baselineSnapshot.text)
        if baselineOccurrenceCount > 0 {
            print("Focused text already contains \(baselineOccurrenceCount) occurrence(s) at release; waiting for a new occurrence.")
        } else if let error = baselineSnapshot.error {
            print("Focused text unreadable at release: \(error)")
        }
        let observation = waitForVisibleText(
            expectedText: expectedText,
            baselineOccurrenceCount: baselineOccurrenceCount,
            releaseTime: releaseTime,
            timeoutMs: config.timeoutMs,
            pollMs: config.pollMs
        )
        let latencyMs = observation?.latencyMs
        let clipboardHit = clipboardContains(expectedText)
        let finalSnapshot = observation?.snapshot ?? FocusedTextReader.snapshot()
        let visibleOccurrenceCount = observation?.occurrenceCount
            ?? occurrenceCount(of: expectedText, in: finalSnapshot.text)
        let sampleStatus: String
        if latencyMs == nil && finalSnapshot.text == nil {
            sampleStatus = "focused-text-unreadable"
        } else if latencyMs == nil && clipboardHit {
            sampleStatus = "clipboard-only"
        } else {
            sampleStatus = status(for: latencyMs, thresholdMs: config.thresholdMs, bestMs: config.bestMs)
        }
        sampleResults.append(SampleResult(
            index: sampleIndex,
            status: sampleStatus,
            latencyMs: latencyMs,
            baselineOccurrenceCount: baselineOccurrenceCount,
            visibleOccurrenceCount: visibleOccurrenceCount,
            focusedTextSource: finalSnapshot.source,
            focusedTextRole: finalSnapshot.role,
            focusedTextError: finalSnapshot.error,
            clipboardContainedExpectedText: clipboardHit
        ))

        if let latencyMs {
            print("\(sampleStatus.uppercased()) visible in \(String(format: "%.1f", latencyMs))ms")
        } else if clipboardHit {
            print("FAIL expected text reached clipboard but not focused text before timeout")
        } else {
            print("FAIL expected text did not appear before timeout")
        }
    }

    let measuredLatencies = sampleResults.compactMap(\.latencyMs)
    let p50 = Percentiles.value(50, in: measuredLatencies)
    let p95 = Percentiles.value(95, in: measuredLatencies)
    let maxValue = measuredLatencies.max()
    let missedCount = sampleResults.filter { $0.latencyMs == nil }.count
    let passed = missedCount == 0 && (p95 ?? .infinity) <= config.thresholdMs

    return HarnessReport(
        expectedText: expectedText,
        trigger: config.trigger.description,
        thresholdMs: config.thresholdMs,
        bestMs: config.bestMs,
        timeoutMs: config.timeoutMs,
        samples: sampleResults,
        passedCount: sampleResults.count - missedCount,
        missedCount: missedCount,
        p50Ms: p50,
        p95Ms: p95,
        maxMs: maxValue,
        passed: passed
    )
}

private func writeJSONReport(_ report: HarnessReport, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func printSummary(_ report: HarnessReport) {
    func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(String(format: "%.1f", value))ms"
    }

    print("")
    print("Summary")
    print("passed samples: \(report.passedCount)")
    print("missed samples: \(report.missedCount)")
    print("p50: \(format(report.p50Ms))")
    print("p95: \(format(report.p95Ms))")
    print("max: \(format(report.maxMs))")
    print(report.passed ? "PASS" : "FAIL")
}

private func printUsageAndExit(_ code: Int32) -> Never {
    print("""
    Usage:
      VisibleTextLatencyHarness --expected <text> [options]

    Options:
      --samples <n>          Samples to collect. Default: 5
      --trigger <trigger>    left-shift, right-shift, left-command, right-command,
                             left-option, right-option, left-control, right-control,
                             key-code:<n>, any-key-up. Default: left-shift
      --threshold-ms <ms>    Failing p95 threshold. Default: 440
      --best-ms <ms>         Best-case target label. Default: 220
      --timeout-ms <ms>      Per-sample trigger/text timeout. Default: 5000
      --poll-ms <ms>         Focused text polling interval. Default: 10
      --json-output <path>   Write a machine-readable report.

    Example:
      ./VisibleTextLatencyHarness --expected "roma latency marker" --samples 10 --trigger left-shift
    """)
    exit(code)
}

do {
    let config = try parseArguments(CommandLine.arguments)
    guard AccessibilityTrust.isGranted(prompt: true) else {
        fputs("Accessibility is not granted for this process. Grant the Terminal/iTerm app or the VisibleTextLatencyHarness helper app, then restart it.\n", stderr)
        exit(2)
    }

    let report = runHarness(config: config)
    printSummary(report)
    if let jsonOutputPath = config.jsonOutputPath {
        try writeJSONReport(report, path: jsonOutputPath)
        print("JSON report: \(jsonOutputPath)")
    }
    exit(report.passed ? 0 : 1)
} catch {
    fputs("\(error)\n\n", stderr)
    printUsageAndExit(2)
}
