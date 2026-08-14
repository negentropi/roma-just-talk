import AppKit
import ApplicationServices
import Foundation
import RuntimeE2ECore

struct RuntimeRecordingFileFingerprint: Codable, Equatable {
    let name: String
    let size: UInt64
    let modifiedAt: Date?
}

struct RuntimeFalseTriggerSideEffectSnapshot: Codable, Equatable {
    let recordingsDirectoryPath: String
    let recordingsDirectoryExisted: Bool
    let recordingFiles: [RuntimeRecordingFileFingerprint]
    let historyStorePath: String
    let historyStoreExisted: Bool
    let transcriptionCount: Int?
    let transcriptionRowIDs: [Int]?
    let transcriptionPrimaryKeyMaximum: Int?
    let errors: [String]

    var observationSucceeded: Bool {
        errors.isEmpty && transcriptionCount != nil && transcriptionRowIDs != nil
    }
}

struct RuntimeFalseTriggerSideEffectRestoration: Codable {
    let attempted: Bool
    let removedRecordingFiles: [String]
    let removedTranscriptionRowIDs: [Int]
    let stateMatchesBaseline: Bool
    let passed: Bool
    let errors: [String]

    static let notNeeded = Self(
        attempted: false,
        removedRecordingFiles: [],
        removedTranscriptionRowIDs: [],
        stateMatchesBaseline: true,
        passed: true,
        errors: []
    )
}

struct RuntimeFalseTriggerInteractionReport: Codable {
    let kind: RuntimeFalseTriggerKind
    let keyCode: UInt16?
    let expectedInsertedText: String?
    let pointerStartX: Double?
    let pointerStartY: Double?
    let pointerEndX: Double?
    let pointerEndY: Double?
}

struct RuntimeFalseTriggerCaseReport: Codable {
    let id: String
    let scenario: RuntimeFalseTriggerScenario
    let target: RuntimeTargetApp
    let repetition: Int
    let startedAt: Date
    let finishedAt: Date
    let targetPreparation: RuntimeTargetPreparationInfo?
    let targetBefore: RuntimeTargetInteractionSnapshot?
    let targetAfter: RuntimeTargetInteractionSnapshot?
    let shortcutDown: RuntimeShortcutEventResult?
    let shortcutUp: RuntimeShortcutEventResult?
    let actualHoldMilliseconds: Double?
    let interaction: RuntimeFalseTriggerInteractionReport?
    let clipboardChanged: Bool
    let sideEffectsBefore: RuntimeFalseTriggerSideEffectSnapshot?
    let sideEffectsAfter: RuntimeFalseTriggerSideEffectSnapshot?
    let sideEffectRestoration: RuntimeFalseTriggerSideEffectRestoration
    let latencyTrace: RuntimeLatencyTrace?
    let nativeBehaviorSatisfied: Bool
    let targetCleanup: RuntimeTargetCleanupInfo?
    let assessment: RuntimeFalseTriggerAssessment
    let error: String?
}

enum RuntimeFalseTriggerRunner {
    private static let observationSettleSeconds: TimeInterval = 0.35

