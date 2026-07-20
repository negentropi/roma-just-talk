import AppKit
import Foundation
import RuntimeE2ECore

enum RuntimeFailureBoundary: String, Codable {
    case none
    case targetPreparation
    case audioInjection
    case shortcutInjection
    case traceCollection
    case voiceInkTrigger
    case voiceInkTranscription
    case voiceInkPasteHandoff
    case pasteDeliveryOrTargetVisibility
    case latencyBudget
    case contentQuality
    case targetCleanup
}

struct RuntimeCaseEvidence: Codable {
    let targetPrepared: Bool
    let audioPlaybackStarted: Bool
    let shortcutDownPosted: Bool
    let shortcutUpPosted: Bool
    let emergencyShortcutReleasePosted: Bool
    let voiceInkTriggerObserved: Bool
    let voiceInkTranscriptionCompleted: Bool
    let voiceInkClipboardWriteSucceeded: Bool
    let voiceInkPasteEventPosted: Bool
    let systemClipboardChangeObserved: Bool
    let targetVisibleTextObserved: Bool
    let targetCleanupPassed: Bool?
}

struct RuntimeCaseReport: Codable {
    let id: String
    let fixturePath: String
    let expectedTranscript: String?
    let target: RuntimeTargetApp
    let repetition: Int
    let startedAt: Date
    let finishedAt: Date
    let timingPlan: RuntimeTimingPlan?
    let targetPreparation: RuntimeTargetPreparationInfo?
    let audioPlayback: RuntimeAudioPlaybackResult?
    let shortcutDown: RuntimeShortcutEventResult?
    let shortcutUp: RuntimeShortcutEventResult?
    let actualAudioLeadMilliseconds: Double?
    let actualHoldMilliseconds: Double?
    let voiceInkKeyUpToPasteEventMilliseconds: Double?
    let pasteEventToVisibleMilliseconds: Double?
    let visibleText: RuntimeVisibleTextResult?
    let clipboardChanged: Bool
    let latencyTrace: RuntimeLatencyTrace?
    let evidence: RuntimeCaseEvidence
    let failureBoundary: RuntimeFailureBoundary
    let targetCleanup: RuntimeTargetCleanupInfo?
    let assessment: RuntimeCaseAssessment
    let error: String?
}

struct RuntimeAppSummary: Codable {
    let targetID: String
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let noPasteCases: Int
    let p50VisibleMilliseconds: Double?
    let p95VisibleMilliseconds: Double?
    let maxVisibleMilliseconds: Double?
}

struct RuntimeRunSummary: Codable {
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let noPasteCases: Int
    let p50VisibleMilliseconds: Double?
    let p95VisibleMilliseconds: Double?
    let maxVisibleMilliseconds: Double?
    let apps: [RuntimeAppSummary]
    let passed: Bool
}

struct RuntimeHarnessReport: Codable {
    var schemaVersion = 1
    let startedAt: Date
    var finishedAt: Date?
    let configuration: RuntimeHarnessConfiguration
    let preflight: RuntimePreflightReport
    var abandonedTargetCleanup: RuntimeAbandonedTargetCleanupInfo?
    var voiceInkSession: RuntimeVoiceInkSessionInfo?
    var cases: [RuntimeCaseReport]
    var summary: RuntimeRunSummary
    var restoredOriginalState: Bool
    var fatalError: String?
}

