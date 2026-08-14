import Foundation
import RuntimeE2ECore

private struct RuntimeHarnessArguments {
    var mode = "run"
    var configurationPath: String?
    var jsonOutputPath: String?
    var audioProbePath: String?

    static func parse(_ arguments: [String]) throws -> Self {
        var result = Self()
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--preflight":
                result.mode = "preflight"
            case "--target-probe":
                result.mode = "target-probe"
            case "--audio-probe":
                result.mode = "audio-probe"
                index += 1
                guard index < arguments.count else { throw RuntimeHarnessArgumentError.missingValue(argument) }
                result.audioProbePath = arguments[index]
            case "--restore":
                result.mode = "restore"
            case "--side-effect-restore-check":
                result.mode = "side-effect-restore-check"
            case "--config":
                index += 1
                guard index < arguments.count else { throw RuntimeHarnessArgumentError.missingValue(argument) }
                result.configurationPath = arguments[index]
            case "--json-output":
                index += 1
                guard index < arguments.count else { throw RuntimeHarnessArgumentError.missingValue(argument) }
                result.jsonOutputPath = arguments[index]
            case "--help", "-h":
                result.mode = "help"
            default:
                throw RuntimeHarnessArgumentError.unknownArgument(argument)
            }
            index += 1
        }
        return result
    }
}

private enum RuntimeHarnessArgumentError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case targetRestorationFailed([String])

    var description: String {
        switch self {
        case .missingValue(let argument):
            return "Missing value after \(argument)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .targetRestorationFailed(let runIDs):
            return "Unresolved target runs: \(runIDs.joined(separator: ", "))"
        }
    }
}

private func loadConfiguration(path: String?) throws -> RuntimeHarnessConfiguration {
    guard let path else { return .default }
    let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    return try JSONDecoder().decode(RuntimeHarnessConfiguration.self, from: Data(contentsOf: url))
}

private func writeJSON<T: Encodable>(_ value: T, path: String?) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let path {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try data.write(to: url, options: .atomic)
        print("JSON report: \(url.path)")
    } else if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

private func withRuntimeMutationLock<T>(_ body: () throws -> T) throws -> T {
    let mutationLock = try RuntimeHarnessMutationLock.acquire()
    defer { mutationLock.release() }
    return try body()
}

private func printUsage() {
    print("""
    Usage:
      RuntimeE2EHarness --preflight [--config PATH] [--json-output PATH]
      RuntimeE2EHarness --target-probe [--config PATH] [--json-output PATH]
      RuntimeE2EHarness --audio-probe WAV [--config PATH] [--json-output PATH]
      RuntimeE2EHarness --restore [--config PATH]
      RuntimeE2EHarness --side-effect-restore-check
      RuntimeE2EHarness --config PATH --json-output PATH

    A run without --config uses ~/Downloads/roma jt builds/audio, BlackHole 2ch,
    1.1 seconds of speech before key-down, and the five-app default matrix.
    """)
}

