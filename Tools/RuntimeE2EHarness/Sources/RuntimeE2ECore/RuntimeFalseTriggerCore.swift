import Foundation

public enum RuntimeModifierFlag: String, Codable, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command
    case function
}

public struct RuntimeModifierShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifierFlag: RuntimeModifierFlag

    public init(keyCode: UInt16, modifierFlag: RuntimeModifierFlag) {
        self.keyCode = keyCode
        self.modifierFlag = modifierFlag
    }

    public static let leftShift = Self(keyCode: 56, modifierFlag: .shift)
}

public enum RuntimeFalseTriggerKind: String, Codable, CaseIterable, Hashable, Sendable {
    case capitalLetter
    case shiftedSymbol
    case shiftTab
    case shiftAHotkey
    case pointerMove
    case pointerClick
    case pointerDrag
}

public struct RuntimeFalseTriggerNativeSnapshot: Codable, Equatable, Sendable {
    public let text: String?
    public let selectionLocation: Int?
    public let selectionLength: Int?
    public let textElementFocused: Bool?
    public let focusedRole: String?
    public let focusedTitle: String?
    public let pointerX: Double
    public let pointerY: Double

    public init(
        text: String?,
        selectionLocation: Int?,
        selectionLength: Int?,
        textElementFocused: Bool?,
        focusedRole: String?,
        focusedTitle: String?,
        pointerX: Double,
        pointerY: Double
    ) {
        self.text = text
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.textElementFocused = textElementFocused
        self.focusedRole = focusedRole
        self.focusedTitle = focusedTitle
        self.pointerX = pointerX
        self.pointerY = pointerY
    }
}

public enum RuntimeFalseTriggerNativeBehaviorPolicy {
    public static func isSatisfied(
        kind: RuntimeFalseTriggerKind,
        expectedInsertedText: String?,
        before: RuntimeFalseTriggerNativeSnapshot,
        after: RuntimeFalseTriggerNativeSnapshot
    ) -> Bool {
        switch kind {
        case .capitalLetter, .shiftedSymbol, .shiftAHotkey:
            guard let expectedInsertedText,
                  let beforeText = before.text,
                  let afterText = after.text else {
                return false
            }
            return afterText == beforeText + expectedInsertedText
        case .shiftTab:
            return before.text == after.text
                && (selectionChanged(before: before, after: after)
                    || focusChanged(before: before, after: after))
        case .pointerMove:
            return before.text == after.text
                && hypot(after.pointerX - before.pointerX, after.pointerY - before.pointerY) >= 5
        case .pointerClick:
            return before.text == after.text
                && (selectionChanged(before: before, after: after)
                    || focusChanged(before: before, after: after))
        case .pointerDrag:
            return before.text == after.text && (after.selectionLength ?? 0) > 0
        }
    }

    private static func selectionChanged(
        before: RuntimeFalseTriggerNativeSnapshot,
        after: RuntimeFalseTriggerNativeSnapshot
    ) -> Bool {
        before.selectionLocation != after.selectionLocation
            || before.selectionLength != after.selectionLength
    }

    private static func focusChanged(
        before: RuntimeFalseTriggerNativeSnapshot,
        after: RuntimeFalseTriggerNativeSnapshot
    ) -> Bool {
        before.textElementFocused != after.textElementFocused
            || before.focusedRole != after.focusedRole
            || before.focusedTitle != after.focusedTitle
    }
}

public struct RuntimeFalseTriggerScenario: Codable, Equatable, Sendable {
    public let id: String
    public let kind: RuntimeFalseTriggerKind
    public let holdSeconds: TimeInterval
    public let interactionStartSeconds: TimeInterval
    public let interactionDurationSeconds: TimeInterval
    public let targetIDs: [String]

    public init(
        id: String,
        kind: RuntimeFalseTriggerKind,
        holdSeconds: TimeInterval,
        interactionStartSeconds: TimeInterval,
        interactionDurationSeconds: TimeInterval,
        targetIDs: [String]
    ) {
        self.id = id
        self.kind = kind
        self.holdSeconds = holdSeconds
        self.interactionStartSeconds = interactionStartSeconds
        self.interactionDurationSeconds = interactionDurationSeconds
        self.targetIDs = targetIDs
    }

    public var textScenario: RuntimeTextScenario {
        switch kind {
        case .capitalLetter, .shiftedSymbol, .shiftAHotkey:
            return .empty
        case .shiftTab, .pointerMove, .pointerClick, .pointerDrag:
            return .existingText
        }
    }