    static func execute(
        _ runCase: RuntimeFalseTriggerCase,
        configuration: RuntimeHarnessConfiguration,
        seenTraceIDs: inout Set<String>,
        restorationJournalURL: URL,
        prepareForSideEffectRestoration: () throws -> Void
    ) -> RuntimeFalseTriggerCaseReport {
        let startedAt = Date()
        let runID = makeRunID(runCase)
        let specialShortcut = configuration.resolvedSpecialShortcut
        var phase = "target"
        var preparedTarget: RuntimePreparedTarget?
        var targetBefore: RuntimeTargetInteractionSnapshot?
        var targetAfter: RuntimeTargetInteractionSnapshot?
        var shortcutDown: RuntimeShortcutEventResult?
        var shortcutUp: RuntimeShortcutEventResult?
        var interaction: RuntimeFalseTriggerInteractionReport?
        var sideEffectsBefore: RuntimeFalseTriggerSideEffectSnapshot?
        var sideEffectsAfter: RuntimeFalseTriggerSideEffectSnapshot?
        var sideEffectRestoration = RuntimeFalseTriggerSideEffectRestoration.notNeeded
        var sideEffectJournalPrepared = false
        var latencyTrace: RuntimeLatencyTrace?
        var clipboardChanged = false
        var nativeBehaviorSatisfied = false
        var assessment = RuntimeFalseTriggerAssessment(status: .targetSetupFailed, passed: false)
        var errors: [String] = []

        do {
            let target = try RuntimeTargetController.prepare(
                target: runCase.target,
                textScenario: runCase.scenario.textScenario,
                runID: runID,
                settleSeconds: configuration.targetSettleSeconds,
                availabilityPolicy: configuration.targetAvailabilityPolicy
            )
            preparedTarget = target
            guard target.focusForInteraction() else {
                throw RuntimeFalseTriggerRunnerError.targetFocusFailed
            }
            let pointerPoints = try interactionPointsIfNeeded(
                for: runCase.scenario.kind,
                target: target
            )
            if let pointerPoints {
                try RuntimeShortcutInjector.postPointerEvent(
                    type: .mouseMoved,
                    point: pointerPoints.start
                )
                Thread.sleep(forTimeInterval: 0.05)
            }

            targetBefore = target.interactionSnapshot()
            let sideEffectBaseline = RuntimeFalseTriggerSideEffectObserver.capture(
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            sideEffectsBefore = sideEffectBaseline
            guard sideEffectBaseline.observationSucceeded else {
                throw RuntimeFalseTriggerRunnerError.sideEffectObservationFailed
            }
            try RuntimeFalseTriggerSideEffectObserver.prepareRestorationJournal(
                baseline: sideEffectBaseline,
                bundleIdentifier: configuration.voiceInkBundleIdentifier,
                journalURL: restorationJournalURL
            )
            sideEffectJournalPrepared = true
            let clipboardChangeCount = NSPasteboard.general.changeCount

            phase = "shortcut"
            let down = try RuntimeShortcutInjector.postModifierDown(specialShortcut)
            shortcutDown = down
            waitUntilSystemUptime(
                down.postedAtSystemUptime + runCase.scenario.interactionStartSeconds
            )
            interaction = try performInteraction(
                runCase.scenario,
                specialShortcut: specialShortcut,
                pointerPoints: pointerPoints
            )
            waitUntilSystemUptime(down.postedAtSystemUptime + runCase.scenario.holdSeconds)
            let up = try RuntimeShortcutInjector.postModifierUp(specialShortcut)
            shortcutUp = up

            phase = "observation"
            Thread.sleep(forTimeInterval: observationSettleSeconds)
            latencyTrace = try waitForRejectedTrace(
                excluding: &seenTraceIDs,
                shortcutDownSystemUptime: down.postedAtSystemUptime,
                timeoutSeconds: 3
            )
            targetAfter = target.interactionSnapshot()
            sideEffectsAfter = RuntimeFalseTriggerSideEffectObserver.capture(
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            clipboardChanged = NSPasteboard.general.changeCount != clipboardChangeCount
            nativeBehaviorSatisfied = nativeBehaviorWasPreserved(
                interaction: interaction,
                before: targetBefore,
                after: targetAfter
            )

            let recordingsChanged = sideEffectsBefore?.recordingsDirectoryExisted
                    != sideEffectsAfter?.recordingsDirectoryExisted
                || sideEffectsBefore?.recordingFiles != sideEffectsAfter?.recordingFiles
            let historyChanged = sideEffectsBefore?.historyStoreExisted != sideEffectsAfter?.historyStoreExisted
                || sideEffectsBefore?.transcriptionRowIDs != sideEffectsAfter?.transcriptionRowIDs
                || sideEffectsBefore?.transcriptionPrimaryKeyMaximum
                    != sideEffectsAfter?.transcriptionPrimaryKeyMaximum
            let sideEffectObservationSucceeded = sideEffectsBefore?.observationSucceeded == true
                && sideEffectsAfter?.observationSucceeded == true
            assessment = RuntimeFalseTriggerAssessment.assess(
                nativeBehaviorSatisfied: nativeBehaviorSatisfied,
                shortcutEvidenceRejected: latencyTrace?.shortcutKeyEvidenceRejected == true,
                recordingDiscarded: latencyTrace?.recordingDiscarded == true,
                transcriptionStarted: latencyTrace?.transcriptionStarted == true,
                textDeliveryAttempted: latencyTrace.map {
                    $0.pasteEventPosted || $0.clipboardWriteSucceeded || $0.textDeliveryHandoffCompleted
                } ?? false,
                clipboardChanged: clipboardChanged,
                recordingsChanged: recordingsChanged,
                transcriptionCountChanged: historyChanged,
                sideEffectObservationSucceeded: sideEffectObservationSucceeded
            )
            if latencyTrace == nil {
                assessment = RuntimeFalseTriggerAssessment(status: .traceMissing, passed: false)
            }
            errors.append(contentsOf: sideEffectsBefore?.errors ?? [])
            errors.append(contentsOf: sideEffectsAfter?.errors ?? [])
        } catch {
            errors.append(String(describing: error))
            assessment = RuntimeFalseTriggerAssessment(
                status: phase == "target" ? .targetSetupFailed : .shortcutFailed,
                passed: false
            )
        }

        if shortcutDown != nil, shortcutUp == nil {
            shortcutUp = try? RuntimeShortcutInjector.postModifierUp(specialShortcut)
        }
        if shortcutDown != nil, sideEffectsAfter == nil {
            sideEffectsAfter = RuntimeFalseTriggerSideEffectObserver.capture(
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
        }
        if sideEffectJournalPrepared, let sideEffectsBefore, let sideEffectsAfter {
            if !sideEffectsAfter.observationSucceeded {
                sideEffectRestoration = restorationFailure(
                    "Could not verify post-case recording/history state"
                )
            } else if RuntimeFalseTriggerSideEffectObserver.changed(
                from: sideEffectsBefore,
                to: sideEffectsAfter
            ) {
                do {
                    try prepareForSideEffectRestoration()
                    sideEffectRestoration = try RuntimeFalseTriggerSideEffectObserver
                        .restoreFromJournal(at: restorationJournalURL)
                } catch {
                    sideEffectRestoration = restorationFailure(
                        "Could not restore false-trigger side effects: \(error)"
                    )
                }
            } else if assessment.passed {
                do {
                    try RuntimeFalseTriggerSideEffectObserver.discardRestorationJournal(
                        at: restorationJournalURL
                    )
                } catch {
                    sideEffectRestoration = restorationFailure(
                        "Could not clear the verified side-effect restoration journal: \(error)"
                    )
                }
            }
            errors.append(contentsOf: sideEffectRestoration.errors)
        }
        let targetCleanup = preparedTarget?.cleanup()
        if let targetCleanup, !targetCleanup.passed {
            errors.append(contentsOf: targetCleanup.errors)
            assessment = RuntimeFalseTriggerAssessment(status: .targetCleanupFailed, passed: false)
        }

        return RuntimeFalseTriggerCaseReport(
            id: runID,
            scenario: runCase.scenario,
            target: runCase.target,
            repetition: runCase.repetition,
            startedAt: startedAt,
            finishedAt: Date(),
            targetPreparation: preparedTarget?.info,
            targetBefore: targetBefore,
            targetAfter: targetAfter,
            shortcutDown: shortcutDown,
            shortcutUp: shortcutUp,
            actualHoldMilliseconds: shortcutDown.flatMap { down in
                shortcutUp.map { ($0.postedAtSystemUptime - down.postedAtSystemUptime) * 1_000 }
            },
            interaction: interaction,
            clipboardChanged: clipboardChanged,
            sideEffectsBefore: sideEffectsBefore,
            sideEffectsAfter: sideEffectsAfter,
            sideEffectRestoration: sideEffectRestoration,
            latencyTrace: latencyTrace,
            nativeBehaviorSatisfied: nativeBehaviorSatisfied,
            targetCleanup: targetCleanup,
            assessment: assessment,
            error: errors.isEmpty ? nil : errors.joined(separator: "; ")
        )
    }

    private static func interactionPointsIfNeeded(
        for kind: RuntimeFalseTriggerKind,
        target: RuntimePreparedTarget
    ) throws -> RuntimeTargetInteractionPoints? {
        switch kind {
        case .pointerMove, .pointerClick, .pointerDrag:
            guard let points = target.interactionPoints() else {
                throw RuntimeFalseTriggerRunnerError.pointerGeometryUnavailable
            }
            return points
        case .capitalLetter, .shiftedSymbol, .shiftTab, .shiftAHotkey:
            return nil
        }
    }

    private static func performInteraction(
        _ scenario: RuntimeFalseTriggerScenario,
        specialShortcut: RuntimeModifierShortcut,
        pointerPoints: RuntimeTargetInteractionPoints?
    ) throws -> RuntimeFalseTriggerInteractionReport {
        let specialFlags = RuntimeShortcutInjector.flags(for: specialShortcut.modifierFlag)
        let shiftedFlags = specialFlags.union(.maskShift)

        switch scenario.kind {
        case .capitalLetter:
            let letter = randomLetter()
            try postKey(
                keyCode: letter.keyCode,
                flags: shiftedFlags,
                durationSeconds: scenario.interactionDurationSeconds
            )
            return interactionReport(kind: scenario.kind, keyCode: letter.keyCode, text: letter.character)
        case .shiftedSymbol:
            try postKey(keyCode: 21, flags: shiftedFlags, durationSeconds: scenario.interactionDurationSeconds)
            return interactionReport(kind: scenario.kind, keyCode: 21, text: "$")
        case .shiftTab:
            try postKey(keyCode: 48, flags: shiftedFlags, durationSeconds: scenario.interactionDurationSeconds)
            return interactionReport(kind: scenario.kind, keyCode: 48, text: nil)
        case .shiftAHotkey:
            try postKey(keyCode: 0, flags: shiftedFlags, durationSeconds: scenario.interactionDurationSeconds)
            return interactionReport(kind: scenario.kind, keyCode: 0, text: "A")
        case .pointerMove:
            let points = try requirePointerPoints(pointerPoints)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .mouseMoved,
                point: points.end,
                flags: specialFlags
            )
            Thread.sleep(forTimeInterval: scenario.interactionDurationSeconds)
            return interactionReport(kind: scenario.kind, points: points)
        case .pointerClick:
            let points = try requirePointerPoints(pointerPoints)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .leftMouseDown,
                point: points.start,
                flags: specialFlags
            )
            Thread.sleep(forTimeInterval: scenario.interactionDurationSeconds)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .leftMouseUp,
                point: points.start,
                flags: specialFlags
            )
            return interactionReport(kind: scenario.kind, points: points)
        case .pointerDrag:
            let points = try requirePointerPoints(pointerPoints)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .leftMouseDown,
                point: points.start,
                flags: specialFlags
            )
            Thread.sleep(forTimeInterval: scenario.interactionDurationSeconds / 2)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .leftMouseDragged,
                point: points.end,
                flags: specialFlags
            )
            Thread.sleep(forTimeInterval: scenario.interactionDurationSeconds / 2)
            try RuntimeShortcutInjector.postPointerEvent(
                type: .leftMouseUp,
                point: points.end,
                flags: specialFlags
            )
            return interactionReport(kind: scenario.kind, points: points)
        }
    }

    private static func postKey(
        keyCode: UInt16,
        flags: CGEventFlags,
        durationSeconds: TimeInterval
    ) throws {
        _ = try RuntimeShortcutInjector.postKeyDown(keyCode: keyCode, flags: flags)
        Thread.sleep(forTimeInterval: durationSeconds)
        _ = try RuntimeShortcutInjector.postKeyUp(keyCode: keyCode, flags: flags)
    }

    private static func nativeBehaviorWasPreserved(
        interaction: RuntimeFalseTriggerInteractionReport?,
        before: RuntimeTargetInteractionSnapshot?,
        after: RuntimeTargetInteractionSnapshot?
    ) -> Bool {
        guard let interaction, let before, let after else { return false }
        return RuntimeFalseTriggerNativeBehaviorPolicy.isSatisfied(
            kind: interaction.kind,
            expectedInsertedText: interaction.expectedInsertedText,
            before: before,
            after: after
        )
    }

    private static func interactionReport(
        kind: RuntimeFalseTriggerKind,
        keyCode: UInt16,
        text: String?
    ) -> RuntimeFalseTriggerInteractionReport {
        RuntimeFalseTriggerInteractionReport(
            kind: kind,
            keyCode: keyCode,
            expectedInsertedText: text,
            pointerStartX: nil,
            pointerStartY: nil,
            pointerEndX: nil,
            pointerEndY: nil
        )
    }

    private static func interactionReport(
        kind: RuntimeFalseTriggerKind,
        points: RuntimeTargetInteractionPoints
    ) -> RuntimeFalseTriggerInteractionReport {
        RuntimeFalseTriggerInteractionReport(
            kind: kind,
            keyCode: nil,
            expectedInsertedText: nil,
            pointerStartX: points.start.x,
            pointerStartY: points.start.y,
            pointerEndX: points.end.x,
            pointerEndY: points.end.y
        )
    }

    private static func requirePointerPoints(
        _ points: RuntimeTargetInteractionPoints?
    ) throws -> RuntimeTargetInteractionPoints {
        guard let points else { throw RuntimeFalseTriggerRunnerError.pointerGeometryUnavailable }
        return points
    }

    private static func randomLetter() -> (keyCode: UInt16, character: String) {
        let letters: [(UInt16, String)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"),
            (5, "G"), (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"),
            (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"),
            (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"),
            (16, "Y"), (6, "Z")
        ]
        return letters.randomElement()!
    }

    private static func waitForRejectedTrace(
        excluding seenTraceIDs: inout Set<String>,
        shortcutDownSystemUptime: TimeInterval,
        timeoutSeconds: TimeInterval
    ) throws -> RuntimeLatencyTrace? {
        let attributionToleranceSeconds: TimeInterval = 0.15
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var candidate: RuntimeLatencyTrace?
        var observedTraceIDs = seenTraceIDs
        repeat {
            let snapshot = try RuntimeLatencyLogReader.recent()
            observedTraceIDs.formUnion(snapshot.traces.map(\.traceID))
            let newTraces = snapshot.traces.filter { !seenTraceIDs.contains($0.traceID) }
            let attributedTraces = newTraces.filter { trace in
                trace.shortcutKeyDownSystemUptime.map {
                    abs($0 - shortcutDownSystemUptime) <= attributionToleranceSeconds
                } ?? false
            }
            guard attributedTraces.count <= 1 else {
                throw RuntimeFalseTriggerRunnerError.ambiguousLatencyTrace
            }
            if let rejected = attributedTraces.last(where: \.shortcutKeyEvidenceRejected) {
                candidate = rejected
                if rejected.recordingDiscarded {
                    seenTraceIDs = observedTraceIDs
                    return rejected
                }
            } else if let triggered = attributedTraces.last(where: \.triggerObserved) {
                candidate = triggered
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
        } while Date() < deadline
        seenTraceIDs = observedTraceIDs
        return candidate
    }

    private static func waitUntilSystemUptime(_ target: TimeInterval) {
        while true {
            let remaining = target - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(remaining, 0.005))
        }
    }

    private static func makeRunID(_ runCase: RuntimeFalseTriggerCase) -> String {
        "false-\(runCase.scenario.id)-\(runCase.target.id)-r\(runCase.repetition)-\(UUID().uuidString.prefix(6))"
    }

    private static func restorationFailure(
        _ message: String
    ) -> RuntimeFalseTriggerSideEffectRestoration {
        RuntimeFalseTriggerSideEffectRestoration(
            attempted: true,
            removedRecordingFiles: [],
            removedTranscriptionRowIDs: [],
            stateMatchesBaseline: false,
            passed: false,
            errors: [message]
        )
    }
}

enum RuntimeFalseTriggerSideEffectObserver {
    private struct RestorationJournal: Codable {
        let bundleIdentifier: String
        let baseline: RuntimeFalseTriggerSideEffectSnapshot
    }

    static func capture(bundleIdentifier: String) -> RuntimeFalseTriggerSideEffectSnapshot {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(bundleIdentifier, isDirectory: true)
        return capture(applicationSupportURL: appSupportURL)
    }

    static func capture(applicationSupportURL appSupportURL: URL) -> RuntimeFalseTriggerSideEffectSnapshot {
        let recordingsURL = appSupportURL.appendingPathComponent("Recordings", isDirectory: true)
        let historyURL = appSupportURL.appendingPathComponent("default.store")
        var errors: [String] = []
        let recordingsDirectoryExisted = FileManager.default.fileExists(atPath: recordingsURL.path)
        let historyStoreExisted = FileManager.default.fileExists(atPath: historyURL.path)
        let recordingFiles = recordingFingerprints(at: recordingsURL, errors: &errors)
        let transcriptionRowIDs: [Int]?
        let transcriptionPrimaryKeyMaximum: Int?
        do {
            let history = try queryTranscriptionState(at: historyURL)
            transcriptionRowIDs = history.rowIDs
            transcriptionPrimaryKeyMaximum = history.primaryKeyMaximum
        } catch {
            transcriptionRowIDs = nil
            transcriptionPrimaryKeyMaximum = nil
            errors.append(String(describing: error))
        }
        return RuntimeFalseTriggerSideEffectSnapshot(
            recordingsDirectoryPath: recordingsURL.path,
            recordingsDirectoryExisted: recordingsDirectoryExisted,
            recordingFiles: recordingFiles,
            historyStorePath: historyURL.path,
            historyStoreExisted: historyStoreExisted,
            transcriptionCount: transcriptionRowIDs?.count,
            transcriptionRowIDs: transcriptionRowIDs,
            transcriptionPrimaryKeyMaximum: transcriptionPrimaryKeyMaximum,
            errors: errors
        )
    }

    static func changed(
        from baseline: RuntimeFalseTriggerSideEffectSnapshot,
        to current: RuntimeFalseTriggerSideEffectSnapshot
    ) -> Bool {
        baseline.recordingsDirectoryExisted != current.recordingsDirectoryExisted
            || baseline.recordingFiles != current.recordingFiles
            || baseline.historyStoreExisted != current.historyStoreExisted
            || baseline.transcriptionRowIDs != current.transcriptionRowIDs
            || baseline.transcriptionPrimaryKeyMaximum != current.transcriptionPrimaryKeyMaximum
    }

    static func prepareRestorationJournal(
        baseline: RuntimeFalseTriggerSideEffectSnapshot,
        bundleIdentifier: String,
        journalURL: URL
    ) throws {
        guard !FileManager.default.fileExists(atPath: journalURL.path) else {
            throw RuntimeFalseTriggerRunnerError.pendingSideEffectRestoration
        }
        let journal = RestorationJournal(
            bundleIdentifier: bundleIdentifier,
            baseline: baseline
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)
    }

    static func pendingRestorationBundleIdentifier(at journalURL: URL) throws -> String {
        try readRestorationJournal(at: journalURL).bundleIdentifier
    }

    static func restoreFromJournal(
        at journalURL: URL
    ) throws -> RuntimeFalseTriggerSideEffectRestoration {
        let journal = try readRestorationJournal(at: journalURL)
        let result = restore(
            baseline: journal.baseline,
            bundleIdentifier: journal.bundleIdentifier
        )
        guard result.passed else {
            throw RuntimeFalseTriggerRunnerError.sideEffectRestorationFailed(
                result.errors.joined(separator: "; ")
            )
        }
        try discardRestorationJournal(at: journalURL)
        return result
    }

    static func discardRestorationJournal(at journalURL: URL) throws {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            try FileManager.default.removeItem(at: journalURL)
        }
    }

    static func restore(
        baseline: RuntimeFalseTriggerSideEffectSnapshot,
        bundleIdentifier: String
    ) -> RuntimeFalseTriggerSideEffectRestoration {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(bundleIdentifier, isDirectory: true)
        return restore(baseline: baseline, applicationSupportURL: appSupportURL)
    }

    static func verifyRestoration() throws {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.temporaryDirectory.appendingPathComponent(
            "roma-runtime-e2e-restoration-check-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: appSupportURL) }
        let recordingsURL = appSupportURL.appendingPathComponent("Recordings", isDirectory: true)
        try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        try Data("baseline".utf8).write(
            to: recordingsURL.appendingPathComponent("existing.wav")
        )
        let storeURL = appSupportURL.appendingPathComponent("default.store")
        _ = try runSQLite(arguments: [
            storeURL.path,
            "CREATE TABLE ZTRANSCRIPTION (Z_PK INTEGER PRIMARY KEY);"
                + "CREATE TABLE Z_PRIMARYKEY (Z_NAME VARCHAR, Z_MAX INTEGER);"
                + "INSERT INTO ZTRANSCRIPTION VALUES (1);"
                + "INSERT INTO Z_PRIMARYKEY VALUES ('Transcription', 1);"
        ])
        let baseline = capture(applicationSupportURL: appSupportURL)

        try Data("leak".utf8).write(
            to: recordingsURL.appendingPathComponent("false-trigger.wav")
        )
        _ = try runSQLite(arguments: [
            storeURL.path,
            "INSERT INTO ZTRANSCRIPTION VALUES (2);"
                + "UPDATE Z_PRIMARYKEY SET Z_MAX=2 WHERE Z_NAME='Transcription';"
        ])

        let result = restore(baseline: baseline, applicationSupportURL: appSupportURL)
        guard result.passed,
              result.removedRecordingFiles == ["false-trigger.wav"],
              result.removedTranscriptionRowIDs == [2],
              capture(applicationSupportURL: appSupportURL) == baseline else {
            throw RuntimeFalseTriggerRunnerError.sideEffectSelfCheckFailed(
                result.errors.joined(separator: "; ")
            )
        }
    }

    private static func restore(
        baseline: RuntimeFalseTriggerSideEffectSnapshot,
        applicationSupportURL: URL
    ) -> RuntimeFalseTriggerSideEffectRestoration {
        var errors: [String] = []
        var removedRecordingFiles: [String] = []
        var removedTranscriptionRowIDs: [Int] = []
        let current = capture(applicationSupportURL: applicationSupportURL)

        guard baseline.observationSucceeded, current.observationSucceeded else {
            return RuntimeFalseTriggerSideEffectRestoration(
                attempted: true,
                removedRecordingFiles: [],
                removedTranscriptionRowIDs: [],
                stateMatchesBaseline: false,
                passed: false,
                errors: baseline.errors + current.errors + [
                    "Cannot safely restore false-trigger side effects without complete snapshots"
                ]
            )
        }

        let baselineFiles = Dictionary(uniqueKeysWithValues: baseline.recordingFiles.map { ($0.name, $0) })
        let currentFiles = Dictionary(uniqueKeysWithValues: current.recordingFiles.map { ($0.name, $0) })
        let changedExistingFiles = Set(baselineFiles.keys).intersection(currentFiles.keys).filter {
            baselineFiles[$0] != currentFiles[$0]
        }
        if !changedExistingFiles.isEmpty {
            errors.append(
                "Pre-existing recording files changed and cannot be restored: "
                    + changedExistingFiles.sorted().joined(separator: ", ")
            )
        }
        let newRecordingFiles = Set(currentFiles.keys).subtracting(baselineFiles.keys).sorted()
        let recordingsURL = URL(fileURLWithPath: baseline.recordingsDirectoryPath, isDirectory: true)
        for name in newRecordingFiles {
            let fileURL = recordingsURL.appendingPathComponent(name, isDirectory: false)
            guard fileURL.deletingLastPathComponent().standardizedFileURL == recordingsURL.standardizedFileURL else {
                errors.append("Refused to remove recording outside the observed directory: \(name)")
                continue
            }
            do {
                try FileManager.default.removeItem(at: fileURL)
                removedRecordingFiles.append(name)
            } catch {
                errors.append("Could not remove false-trigger recording \(name): \(error)")
            }
        }

        if !baseline.recordingsDirectoryExisted,
           FileManager.default.fileExists(atPath: recordingsURL.path) {
            do {
                let remaining = try FileManager.default.contentsOfDirectory(atPath: recordingsURL.path)
                if remaining.isEmpty {
                    try FileManager.default.removeItem(at: recordingsURL)
                } else {
                    errors.append("False-trigger Recordings directory still contains files")
                }
            } catch {
                errors.append("Could not restore the original Recordings directory state: \(error)")
            }
        }

        if !baseline.historyStoreExisted, current.historyStoreExisted {
            errors.append("False trigger created a history store that cannot be safely removed")
        } else if let baselineRowIDs = baseline.transcriptionRowIDs,
                  let currentRowIDs = current.transcriptionRowIDs {
            let deletedBaselineRows = Set(baselineRowIDs).subtracting(currentRowIDs)
            if !deletedBaselineRows.isEmpty {
                errors.append("Pre-existing transcription rows disappeared during the case")
            }
            let newRowIDs = Set(currentRowIDs).subtracting(baselineRowIDs).sorted()
            do {
                try restoreHistory(
                    storeURL: URL(fileURLWithPath: baseline.historyStorePath),
                    rowIDs: newRowIDs,
                    primaryKeyMaximum: baseline.transcriptionPrimaryKeyMaximum
                )
                removedTranscriptionRowIDs = newRowIDs
            } catch {
                errors.append("Could not remove false-trigger transcription rows: \(error)")
            }
        }

        let final = capture(applicationSupportURL: applicationSupportURL)
        let stateMatchesBaseline = snapshotsMatchState(baseline, final)
        if !stateMatchesBaseline {
            errors.append("False-trigger artifacts or history did not return to the pre-case baseline")
        }
        errors.append(contentsOf: final.errors)
        return RuntimeFalseTriggerSideEffectRestoration(
            attempted: true,
            removedRecordingFiles: removedRecordingFiles,
            removedTranscriptionRowIDs: removedTranscriptionRowIDs,
            stateMatchesBaseline: stateMatchesBaseline,
            passed: errors.isEmpty && stateMatchesBaseline,
            errors: errors
        )
    }

    private static func recordingFingerprints(
        at directoryURL: URL,
        errors: inout [String]
    ) -> [RuntimeRecordingFileFingerprint] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).map { url in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return RuntimeRecordingFileFingerprint(
                    name: url.lastPathComponent,
                    size: UInt64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate
                )
            }.sorted { $0.name < $1.name }
        } catch {
            errors.append("Could not inspect recording artifacts: \(error)")
            return []
        }
    }

    private static func queryTranscriptionState(
        at storeURL: URL
    ) throws -> (rowIDs: [Int], primaryKeyMaximum: Int?) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return ([], nil) }
        let tableCount = try sqliteScalar(
            storeURL: storeURL,
            query: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='ZTRANSCRIPTION';"
        )
        guard tableCount > 0 else { return ([], nil) }
        let rowIDs = try sqliteIntegers(
            storeURL: storeURL,
            query: "SELECT Z_PK FROM ZTRANSCRIPTION ORDER BY Z_PK;"
        )
        let primaryKeyMaximum = try sqliteIntegers(
            storeURL: storeURL,
            query: "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='Transcription' LIMIT 1;"
        ).first
        return (rowIDs, primaryKeyMaximum)
    }

    private static func sqliteScalar(storeURL: URL, query: String) throws -> Int {
        let value = try runSQLite(arguments: ["-readonly", storeURL.path, query])
        guard let scalar = Int(value) else {
            throw RuntimeFalseTriggerRunnerError.historyQueryFailed(
                "sqlite returned a non-integer value"
            )
        }
        return scalar
    }

    private static func sqliteIntegers(storeURL: URL, query: String) throws -> [Int] {
        let output = try runSQLite(arguments: ["-readonly", storeURL.path, query])
        if output.isEmpty { return [] }
        let rows = output.split(whereSeparator: \.isNewline)
        let values = rows.compactMap { Int($0) }
        guard values.count == rows.count else {
            throw RuntimeFalseTriggerRunnerError.historyQueryFailed("sqlite returned a non-integer value")
        }
        return values
    }

    private static func restoreHistory(
        storeURL: URL,
        rowIDs: [Int],
        primaryKeyMaximum: Int?
    ) throws {
        var statements = ["PRAGMA busy_timeout=5000", "BEGIN IMMEDIATE"]
        if !rowIDs.isEmpty {
            statements.append("DELETE FROM ZTRANSCRIPTION WHERE Z_PK IN (\(rowIDs.map(String.init).joined(separator: ",")))")
        }
        if let primaryKeyMaximum {
            statements.append(
                "UPDATE Z_PRIMARYKEY SET Z_MAX=\(primaryKeyMaximum) WHERE Z_NAME='Transcription'"
            )
        }
        statements.append("COMMIT")
        _ = try runSQLite(arguments: [storeURL.path, statements.joined(separator: ";") + ";"])
    }

    private static func runSQLite(arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeFalseTriggerRunnerError.historyQueryFailed(message)
        }
        return String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func snapshotsMatchState(
        _ lhs: RuntimeFalseTriggerSideEffectSnapshot,
        _ rhs: RuntimeFalseTriggerSideEffectSnapshot
    ) -> Bool {
        lhs.recordingsDirectoryExisted == rhs.recordingsDirectoryExisted
            && lhs.recordingFiles == rhs.recordingFiles
            && lhs.historyStoreExisted == rhs.historyStoreExisted
            && lhs.transcriptionRowIDs == rhs.transcriptionRowIDs
            && lhs.transcriptionPrimaryKeyMaximum == rhs.transcriptionPrimaryKeyMaximum
    }

    private static func readRestorationJournal(at journalURL: URL) throws -> RestorationJournal {
        let data = try Data(contentsOf: journalURL)
        return try JSONDecoder().decode(RestorationJournal.self, from: data)
    }
}

enum RuntimeFalseTriggerRunnerError: Error, CustomStringConvertible {
    case targetFocusFailed
    case pointerGeometryUnavailable
    case historyQueryFailed(String)
    case ambiguousLatencyTrace
    case sideEffectObservationFailed
    case pendingSideEffectRestoration
    case sideEffectRestorationFailed(String)
    case sideEffectSelfCheckFailed(String)

    var description: String {
        switch self {
        case .targetFocusFailed:
            return "Could not focus the false-trigger target"
        case .pointerGeometryUnavailable:
            return "Could not resolve pointer coordinates inside the target editor"
        case .historyQueryFailed(let message):
            return "Could not inspect transcription history: \(message)"
        case .ambiguousLatencyTrace:
            return "Multiple shortcut traces matched one injected modifier press"
        case .sideEffectObservationFailed:
            return "Could not capture a complete recording/history baseline"
        case .pendingSideEffectRestoration:
            return "A previous false-trigger side-effect restoration is still pending"
        case .sideEffectRestorationFailed(let message):
            return "False-trigger side-effect restoration failed: \(message)"
        case .sideEffectSelfCheckFailed(let message):
            return "False-trigger side-effect restoration self-check failed: \(message)"
        }
    }
}
