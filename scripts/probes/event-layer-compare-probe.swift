#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

private struct Options {
    var forceSecureInput = false
    var logPath: String?
    var includeMouse = true
    var includeNSEventGlobal = true
    var includeIOHIDManager = true
    var includeIOHIDDevice = true
}

private let usage = """
Usage:
  swift scripts/probes/event-layer-compare-probe.swift [--secure] [--log PATH] [--no-mouse] [--no-nsevent-global] [--no-iohid-manager] [--no-iohid-device]

Compares input visibility across:
  - VI-CGSession: current VoiceInk-level cgSessionEventTap decoding
  - CGHID: lower cghidEventTap decoding
  - NSEventFromSessionCG / NSEventFromHIDCG: NSEvent conversion from each CG layer
  - NSEventGlobal: high-level global NSEvent monitor
  - IOHIDManager: manager-level IOHID input value callback
  - IOHIDDevice: per-device IOHID input value callback

The probe prints categories and keyCodes, not typed characters.
Press Ctrl-C to stop. If --secure was used, Ctrl-C disables Secure Event Input.
"""

private var options = Options()
private var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--secure":
        options.forceSecureInput = true
    case "--log":
        guard let path = args.first else {
            fputs("--log requires a path\n", stderr)
            exit(2)
        }
        options.logPath = path
        args.removeFirst()
    case "--no-mouse":
        options.includeMouse = false
    case "--no-nsevent-global":
        options.includeNSEventGlobal = false
    case "--no-iohid-manager":
        options.includeIOHIDManager = false
    case "--no-iohid-device":
        options.includeIOHIDDevice = false
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        fputs("Unknown argument: \(arg)\n\n\(usage)\n", stderr)
        exit(2)
    }
}

private let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
private let systemDefinedRawValue = UInt64(NSEvent.EventType.systemDefined.rawValue)
private let interestingStateCodes: [CGKeyCode] = [
    0, 1, 2, 3, 4, 5, 11, 12, 13, 38, 40, 45, 46, 49,
    54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    105, 106, 107, 108, 109, 110, 111
]

private var logHandle: FileHandle?
private var lastThrottledLog: [String: TimeInterval] = [:]
private var retainedHIDDevices: [IOHIDDevice] = []
private var didEnableSecureInput = false

private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

private func writeLine(_ line: String) {
    print(line)
    fflush(stdout)

    guard let logHandle else { return }
    if let data = (line + "\n").data(using: .utf8) {
        logHandle.write(data)
    }
}

private func flagsSummary(_ flags: CGEventFlags) -> String {
    var parts: [String] = []
    if flags.contains(.maskShift) { parts.append("shift") }
    if flags.contains(.maskControl) { parts.append("ctrl") }
    if flags.contains(.maskAlternate) { parts.append("opt") }
    if flags.contains(.maskCommand) { parts.append("cmd") }
    if flags.contains(.maskSecondaryFn) { parts.append("fn") }
    if flags.contains(.maskAlphaShift) { parts.append("caps") }
    return parts.isEmpty ? "none" : parts.joined(separator: ",")
}

private func nsFlagsSummary(_ flags: NSEvent.ModifierFlags) -> String {
    var parts: [String] = []
    if flags.contains(.shift) { parts.append("shift") }
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.option) { parts.append("opt") }
    if flags.contains(.command) { parts.append("cmd") }
    if flags.contains(.function) { parts.append("fn") }
    if flags.contains(.capsLock) { parts.append("caps") }
    return parts.isEmpty ? "none" : parts.joined(separator: ",")
}

private func keyClass(_ keyCode: Int64) -> String {
    if modifierKeyCodes.contains(keyCode) { return "modifier" }
    if keyCode == 49 { return "space" }
    if keyCode >= 105 && keyCode <= 111 { return "F\(keyCode - 92)" }
    return "nonmod"
}

private func hidUsageClass(page: UInt32, usage: UInt32) -> String {
    switch page {
    case 0x07:
        if usage >= 0xE0 && usage <= 0xE7 { return "modifier" }
        if usage == 0x2C { return "space" }
        if usage >= 0x04 && usage <= 0x1D { return "letter-key" }
        if usage >= 0x3A && usage <= 0x45 { return "function-key" }
        return "keyboard-non-letter"
    case 0x09:
        return "mouse-button"
    case 0x01:
        switch usage {
        case 0x30, 0x31:
            return "mouse-move"
        case 0x38:
            return "scroll"
        default:
            return "generic-desktop"
        }
    case 0x0C:
        return "consumer-control"
    default:
        return "hid-other"
    }
}

private func pressedStateSummary() -> String {
    let pressed = interestingStateCodes.filter {
        CGEventSource.keyState(.combinedSessionState, key: $0)
    }
    guard !pressed.isEmpty else { return "state=none" }
    return "state=" + pressed.map { "\($0):\(keyClass(Int64($0)))" }.joined(separator: ",")
}