enum RuntimeHarnessRunner {
    static func run(
        configuration: RuntimeHarnessConfiguration,
        reportURL: URL
    ) throws -> RuntimeHarnessReport {
        let preflight = RuntimePreflight.run(configuration: configuration)
        guard preflight.passed else {
            var report = RuntimeHarnessReport(
                startedAt: Date(),
                finishedAt: Date(),
                configuration: configuration,
                preflight: preflight,
                abandonedTargetCleanup: nil,
                voiceInkSession: nil,
                cases: [],
                summary: summarize(cases: []),
                restoredOriginalState: true,
                fatalError: preflight.failures.joined(separator: "; ")
            )
            try write(report: report, to: reportURL)
            report.summary = summarize(cases: report.cases)
            return report
        }

        guard let audioDevice = preflight.requestedAudioDevice else {
            throw RuntimeAudioPlaybackError.audioDeviceNotFound
        }
        let fixtureURLs = preflight.audioFixtures.map { URL(fileURLWithPath: $0.path) }
        let selectedTargetIDs = Set(preflight.selectedTargetIDs)
        let selectedTargets = configuration.targets.filter { selectedTargetIDs.contains($0.id) }
        let runPlan = try RuntimeRunPlan.make(
            fixtureURLs: fixtureURLs,
            expectedTranscripts: configuration.expectedTranscripts,
            targets: selectedTargets,
            repetitions: configuration.repetitions
        )
        let fixtureDurations = Dictionary(
            uniqueKeysWithValues: preflight.audioFixtures.compactMap { fixture in
                fixture.durationSeconds.map { (fixture.path, $0) }
            }
        )

        var report = RuntimeHarnessReport(
            startedAt: Date(),
            finishedAt: nil,
            configuration: configuration,
            preflight: preflight,
            abandonedTargetCleanup: nil,
            voiceInkSession: nil,
            cases: [],
            summary: summarize(cases: []),
            restoredOriginalState: false,
            fatalError: nil
        )
        try write(report: report, to: reportURL)

        let abandonedTargetCleanup = RuntimeTargetController.restoreAbandonedTargets(
            targets: RuntimeTargetCatalog.restorationTargets(
                configuredTargets: configuration.targets
            )
        )
        report.abandonedTargetCleanup = abandonedTargetCleanup
        if !abandonedTargetCleanup.passed {
            report.finishedAt = Date()
            report.restoredOriginalState = true
            report.fatalError = "Could not restore abandoned runtime target surfaces"
            try write(report: report, to: reportURL)
            return report
        }
        try write(report: report, to: reportURL)

        let outputSession = try RuntimeSystemOutputSession.start(targetDevice: audioDevice)
        var voiceInkSession: RuntimeVoiceInkSession?
        do {
            let session = try RuntimeVoiceInkSession.start(
                configuration: configuration,
                audioDeviceUID: audioDevice.uid
            )
            voiceInkSession = session
            report.voiceInkSession = session.info
            Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)

            var seenTraceIDs = Set((try? RuntimeLatencyLogReader.recent().traces.map(\.traceID)) ?? [])
            var previousFixturePath: String?
            for (caseIndex, runCase) in runPlan.cases.enumerated() {
                if shouldRelaunchVoiceInk(
                    lifecycle: configuration.voiceInkLifecycle,
                    previousFixturePath: previousFixturePath,
                    currentFixturePath: runCase.fixtureURL.path,
                    caseIndex: caseIndex
                ) {
                    try session.relaunchForRun(bundleIdentifier: configuration.voiceInkBundleIdentifier)
                    Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)
                }
                previousFixturePath = runCase.fixtureURL.path

                let caseReport = executeCase(
                    runCase,
                    configuration: configuration,
                    audioDevice: audioDevice,
                    fixtureDurationSeconds: fixtureDurations[runCase.fixtureURL.path],
                    seenTraceIDs: &seenTraceIDs
                )
                report.cases.append(caseReport)
                report.summary = summarize(cases: report.cases)
                try write(report: report, to: reportURL)
                printCaseProgress(caseReport, index: caseIndex + 1, total: runPlan.cases.count)
            }