do {
    let arguments = try RuntimeHarnessArguments.parse(CommandLine.arguments)
    switch arguments.mode {
    case "help":
        printUsage()
        exit(0)
    case "preflight":
        let report = RuntimePreflight.run(
            configuration: try loadConfiguration(path: arguments.configurationPath),
            promptForAccessibility: true,
            requestScreenCaptureAccess: true
        )
        try writeJSON(report, path: arguments.jsonOutputPath)
        exit(report.passed ? 0 : 2)
    case "target-probe":
        let report = try withRuntimeMutationLock {
            RuntimeTargetProbe.run(
                configuration: try loadConfiguration(path: arguments.configurationPath)
            )
        }
        try writeJSON(report, path: arguments.jsonOutputPath)
        exit(report.passed ? 0 : 2)
    case "audio-probe":
        let configuration = try loadConfiguration(path: arguments.configurationPath)
        let devices = try RuntimeAudioDeviceCatalog.devices()
        guard let device = devices.first(where: {
            $0.name.localizedCaseInsensitiveCompare(configuration.audioDeviceName) == .orderedSame
        }) else {
            throw RuntimeAudioPlaybackError.audioDeviceNotFound
        }
        guard let audioProbePath = arguments.audioProbePath else {
            throw RuntimeHarnessArgumentError.missingValue("--audio-probe")
        }
        let fixtureURL = URL(fileURLWithPath: NSString(string: audioProbePath).expandingTildeInPath)
        guard let fixtureInfo = RuntimePreflight.run(configuration: configuration).audioFixtures.first(where: {
            $0.path == fixtureURL.path
        }), let durationSeconds = fixtureInfo.durationSeconds else {
            throw RuntimeAudioPlaybackError.notStarted
        }
        let report: RuntimeAudioThroughVoiceInkProbeReport = try withRuntimeMutationLock {
            _ = try RuntimeRestorationCoordinator.restorePendingRun()
            let restorationScope = try RuntimeRestorationScope.create()
            defer { try? restorationScope.finish() }
            let outputSession = try RuntimeSystemOutputSession.start(
                targetDevice: device,
                restorationScope: restorationScope
            )
            var voiceInkSession: RuntimeVoiceInkSession?
            do {
                let session = try RuntimeVoiceInkSession.start(
                    configuration: configuration,
                    audioDeviceUID: device.uid,
                    restorationScope: restorationScope
                )
                voiceInkSession = session
                Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)
                let playback = RuntimeAudioPlayback(
                    fixtureURL: fixtureURL,
                    device: device,
                    expectedDurationSeconds: durationSeconds
                )
                _ = try playback.start()
                let result = try playback.waitUntilFinished()
                try session.restore()
                try outputSession.restore()
                try restorationScope.finish()
                return RuntimeAudioThroughVoiceInkProbeReport(
                    voiceInkSession: session.info,
                    playback: result,
                    restoredOriginalState: true
                )
            } catch {
                try? voiceInkSession?.restore()
                try? outputSession.restore()
                throw error
            }
        }
        try writeJSON(report, path: arguments.jsonOutputPath)
        exit(0)
    case "restore":
        let configuration = try loadConfiguration(path: arguments.configurationPath)
        let restored: [String] = try withRuntimeMutationLock {
            var restored = try RuntimeRestorationCoordinator.restorePendingRun()
            let targetCleanup = RuntimeTargetController.restoreAbandonedTargets(
                targets: RuntimeTargetCatalog.restorationTargets(
                    configuredTargets: configuration.targets
                )
            )
            if targetCleanup.discoveredResources > 0 {
                restored.append(
                    "\(targetCleanup.removedResources) abandoned target resources"
                )
            }
            guard targetCleanup.passed else {
                throw RuntimeHarnessArgumentError.targetRestorationFailed(
                    targetCleanup.unresolvedRunIDs
                )
            }
            return restored
        }
        print(restored.isEmpty ? "No pending runtime-harness restoration" : "Restored " + restored.joined(separator: " and "))
        exit(0)
    case "side-effect-restore-check":
        try RuntimeFalseTriggerSideEffectObserver.verifyRestoration()
        try RuntimeRestorationScope.verifyIsolation()
        try RuntimeHarnessMutationLock.verifyExclusivity()
        print("PASS false-trigger restoration is targeted and state-mutating runs are exclusive")
        exit(0)
    default:
        let configuration = try loadConfiguration(path: arguments.configurationPath)
        let reportPath = arguments.jsonOutputPath
            ?? "/tmp/roma-runtime-e2e-report.json"
        let reportURL = URL(fileURLWithPath: NSString(string: reportPath).expandingTildeInPath)
        let report = try RuntimeHarnessRunner.run(
            configuration: configuration,
            reportURL: reportURL
        )
        print("JSON report: \(reportURL.path)")
        exit(report.summary.passed ? 0 : 1)
    }
} catch {
    fputs("\(error)\n", stderr)
    printUsage()
    exit(2)
}