private func emit(
    layer: String,
    event: String,
    keyCode: Int64? = nil,
    cls: String,
    flags: String = "n/a",
    hidPage: UInt32? = nil,
    hidUsage: UInt32? = nil,
    subtype: Int? = nil,
    data1: Int? = nil,
    data2: Int? = nil,
    value: Int? = nil,
    throttleMs: Double = 0
) {
    let now = Date().timeIntervalSince1970 * 1000
    let throttleKey = "\(layer)|\(event)|\(cls)|\(hidPage.map(String.init) ?? "")|\(hidUsage.map(String.init) ?? "")"
    if throttleMs > 0, let last = lastThrottledLog[throttleKey], now - last < throttleMs {
        return
    }
    lastThrottledLog[throttleKey] = now

    var fields = [
        timestamp(),
        "secure=\(IsSecureEventInputEnabled())",
        "layer=\(layer)",
        "event=\(event)",
        "class=\(cls)",
        "flags=\(flags)"
    ]
    if let keyCode { fields.append("keyCode=\(keyCode)") }
    if let hidPage { fields.append("hidPage=0x\(String(hidPage, radix: 16))") }
    if let hidUsage { fields.append("hidUsage=0x\(String(hidUsage, radix: 16))") }
    if let subtype { fields.append("subtype=\(subtype)") }
    if let data1 { fields.append("data1=\(data1)") }
    if let data2 { fields.append("data2=\(data2)") }
    if let value { fields.append("value=\(value)") }
    fields.append(pressedStateSummary())
    writeLine(fields.joined(separator: " "))
}

private func cgEventInfo(_ type: CGEventType, event: CGEvent) -> (
    event: String,
    keyCode: Int64?,
    cls: String,
    flags: String,
    throttleMs: Double
)? {
    if UInt64(type.rawValue) == systemDefinedRawValue {
        return ("systemDefined", nil, "system", flagsSummary(event.flags), 0)
    }

    let flags = flagsSummary(event.flags)
    switch type {
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return ("keyDown", keyCode, keyClass(keyCode), flags, 0)
    case .keyUp:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return ("keyUp", keyCode, keyClass(keyCode), flags, 0)
    case .flagsChanged:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return ("flagsChanged", keyCode, keyClass(keyCode), flags, 0)
    case .leftMouseDown:
        return ("mouseDown", nil, "left-button", flags, 0)
    case .leftMouseUp:
        return ("mouseUp", nil, "left-button", flags, 0)
    case .rightMouseDown:
        return ("mouseDown", nil, "right-button", flags, 0)
    case .rightMouseUp:
        return ("mouseUp", nil, "right-button", flags, 0)
    case .otherMouseDown:
        return ("mouseDown", nil, "other-button", flags, 0)
    case .otherMouseUp:
        return ("mouseUp", nil, "other-button", flags, 0)
    case .mouseMoved:
        return ("mouseMoved", nil, "mouse-move", flags, 900)
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        return ("mouseDragged", nil, "mouse-drag", flags, 900)
    case .scrollWheel:
        return ("scrollWheel", nil, "scroll", flags, 900)
    default:
        return nil
    }
}

private func emitNSEvent(layer: String, event: NSEvent) {
    let eventName: String
    switch event.type {
    case .keyDown:
        eventName = "keyDown"
    case .keyUp:
        eventName = "keyUp"
    case .flagsChanged:
        eventName = "flagsChanged"
    case .systemDefined:
        eventName = "systemDefined"
    default:
        return
    }

    if event.type == .systemDefined {
        emit(
            layer: layer,
            event: eventName,
            cls: "system",
            flags: nsFlagsSummary(event.modifierFlags),
            subtype: Int(event.subtype.rawValue),
            data1: event.data1,
            data2: event.data2
        )
        return
    }

    let keyCode = Int64(event.keyCode)
    emit(
        layer: layer,
        event: eventName,
        keyCode: keyCode,
        cls: keyClass(keyCode),
        flags: nsFlagsSummary(event.modifierFlags)
    )
}

private let cgTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let layer = userInfo.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "CG?"

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        emit(layer: layer, event: "tapDisabled", cls: "tap", flags: flagsSummary(event.flags))
        return Unmanaged.passUnretained(event)
    }

    if let info = cgEventInfo(type, event: event) {
        emit(
            layer: layer,
            event: info.event,
            keyCode: info.keyCode,
            cls: info.cls,
            flags: info.flags,
            throttleMs: info.throttleMs
        )
    }

    if let nsEvent = NSEvent(cgEvent: event) {
        switch layer {
        case "VI-CGSession":
            emitNSEvent(layer: "NSEventFromSessionCG", event: nsEvent)
        case "CGHID":
            emitNSEvent(layer: "NSEventFromHIDCG", event: nsEvent)
        default:
            break
        }
    }

    return Unmanaged.passUnretained(event)
}

