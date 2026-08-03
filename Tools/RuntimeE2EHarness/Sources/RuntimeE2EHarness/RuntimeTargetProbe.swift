import AppKit
import Foundation
import RuntimeE2ECore

struct RuntimeTargetProbeCaseReport: Codable {
    let target: RuntimeTargetApp
    let preparation: RuntimeTargetPreparationInfo?
    let cleanup: RuntimeTargetCleanupInfo?
    let passed: Bool
    let error: String?
}

struct RuntimeTargetProbeReport: Codable {
    let generatedAt: Date
    let targetAvailabilityPolicy: RuntimeHarnessConfiguration.TargetAvailabilityPolicy
    let minimumTargetCount: Int
    let selectedTargetIDs: [String]
    let skippedTargetIDs: [String]
    let abandonedTargetCleanup: RuntimeAbandonedTargetCleanupInfo
    let cases: [RuntimeTargetProbeCaseReport]
    let failures: [String]
    let passed: Bool
}

enum RuntimeTargetProbe {
    static func run(configuration: RuntimeHarnessConfiguration) -> RuntimeTargetProbeReport {
        let runningBundleIdentifiers = Set(
            configuration.targets.compactMap { target in
                NSRunningApplication.runningApplications(
                    withBundleIdentifier: target.bundleIdentifier
                ).isEmpty ? nil : target.bundleIdentifier
            }
        )
        let selectedTargets = RuntimeTargetAvailabilitySelector.select(
            configuredTargets: configuration.targets,
            runningBundleIdentifiers: runningBundleIdentifiers,
            policy: configuration.targetAvailabilityPolicy
        )
        let selectedTargetIDs = selectedTargets.map(\.id)
        let skippedTargetIDs = configuration.targets
            .filter { !selectedTargetIDs.contains($0.id) }
            .map(\.id)
        var failures: [String] = []

        if selectedTargets.count < configuration.minimumTargetCount {
            failures.append(
                "Only \(selectedTargets.count) target apps satisfy "
                + "\(configuration.targetAvailabilityPolicy.rawValue); "
                + "at least \(configuration.minimumTargetCount) are required"
            )
        }
        let abandonedTargetCleanup = RuntimeTargetController.restoreAbandonedTargets(
            targets: RuntimeTargetCatalog.restorationTargets(
                configuredTargets: configuration.targets
            )
        )
        if !abandonedTargetCleanup.passed {
            failures.append("Could not restore abandoned target surfaces")
        }

        var cases: [RuntimeTargetProbeCaseReport] = []
        if failures.isEmpty {
            for target in selectedTargets {
                for textScenario in RuntimeTextScenario.allCases {
                    var preparedTarget: RuntimePreparedTarget?
                    do {
                        let prepared = try RuntimeTargetController.prepare(
                            target: target,
                            textScenario: textScenario,
                            runID: "target-probe-\(target.id)-\(textScenario.rawValue)-r1-\(UUID().uuidString.prefix(6))",
                            settleSeconds: configuration.targetSettleSeconds,
                            availabilityPolicy: configuration.targetAvailabilityPolicy
                        )
                        preparedTarget = prepared
                        let cleanup = prepared.cleanup()
                        cases.append(
                            RuntimeTargetProbeCaseReport(
                                target: target,
                                preparation: prepared.info,
                                cleanup: cleanup,
                                passed: cleanup.passed,
                                error: cleanup.passed ? nil : cleanup.errors.joined(separator: "; ")
                            )
                        )
                    } catch {
                        cases.append(
                            RuntimeTargetProbeCaseReport(
                                target: target,
                                preparation: preparedTarget?.info,
                                cleanup: nil,
                                passed: false,
                                error: String(describing: error)
                            )
                        )
                    }
                }
            }
        }

        let passed = failures.isEmpty
            && cases.count >= configuration.minimumTargetCount
            && cases.allSatisfy(\.passed)
        return RuntimeTargetProbeReport(
            generatedAt: Date(),
            targetAvailabilityPolicy: configuration.targetAvailabilityPolicy,
            minimumTargetCount: configuration.minimumTargetCount,
            selectedTargetIDs: selectedTargetIDs,
            skippedTargetIDs: skippedTargetIDs,
            abandonedTargetCleanup: abandonedTargetCleanup,
            cases: cases,
            failures: failures,
            passed: passed
        )
    }
}
