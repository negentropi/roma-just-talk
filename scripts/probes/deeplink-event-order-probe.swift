#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

private struct Options {
    var logPath = "/tmp/voiceink-deeplink-order.log"
}

private var options = Options()
private var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--log":
        guard let path = args.first else {
            fputs("--log requires a path\n", stderr)
            exit(2)
        }
        options.logPath = path
        args.removeFirst()
    case "-h", "--help":
        print("Usage: deeplink-event-order-probe [--log PATH]")
        exit(0)
    default:
        fputs("Unknown argument: \(arg)\n", stderr)
        exit(2)
    }
}

private var logHandle: FileHandle?
private let logQueue = DispatchQueue(label: "voiceink.deeplink-order-probe.log")

private func wallTime() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSSSSS"
    return formatter.string(from: Date())
}

private func uptimeNanos() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
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

private func log(_ fields: [String]) {
    let line = ([
        wallTime(),
        "uptimeNs=\(uptimeNanos())"
    ] + fields).joined(separator: " ")

    logQueue.sync {
        print(line)
        fflush(stdout)
        if let data = (line + "\n").data(using: .utf8) {
            logHandle?.write(data)
        }
    }
}

final class URLHandler: NSObject {
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "<missing-url>"
        log(["event=deeplink", "url=\(url)"])
    }
}

private let cgTapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .flagsChanged:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 56 {
            log([
                "event=cg.flagsChanged",
                "key=left_shift",
                "keyCode=56",
                "flags=\(flagsSummary(event.flags))"
            ])
        }
    default:
        let systemDefinedRawValue = CGEventType.RawValue(NSEvent.EventType.systemDefined.rawValue)
        if type.rawValue == systemDefinedRawValue, let nsEvent = NSEvent(cgEvent: event) {
            log([
                "event=cg.systemDefined",
                "subtype=\(nsEvent.subtype.rawValue)",
                "data1=\(nsEvent.data1)",
                "data2=\(nsEvent.data2)",
                "flags=\(flagsSummary(event.flags))"
            ])
        }
    }
    return Unmanaged.passUnretained(event)
}

private func installCGTap() -> CFMachPort? {
    var mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    mask |= CGEventMask(1) << CGEventType.RawValue(NSEvent.EventType.systemDefined.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: cgTapCallback,
        userInfo: nil
    ) else {
        log(["event=tap.installFailed"])
        return nil
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log(["event=tap.installed"])
    return tap
}

FileManager.default.createFile(atPath: options.logPath, contents: nil)
logHandle = FileHandle(forWritingAtPath: options.logPath)

let handler = URLHandler()
NSAppleEventManager.shared().setEventHandler(
    handler,
    andSelector: #selector(URLHandler.handleGetURLEvent(_:withReplyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)

NSApplication.shared.setActivationPolicy(.accessory)
let tap = installCGTap()
log([
    "event=ready",
    "scheme=voiceink-event-order-probe",
    "log=\(options.logPath)",
    "listen=\(CGPreflightListenEventAccess())"
])

withExtendedLifetime((handler, tap)) {
    NSApplication.shared.run()
}