private func unmanagedCString(_ text: String) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(strdup(text)!)
}

private func installCGTap(layer: String, tap: CGEventTapLocation) -> CFMachPort? {
    var eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    if options.includeMouse {
        eventTypes.append(contentsOf: [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel
        ])
    }

    var mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    mask |= CGEventMask(1) << CGEventType.RawValue(systemDefinedRawValue)

    guard let tapRef = CGEvent.tapCreate(
        tap: tap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: cgTapCallback,
        userInfo: unmanagedCString(layer)
    ) else {
        emit(layer: layer, event: "installFailed", cls: "tap")
        return nil
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapRef, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tapRef, enable: true)
    emit(layer: layer, event: "installed", cls: "tap")
    return tapRef
}

private func hidMatchingDictionaries() -> CFArray {
    let pairs: [[String: Any]] = [
        [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x06], // keyboard
        [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x07], // keypad
        [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x02], // mouse
        [kIOHIDDeviceUsagePageKey: 0x0C, kIOHIDDeviceUsageKey: 0x01]  // consumer control
    ]
    return pairs as CFArray
}

private func emitHIDValue(layer: String, value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    let cls = hidUsageClass(page: page, usage: usage)
    let event: String
    if cls == "mouse-move" || cls == "scroll" {
        event = intValue == 0 ? "change0" : "change"
    } else {
        event = intValue == 0 ? "up/value0" : "down/value"
    }
    let throttleMs = (cls == "mouse-move" || cls == "scroll") ? 900.0 : 0
    emit(
        layer: layer,
        event: event,
        cls: cls,
        hidPage: page,
        hidUsage: usage,
        value: intValue,
        throttleMs: throttleMs
    )
}

private let hidManagerValueCallback: IOHIDValueCallback = { _, _, _, value in
    emitHIDValue(layer: "IOHIDManager", value: value)
}

private let hidDeviceValueCallback: IOHIDValueCallback = { _, _, _, value in
    emitHIDValue(layer: "IOHIDDevice", value: value)
}

private let hidDeviceMatchingCallback: IOHIDDeviceCallback = { _, result, _, device in
    retainedHIDDevices.append(device)
    emit(layer: "IOHIDDevice", event: "matched", cls: "device", value: Int(result))
    IOHIDDeviceRegisterInputValueCallback(device, hidDeviceValueCallback, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    emit(layer: "IOHIDDevice", event: "open", cls: "device", value: Int(openResult))
}

private func installIOHID() -> IOHIDManager? {
    guard options.includeIOHIDManager || options.includeIOHIDDevice else { return nil }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatchingMultiple(manager, hidMatchingDictionaries())

    if options.includeIOHIDManager {
        IOHIDManagerRegisterInputValueCallback(manager, hidManagerValueCallback, nil)
    }

    if options.includeIOHIDDevice {
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchingCallback, nil)
    }

    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    emit(layer: "IOHIDManager", event: "open", cls: "manager", value: Int(openResult))
    return manager
}

private func cleanupAndExit(_ signal: Int32) -> Never {
    if didEnableSecureInput {
        DisableSecureEventInput()
        emit(layer: "SecureInput", event: "disabled", cls: "secure")
    }
    logHandle?.closeFile()
    exit(signal == SIGINT || signal == SIGTERM ? 0 : Int32(signal))
}

private let signalHandler: @convention(c) (Int32) -> Void = { signal in
    cleanupAndExit(signal)
}

signal(SIGINT, signalHandler)
signal(SIGTERM, signalHandler)

if let logPath = options.logPath {
    FileManager.default.createFile(atPath: logPath, contents: nil)
    logHandle = FileHandle(forWritingAtPath: logPath)
}

if options.forceSecureInput {
    let status = EnableSecureEventInput()
    didEnableSecureInput = status == noErr
    emit(layer: "SecureInput", event: "enabled", cls: "secure", value: Int(status))
}

let globalMonitor: Any?
if options.includeNSEventGlobal {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { event in
        emitNSEvent(layer: "NSEventGlobal", event: event)
    }
} else {
    globalMonitor = nil
}

writeLine("\(timestamp()) START ax=\(AXIsProcessTrusted()) listen=\(CGPreflightListenEventAccess()) secure=\(IsSecureEventInputEnabled())")
let sessionTap = installCGTap(layer: "VI-CGSession", tap: .cgSessionEventTap)
let hidTap = installCGTap(layer: "CGHID", tap: .cghidEventTap)
let hidManager = installIOHID()
writeLine("\(timestamp()) READY compare probe running; Ctrl-C to stop")

withExtendedLifetime((globalMonitor, sessionTap, hidTap, hidManager)) {
    CFRunLoopRun()
}