    public static let defaultMatrix: [Self] = [
        Self(
            id: "capital-random-letter",
            kind: .capitalLetter,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "shifted-dollar",
            kind: .shiftedSymbol,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "shift-tab",
            kind: .shiftTab,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "shift-a-hotkey",
            kind: .shiftAHotkey,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-move-short",
            kind: .pointerMove,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-click-short",
            kind: .pointerClick,
            holdSeconds: 0.35,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-drag-short",
            kind: .pointerDrag,
            holdSeconds: 0.5,
            interactionStartSeconds: 0.08,
            interactionDurationSeconds: 0.2,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-click-starts-after-four-seconds",
            kind: .pointerClick,
            holdSeconds: 4.5,
            interactionStartSeconds: 4.1,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-click-ends-after-four-seconds",
            kind: .pointerClick,
            holdSeconds: 4.5,
            interactionStartSeconds: 0.2,
            interactionDurationSeconds: 4,
            targetIDs: ["textedit"]
        ),
        Self(
            id: "pointer-click-ends-before-four-second-release",
            kind: .pointerClick,
            holdSeconds: 4.5,
            interactionStartSeconds: 0.2,
            interactionDurationSeconds: 0.05,
            targetIDs: ["textedit"]
        )
    ]
}

public struct RuntimeFalseTriggerCase: Codable, Equatable, Sendable {
    public let scenario: RuntimeFalseTriggerScenario
    public let target: RuntimeTargetApp
    public let repetition: Int

    public init(scenario: RuntimeFalseTriggerScenario, target: RuntimeTargetApp, repetition: Int) {
        self.scenario = scenario
        self.target = target
        self.repetition = repetition
    }
}

public struct RuntimeFalseTriggerPlan: Codable, Equatable, Sendable {
    public let cases: [RuntimeFalseTriggerCase]

    public init(cases: [RuntimeFalseTriggerCase]) {
        self.cases = cases
    }

    public static func make(
        scenarios: [RuntimeFalseTriggerScenario],
        targets: [RuntimeTargetApp],
        repetitions: Int
    ) throws -> Self {
        guard repetitions > 0 else { throw RuntimeFalseTriggerPlanError.invalidMatrix }
        let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        var cases: [RuntimeFalseTriggerCase] = []

        for scenario in scenarios {
            guard scenario.holdSeconds > 0,
                  scenario.interactionStartSeconds >= 0,
                  scenario.interactionDurationSeconds >= 0,
                  scenario.interactionStartSeconds + scenario.interactionDurationSeconds <= scenario.holdSeconds else {
                throw RuntimeFalseTriggerPlanError.invalidTiming(scenario.id)
            }
            let selectedTargets = scenario.targetIDs.isEmpty
                ? targets
                : scenario.targetIDs.compactMap { targetsByID[$0] }
            guard !selectedTargets.isEmpty else {
                throw RuntimeFalseTriggerPlanError.missingTarget(scenario.id)
            }
            for target in selectedTargets {
                for repetition in 1...repetitions {
                    cases.append(RuntimeFalseTriggerCase(
                        scenario: scenario,
                        target: target,
                        repetition: repetition
                    ))
                }
            }
        }
        return Self(cases: cases)
    }
}

public enum RuntimeFalseTriggerPlanError: Error, Equatable, Sendable {
    case invalidMatrix
    case invalidTiming(String)
    case missingTarget(String)
}

public struct RuntimeFalseTriggerAssessment: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case passed
        case targetSetupFailed
        case shortcutFailed
        case traceMissing
        case targetCleanupFailed
        case nativeBehaviorMissing
        case shortcutNotRejected
        case recordingNotDiscarded
        case transcriptionStarted
        case textDeliveryAttempted
        case clipboardChanged
        case sideEffectObservationFailed
        case recordingArtifactCreated
        case historyChanged
    }

    public let status: Status
    public let passed: Bool

    public init(status: Status, passed: Bool) {
        self.status = status
        self.passed = passed
    }

    public static func assess(
        nativeBehaviorSatisfied: Bool,
        shortcutEvidenceRejected: Bool,
        recordingDiscarded: Bool,
        transcriptionStarted: Bool,
        textDeliveryAttempted: Bool,
        clipboardChanged: Bool,
        recordingsChanged: Bool,
        transcriptionCountChanged: Bool,
        sideEffectObservationSucceeded: Bool = true
    ) -> Self {
        guard nativeBehaviorSatisfied else { return Self(status: .nativeBehaviorMissing, passed: false) }
        guard shortcutEvidenceRejected else { return Self(status: .shortcutNotRejected, passed: false) }
        guard recordingDiscarded else { return Self(status: .recordingNotDiscarded, passed: false) }
        guard !transcriptionStarted else { return Self(status: .transcriptionStarted, passed: false) }
        guard !textDeliveryAttempted else { return Self(status: .textDeliveryAttempted, passed: false) }
        guard !clipboardChanged else { return Self(status: .clipboardChanged, passed: false) }
        guard sideEffectObservationSucceeded else {
            return Self(status: .sideEffectObservationFailed, passed: false)
        }
        guard !recordingsChanged else { return Self(status: .recordingArtifactCreated, passed: false) }
        guard !transcriptionCountChanged else { return Self(status: .historyChanged, passed: false) }
        return Self(status: .passed, passed: true)
    }
}
