import Foundation
import RuntimeE2ECore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(
    _ actual: Double,
    equals expected: Double,
    accuracy: Double = 0.000_001,
    _ message: String
) throws {
    guard abs(actual - expected) <= accuracy else {
        throw CheckFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CheckFailure(description: message)
    }
}

do {
    let plan = try RuntimeTimingPlan(
        audioDurationSeconds: 12.03125,
        audioLeadSeconds: 1.1,
        releaseTailSeconds: 0.15
    )

    try require(plan.keyDownOffsetSeconds, equals: 1.1, "key-down offset")
    try require(plan.keyUpOffsetSeconds, equals: 12.18125, "key-up offset")
    try require(plan.holdDurationSeconds, equals: 11.08125, "hold duration")
    print("PASS speech starts 1.1 seconds before key-down and release follows fixture")

    let fixtures = [
        URL(fileURLWithPath: "/audio/normal noisy clear.wav"),
        URL(fileURLWithPath: "/audio/normal wispering.wav")
    ]
    let targets = RuntimeTargetApp.defaultMatrix
    let runPlan = try RuntimeRunPlan.make(
        fixtureURLs: fixtures,
        expectedTranscripts: ["normal noisy clear.wav": "expected noisy speech"],
        targets: targets,
        repetitions: 2
    )

    try require(targets.count == 5, "default target matrix should contain five apps")
    try require(runPlan.cases.count == 20, "two fixtures x five apps x two repetitions should create twenty cases")
    try require(
        runPlan.cases.first?.expectedTranscript == "expected noisy speech",
        "fixture answer should flow into each case when supplied"
    )
    try require(
        runPlan.cases.contains { $0.fixtureURL.lastPathComponent == "normal wispering.wav" && $0.expectedTranscript == nil },
        "fixtures without answers should remain runnable without content assertions"
    )
    print("PASS fixture/app/repetition matrix carries optional transcript answers")

    let noPaste = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: false,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440
    )
    try require(noPaste.status == .noPaste, "missing target text should be classified as noPaste")
    try require(!noPaste.passed, "noPaste must fail the case")
    print("PASS missing target insertion is an explicit noPaste failure")

    let emptyTranscript = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        transcribedCharacterCount: 0
    )
    try require(
        emptyTranscript.status == .emptyTranscript,
        "a successful zero-character transcription must not be blamed on paste delivery"
    )
    print("PASS empty transcription remains distinct from clipboard and target failures")

    let shortcutTimingMismatch = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        shortcutHoldMatched: false,
        transcriptionCompleted: false
    )
    try require(
        shortcutTimingMismatch.status == .shortcutTimingMismatch,
        "an app-observed hold that disagrees with the posted hold must remain an input-delivery failure"
    )

    let incompleteTranscription = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        shortcutHoldMatched: true,
        transcriptionCompleted: false
    )
    try require(
        incompleteTranscription.status == .transcriptionIncomplete,
        "an incomplete VoiceInk trace must not be classified from unrelated clipboard changes"
    )
    print("PASS shortcut delivery and incomplete transcription remain distinct from paste failures")

    let unrenderedPaste = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "AX already contains text",
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440
    )
    try require(
        unrenderedPaste.status == .renderNotObserved,
        "AX text without rendered pixels must remain a distinct failure"
    )
    print("PASS AX text cannot masquerade as rendered visibility")

    let defaults = RuntimeHarnessConfiguration.default
    try require(defaults.audioDirectory.hasSuffix("/Downloads/roma jt builds/audio"), "default audio directory")
    try require(defaults.audioDeviceName == "BlackHole 2ch", "default loopback device")
    try require(defaults.targets == RuntimeTargetApp.defaultMatrix, "default app matrix")
    try require(defaults.repetitions == 3, "default repetitions")
    try require(defaults.audioLeadSeconds, equals: 1.1, "default audio lead")
    try require(defaults.latencyThresholdMilliseconds, equals: 440, "default latency budget")
    try require(
        defaults.targetAvailabilityPolicy == .runningOnly,
        "local default must not launch closed target apps"
    )
    try require(defaults.minimumTargetCount == 4, "runtime coverage must require four distinct apps")
    let runningTargets = RuntimeTargetAvailabilitySelector.select(
        configuredTargets: targets,
        runningBundleIdentifiers: ["com.google.Chrome", "dev.zed.Zed"],
        policy: .runningOnly
    )
    try require(
        runningTargets.map(\.id) == ["chrome", "zed"],
        "running-only coverage should preserve configured order and skip closed apps"
    )
    let restorationTargets = RuntimeTargetCatalog.restorationTargets(
        configuredTargets: [
            targets[1],
            RuntimeTargetApp(
                id: "repo-prompt",
                displayName: "Repo Prompt",
                bundleIdentifier: "com.pvncher.repoprompt",
                kind: .document
            )
        ]
    )
    try require(
        restorationTargets.map(\.bundleIdentifier).contains("com.google.Chrome"),
        "custom runs must retain default target metadata for abandoned-resource cleanup"
    )
    try require(
        restorationTargets.filter { $0.bundleIdentifier == "com.apple.Safari" }.count == 1,
        "restoration target catalog must deduplicate configured and default apps"
    )
    print("PASS zero-config run covers supplied fixtures without launching closed target apps")

    let targetTitle = "Roma Runtime E2E fixture-textedit-r1-ABC123"
    try require(
        RuntimeTargetIsolationPlan.documentFilename(
            windowTitleToken: targetTitle,
            bundleIdentifier: "com.apple.TextEdit"
        )
            == "\(targetTitle).txt",
        "document filename must preserve the window-title token used for scoped cleanup"
    )
    try require(
        RuntimeTargetIsolationPlan.documentFilename(
            windowTitleToken: targetTitle,
            bundleIdentifier: "com.apple.ScriptEditor2"
        ) == "\(targetTitle).applescript",
        "Script Editor targets must use its editable document type"
    )
    try require(
        RuntimeTargetIsolationPlan.openArguments(
            bundleIdentifier: "com.google.Chrome",
            resourcePath: "/tmp/\(targetTitle).txt"
        ) == ["-b", "com.google.Chrome", "/tmp/\(targetTitle).txt"],
        "target resource launch must address third-party apps by exact bundle identifier"
    )
    try require(
        RuntimeTargetIsolationPlan.browserEditableLabel(windowTitleToken: targetTitle)
            .contains(targetTitle),
        "browser textarea label must carry the unique target token"
    )
    print("PASS target resources preserve unique tab/window identity and avoid split-instance launch")

    let selectedVoiceInk = RuntimeVoiceInkCandidateSelector.select(
        explicitPath: nil,
        runningPaths: ["/Applications/VoiceInk.app"],
        buildDirectoryPath: "/Users/felix/Downloads/roma jt builds",
        buildCandidates: [
            RuntimeVoiceInkCandidate(path: "/Users/felix/Downloads/roma jt builds/older.app", modifiedAt: Date(timeIntervalSince1970: 1)),
            RuntimeVoiceInkCandidate(path: "/Users/felix/Downloads/roma jt builds/current.app", modifiedAt: Date(timeIntervalSince1970: 2))
        ],
        workspaceInstalledPath: "/Applications/VoiceInk.app"
    )
    try require(selectedVoiceInk?.path.hasSuffix("/current.app") == true, "newest build artifact should beat unrelated installed app")
    try require(selectedVoiceInk?.source == .buildDirectory, "selection source should identify the build directory")
    print("PASS exact newest build artifact is selected instead of unrelated installed VoiceInk")

    let contentPass = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "Hello, ROMA runtime!",
            keyUpToVisibleMilliseconds: 200,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: "hello roma runtime",
        latencyThresholdMilliseconds: 440
    )
    try require(contentPass.status == .passed, "case and punctuation should not fail transcript QA")
    try require(contentPass.wordErrorRate == 0, "normalized identical transcript should have zero WER")

    let contentMismatch = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "completely different words",
            keyUpToVisibleMilliseconds: 200,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: "hello roma runtime",
        latencyThresholdMilliseconds: 440
    )
    try require(contentMismatch.status == .contentMismatch, "materially wrong transcript should fail content QA")
    print("PASS optional transcript answers enforce normalized word-error quality")

    let trace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=A1B2C3D4 seq=0 t=0.0ms delta=0.0ms event=shortcut.key_down_source keyCode=56",
        "[LATENCY] trace=A1B2C3D4 seq=1 t=1100.0ms delta=1100.0ms event=shortcut.key_up_handler duration=1.1",
        "[LATENCY] trace=A1B2C3D4 seq=2 t=1300.0ms delta=200.0ms event=paste_event_posted chars=18",
        "[LATENCY] trace=A1B2C3D4 seq=3 t=1500.0ms delta=200.0ms event=pipeline.complete",
        "[LATENCY] trace=A1B2C3D4 seq=4 t=1800.0ms delta=300.0ms event=ui.engine_toggle.end"
    ])
    try require(trace?.traceID == "A1B2C3D4", "trace ID should be parsed")
    try require(trace?.triggerObserved == true, "key-down trace event should prove trigger acceptance")
    try require(trace?.pasteEventPosted == true, "paste event should be recognized")
    try require(trace?.events.map(\.sequence) == [0, 1, 2, 3, 4], "trace events should stay sequence ordered")
    try require(
        trace?.keyUpToPasteEventMilliseconds ?? -1,
        equals: 200,
        "trace should separate VoiceInk key-up-to-paste handoff from target visibility"
    )
    try require(
        trace?.keyUpToPipelineCompleteMilliseconds ?? -1,
        equals: 400,
        "trace should expose post-paste pipeline completion"
    )
    try require(
        trace?.keyUpToInteractionSettledMilliseconds ?? -1,
        equals: 700,
        "trace should expose the final interaction-settled boundary"
    )
    print("PASS latency trace separates paste, pipeline completion, and settled interaction")

    let executorTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=E1E2E3E4 seq=0 t=100.0ms delta=100.0ms event=streaming_service.drain_continuation.executor_enqueued sentChunks=12",
        "[LATENCY] trace=E1E2E3E4 seq=1 t=612.4ms delta=512.4ms event=streaming_service.drain_continuation.executor_resumed queueDelayMs=512.4"
    ])
    try require(
        executorTrace?.events.last?.executorQueueDelayMilliseconds ?? -1,
        equals: 512.4,
        "executor resume events should expose their queue delay"
    )
    try require(
        executorTrace?.maximumExecutorQueueDelayMilliseconds ?? -1,
        equals: 512.4,
        "trace should expose its worst executor queue delay"
    )
    print("PASS latency trace preserves executor enqueue-to-resume timing")

    let shortcutTimingTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=A1A2A3A4 seq=0 t=0.0ms delta=0.0ms event=shortcut.key_down_physical mode=special",
        "[LATENCY] trace=A1A2A3A4 seq=1 t=166.2ms delta=166.2ms event=shortcut.key_up_handler state=recording"
    ])
    try require(
        shortcutTimingTrace?.observedShortcutHoldMilliseconds ?? -1,
        equals: 166.2,
        "trace should expose the shortcut hold VoiceInk actually observed"
    )
    print("PASS latency trace exposes the VoiceInk-observed shortcut hold")

    let emptyTranscriptTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=F1F2F3F4 seq=0 t=100.0ms delta=100.0ms event=pipeline.transcribe.end durationMs=52.0 result=success rawChars=0"
    ])
    try require(
        emptyTranscriptTrace?.transcribedCharacterCount == 0,
        "trace parsing must preserve a zero-character transcription result"
    )
    let failedTranscriptTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=F5F6F7F8 seq=0 t=100.0ms delta=100.0ms event=pipeline.transcribe.end durationMs=52.0 result=failure rawChars=0"
    ])
    try require(
        failedTranscriptTrace?.transcribedCharacterCount == nil,
        "failed transcription attempts must not masquerade as successful empty transcripts"
    )
    print("PASS latency trace exposes the transcription character count")

    let stablePixels = [UInt8](repeating: 128, count: 400 * 4)
    var caretOnlyPixels = stablePixels
    for pixel in 0..<40 {
        caretOnlyPixels[pixel * 4] = 0
    }
    let caretOnlyDifference = RuntimeRenderedTextChangePolicy.compareRGBA(
        baseline: stablePixels,
        current: caretOnlyPixels
    )
    try require(caretOnlyDifference?.passed == false, "caret-sized changes must not count as rendered text")

    var renderedTextPixels = stablePixels
    for pixel in 0..<120 {
        renderedTextPixels[pixel * 4] = 0
    }
    let renderedTextDifference = RuntimeRenderedTextChangePolicy.compareRGBA(
        baseline: stablePixels,
        current: renderedTextPixels
    )
    try require(renderedTextDifference?.passed == true, "text-sized pixel changes must count as rendered text")
    try require(
        RuntimeRenderedTextChangePolicy.requiredChangedPixels(for: 402_560) == 80,
        "large editable regions must not raise the rendered-text threshold"
    )

    var transientTextPixels = renderedTextPixels
    for pixel in 120..<180 {
        transientTextPixels[pixel * 4] = 0
    }
    var stabilityTracker = RuntimeRenderedTextStabilityTracker(baseline: stablePixels)
    try require(
        stabilityTracker.observe(current: renderedTextPixels)?.stable == false,
        "the first changed frame cannot establish stability"
    )
    try require(
        stabilityTracker.observe(current: transientTextPixels)?.stable == false,
        "two materially different changed frames must not establish stability"
    )
    try require(
        stabilityTracker.observe(current: transientTextPixels)?.stable == true,
        "two mutually stable changed frames must establish rendered text"
    )

    var renderedLatencyTracker = RuntimeRenderedTextLatencyTracker(baseline: stablePixels)
    try require(
        renderedLatencyTracker.observe(
            current: renderedTextPixels,
            atSystemUptime: 1
        )?.firstPersistentChangeAtSystemUptime == nil,
        "the first changed frame must remain provisional"
    )
    try require(
        renderedLatencyTracker.observe(
            current: transientTextPixels,
            atSystemUptime: 2
        )?.firstPersistentChangeAtSystemUptime == nil,
        "a materially different frame must replace the provisional render timestamp"
    )
    try require(
        renderedLatencyTracker.observe(
            current: transientTextPixels,
            atSystemUptime: 3
        )?.firstPersistentChangeAtSystemUptime == 2,
        "stable render proof must report the first persistent frame, not the verification frame"
    )

    try require(
        RuntimeTextVisibilityAttribution.renderedLatency(
            accessibilityText: nil,
            renderedLatency: 180
        ) == nil,
        "pixel changes alone must not be attributed to inserted text"
    )
    try require(
        RuntimeTextVisibilityAttribution.renderedLatency(
            accessibilityText: "AX arrived later",
            renderedLatency: 180
        ) ?? -1,
        equals: 180,
        "AX arriving later must preserve the independently sampled render time"
    )
    print("PASS rendered-text policy rejects noise, requires stability, and remains AX-independent")

    let latencies = [100.0, 200.0, 300.0, 400.0, 500.0]
    try require(RuntimeStatistics.percentile(50, values: latencies) ?? -1, equals: 300, "p50 latency")
    try require(RuntimeStatistics.percentile(95, values: latencies) ?? -1, equals: 500, "p95 latency")
    print("PASS report statistics expose median and p95 visible-text latency")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