            try session.restore()
            try outputSession.restore()
            report.restoredOriginalState = true
            report.finishedAt = Date()
            report.summary = summarize(cases: report.cases)
            try write(report: report, to: reportURL)
            return report
        } catch {
            try? voiceInkSession?.restore()
            try? outputSession.restore()
            report.restoredOriginalState = true
            report.finishedAt = Date()
            report.fatalError = String(describing: error)
            report.summary = summarize(cases: report.cases)
            try? write(report: report, to: reportURL)
            throw error
        }
    }

    private static func executeCase(
        _ runCase: RuntimeRunCase,
        configuration: RuntimeHarnessConfiguration,
        audioDevice: RuntimeAudioDevice,
        fixtureDurationSeconds: TimeInterval?,
        seenTraceIDs: inout Set<String>
    ) -> RuntimeCaseReport {
        let startedAt = Date()
        let runID = makeRunID(runCase)
        var phase = "target"
        var preparedTarget: RuntimePreparedTarget?
        var playback: RuntimeAudioPlayback?
        var timingPlan: RuntimeTimingPlan?
        var audioResult: RuntimeAudioPlaybackResult?
        var shortcutDown: RuntimeShortcutEventResult?
        var shortcutUp: RuntimeShortcutEventResult?
        var visibleText: RuntimeVisibleTextResult?
        var latencyTrace: RuntimeLatencyTrace?
        var clipboardChanged = false
        var audioPlaybackStarted = false
        var emergencyShortcutReleasePosted = false
        var assessment = RuntimeCaseAssessment(status: .targetSetupFailed, passed: false)
        var errorText: String?

        do {
            guard let fixtureDurationSeconds else {
                throw RuntimeHarnessRunError.fixtureDurationMissing(runCase.fixtureURL.path)
            }
            let plan = try timingPlanForCase(
                fixtureDurationSeconds: fixtureDurationSeconds,
                configuration: configuration
            )
            timingPlan = plan
            let target = try RuntimeTargetController.prepare(
                target: runCase.target,
                runID: runID,
                settleSeconds: configuration.targetSettleSeconds,
                availabilityPolicy: configuration.targetAvailabilityPolicy
            )
            preparedTarget = target

            phase = "audio"
            let audio = RuntimeAudioPlayback(
                fixtureURL: runCase.fixtureURL,
                device: audioDevice,
                expectedDurationSeconds: fixtureDurationSeconds
            )
            playback = audio
            let clipboardChangeCount = NSPasteboard.general.changeCount
            let audioStartedAt = try audio.start()
            audioPlaybackStarted = true

            phase = "shortcut"
            waitUntilSystemUptime(audioStartedAt + plan.keyDownOffsetSeconds)
            let down = try RuntimeShortcutInjector.postLeftShiftDown()
            shortcutDown = down
            waitUntilSystemUptime(audioStartedAt + plan.keyUpOffsetSeconds)
            let up = try RuntimeShortcutInjector.postLeftShiftUp()
            shortcutUp = up

            phase = "observation"
            visibleText = target.waitForVisibleText(
                keyUpAtSystemUptime: up.postedAtSystemUptime,
                timeoutSeconds: configuration.targetTextTimeoutSeconds
            )
            audioResult = try audio.waitUntilFinished()
            clipboardChanged = NSPasteboard.general.changeCount != clipboardChangeCount

            Thread.sleep(forTimeInterval: 0.35)
            let logSnapshot = try RuntimeLatencyLogReader.recent()
            let newTraces = logSnapshot.traces.filter { !seenTraceIDs.contains($0.traceID) }
            seenTraceIDs.formUnion(logSnapshot.traces.map(\.traceID))
            latencyTrace = newTraces.last(where: \.triggerObserved)

            let observation = RuntimeCaseObservation(
                visibleText: visibleText?.text,
                keyUpToVisibleMilliseconds: visibleText?.keyUpToVisibleMilliseconds,
                clipboardChanged: clipboardChanged,
                triggerObserved: latencyTrace?.triggerObserved == true
            )
            assessment = RuntimeCaseAssessment.assess(
                observation: observation,
                expectedTranscript: runCase.expectedTranscript,
                latencyThresholdMilliseconds: configuration.latencyThresholdMilliseconds,
                maximumWordErrorRate: configuration.maximumWordErrorRate
            )
            if latencyTrace == nil,
               visibleText?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                assessment = RuntimeCaseAssessment(status: .traceMissing, passed: false)
            }
        } catch {
            errorText = String(describing: error)
            assessment = RuntimeCaseAssessment(
                status: failureStatus(for: phase),
                passed: false
            )
        }

        if shortcutDown != nil, shortcutUp == nil,
           let emergencyUp = try? RuntimeShortcutInjector.postLeftShiftUp() {
            shortcutUp = emergencyUp
            emergencyShortcutReleasePosted = true
        }
        playback?.stop()
        let targetCleanup = preparedTarget?.cleanup()
        if let targetCleanup, !targetCleanup.passed {
            let cleanupError = targetCleanup.errors.joined(separator: "; ")
            errorText = [errorText, cleanupError]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            if assessment.passed {
                assessment = RuntimeCaseAssessment(status: .targetCleanupFailed, passed: false)
            }
        }

        let targetVisibleTextObserved = visibleText?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let evidence = RuntimeCaseEvidence(
            targetPrepared: preparedTarget != nil,
            audioPlaybackStarted: audioPlaybackStarted,
            shortcutDownPosted: shortcutDown != nil,
            shortcutUpPosted: shortcutUp != nil,
            emergencyShortcutReleasePosted: emergencyShortcutReleasePosted,
            voiceInkTriggerObserved: latencyTrace?.triggerObserved == true,
            voiceInkTranscriptionCompleted: latencyTrace?.transcriptionCompleted == true,
            voiceInkClipboardWriteSucceeded: latencyTrace?.clipboardWriteSucceeded == true,
            voiceInkPasteEventPosted: latencyTrace?.pasteEventPosted == true,
            systemClipboardChangeObserved: clipboardChanged,
            targetVisibleTextObserved: targetVisibleTextObserved,
            targetCleanupPassed: targetCleanup?.passed
        )
        let failureBoundary = failureBoundary(
            assessment: assessment,
            evidence: evidence,
            latencyTrace: latencyTrace
        )
        let voiceInkKeyUpToPasteEventMilliseconds = latencyTrace?.keyUpToPasteEventMilliseconds
        let pasteEventToVisibleMilliseconds = visibleText?.keyUpToVisibleMilliseconds.flatMap { visible in
            voiceInkKeyUpToPasteEventMilliseconds.map { max(0, visible - $0) }
        }
        return RuntimeCaseReport(
            id: runID,
            fixturePath: runCase.fixtureURL.path,
            expectedTranscript: runCase.expectedTranscript,
            target: runCase.target,
            repetition: runCase.repetition,
            startedAt: startedAt,
            finishedAt: Date(),
            timingPlan: timingPlan,
            targetPreparation: preparedTarget?.info,
            audioPlayback: audioResult,
            shortcutDown: shortcutDown,
            shortcutUp: shortcutUp,
            actualAudioLeadMilliseconds: shortcutDown.map { down in
                audioResult.map { (down.postedAtSystemUptime - $0.startedAtSystemUptime) * 1_000 }
            } ?? nil,
            actualHoldMilliseconds: shortcutDown.flatMap { down in
                shortcutUp.map { ($0.postedAtSystemUptime - down.postedAtSystemUptime) * 1_000 }
            },
            voiceInkKeyUpToPasteEventMilliseconds: voiceInkKeyUpToPasteEventMilliseconds,
            pasteEventToVisibleMilliseconds: pasteEventToVisibleMilliseconds,
            visibleText: visibleText,
            clipboardChanged: clipboardChanged,
            latencyTrace: latencyTrace,
            evidence: evidence,
            failureBoundary: failureBoundary,
            targetCleanup: targetCleanup,
            assessment: assessment,
            error: errorText
        )
    }

    private static func timingPlanForCase(
        fixtureDurationSeconds: TimeInterval,
        configuration: RuntimeHarnessConfiguration
    ) throws -> RuntimeTimingPlan {
        if let holdSeconds = configuration.explicitHoldSeconds {
            return try RuntimeTimingPlan(
                audioDurationSeconds: configuration.audioLeadSeconds + holdSeconds,
                audioLeadSeconds: configuration.audioLeadSeconds,
                releaseTailSeconds: 0
            )
        }
        return try RuntimeTimingPlan(
            audioDurationSeconds: fixtureDurationSeconds,
            audioLeadSeconds: configuration.audioLeadSeconds,
            releaseTailSeconds: configuration.releaseTailSeconds
        )
    }

    private static func shouldRelaunchVoiceInk(
        lifecycle: RuntimeHarnessConfiguration.VoiceInkLifecycle,
        previousFixturePath: String?,
        currentFixturePath: String,
        caseIndex: Int
    ) -> Bool {
        switch lifecycle {
        case .reuse:
            return false
        case .relaunchPerFixture:
            return caseIndex > 0 && previousFixturePath != currentFixturePath
        case .relaunchPerCase:
            return caseIndex > 0
        }
    }

    private static func failureStatus(for phase: String) -> RuntimeCaseAssessment.Status {
        switch phase {
        case "target": return .targetSetupFailed
        case "audio": return .audioFailed
        case "shortcut": return .shortcutFailed
        default: return .traceMissing
        }
    }

    private static func failureBoundary(
        assessment: RuntimeCaseAssessment,
        evidence: RuntimeCaseEvidence,
        latencyTrace: RuntimeLatencyTrace?
    ) -> RuntimeFailureBoundary {
        guard evidence.targetPrepared else { return .targetPreparation }
        guard evidence.audioPlaybackStarted else { return .audioInjection }
        guard evidence.shortcutDownPosted, evidence.shortcutUpPosted else { return .shortcutInjection }
        guard latencyTrace != nil else { return .traceCollection }
        guard evidence.voiceInkTriggerObserved else { return .voiceInkTrigger }
        guard evidence.voiceInkTranscriptionCompleted else { return .voiceInkTranscription }
        guard evidence.voiceInkClipboardWriteSucceeded,
              evidence.voiceInkPasteEventPosted else {
            return .voiceInkPasteHandoff
        }
        guard evidence.targetVisibleTextObserved else { return .pasteDeliveryOrTargetVisibility }
        if assessment.status == .slow { return .latencyBudget }
        if assessment.status == .contentMismatch { return .contentQuality }
        if evidence.targetCleanupPassed == false { return .targetCleanup }
        return .none
    }

    private static func makeRunID(_ runCase: RuntimeRunCase) -> String {
        let fixture = runCase.fixtureURL.deletingPathExtension().lastPathComponent
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(fixture).replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        return "\(collapsed)-\(runCase.target.id)-r\(runCase.repetition)-\(UUID().uuidString.prefix(6))"
    }

    private static func waitUntilSystemUptime(_ target: TimeInterval) {
        while true {
            let remaining = target - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(remaining, 0.005))
        }
    }

    private static func summarize(cases: [RuntimeCaseReport]) -> RuntimeRunSummary {
        let latencies = cases.compactMap(\.visibleText?.keyUpToVisibleMilliseconds)
        let appSummaries = Dictionary(grouping: cases, by: { $0.target.id })
            .map { targetID, appCases -> RuntimeAppSummary in
                let appLatencies = appCases.compactMap(\.visibleText?.keyUpToVisibleMilliseconds)
                let passed = appCases.filter(\.assessment.passed).count
                return RuntimeAppSummary(
                    targetID: targetID,
                    totalCases: appCases.count,
                    passedCases: passed,
                    failedCases: appCases.count - passed,
                    noPasteCases: appCases.filter { isVisiblePasteFailure($0.assessment.status) }.count,
                    p50VisibleMilliseconds: RuntimeStatistics.percentile(50, values: appLatencies),
                    p95VisibleMilliseconds: RuntimeStatistics.percentile(95, values: appLatencies),
                    maxVisibleMilliseconds: appLatencies.max()
                )
            }
            .sorted { $0.targetID < $1.targetID }
        let passed = cases.filter(\.assessment.passed).count
        return RuntimeRunSummary(
            totalCases: cases.count,
            passedCases: passed,
            failedCases: cases.count - passed,
            noPasteCases: cases.filter { isVisiblePasteFailure($0.assessment.status) }.count,
            p50VisibleMilliseconds: RuntimeStatistics.percentile(50, values: latencies),
            p95VisibleMilliseconds: RuntimeStatistics.percentile(95, values: latencies),
            maxVisibleMilliseconds: latencies.max(),
            apps: appSummaries,
            passed: !cases.isEmpty && passed == cases.count
        )
    }

    private static func isVisiblePasteFailure(_ status: RuntimeCaseAssessment.Status) -> Bool {
        status == .noPaste || status == .clipboardOnly
    }

    private static func write(report: RuntimeHarnessReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static func printCaseProgress(
        _ report: RuntimeCaseReport,
        index: Int,
        total: Int
    ) {
        let latency = report.visibleText?.keyUpToVisibleMilliseconds.map {
            String(format: "%.1fms", $0)
        } ?? "n/a"
        print(
            "[\(index)/\(total)] \(report.target.displayName) | "
            + "\(URL(fileURLWithPath: report.fixturePath).lastPathComponent) | "
            + "\(report.assessment.status.rawValue) | \(latency) | "
            + "boundary=\(report.failureBoundary.rawValue)"
        )
    }
}

enum RuntimeHarnessRunError: Error, CustomStringConvertible {
    case fixtureDurationMissing(String)

    var description: String {
        switch self {
        case .fixtureDurationMissing(let path):
            return "Fixture duration is unavailable: \(path)"
        }
    }
}
