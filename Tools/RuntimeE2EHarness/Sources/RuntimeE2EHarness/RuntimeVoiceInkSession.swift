import AppKit
import CoreFoundation
import Darwin
import Foundation
import RuntimeE2ECore

struct RuntimeVoiceInkSessionInfo: Codable {
    let selectedAppPath: String
    let selectionSource: RuntimeVoiceInkSelection.Source
    let audioDeviceUID: String
    let specialShortcut: RuntimeModifierShortcut
    let originallyRunningPaths: [String]
}

private struct RuntimeVoiceInkRestorationJournal: Codable {
    let bundleIdentifier: String
    let originalAudioInputMode: String?
    let originalAudioInputModeExisted: Bool
    let originalSelectedDeviceUID: String?
    let originalSelectedDeviceUIDExisted: Bool
    let originalPauseMediaEnabled: Bool?
    let originalPauseMediaEnabledExisted: Bool?
    let originalPrimaryShortcutSelection: String?
    let originalPrimaryShortcutSelectionExisted: Bool?
    let originalPrimaryShortcutMode: String?
    let originalPrimaryShortcutModeExisted: Bool?
    let originalPrimaryShortcutData: Data?
    let originalPrimaryShortcutDataExisted: Bool?
    let originalPrimaryShortcutCleared: Bool?
    let originalPrimaryShortcutClearedExisted: Bool?
    let originallyRunningPaths: [String]
}

private struct RuntimeVoiceInkPreferenceSnapshot {
    let audioInputMode: String?
    let audioInputModeExisted: Bool
    let selectedDeviceUID: String?
    let selectedDeviceUIDExisted: Bool
    let pauseMediaEnabled: Bool?
    let pauseMediaEnabledExisted: Bool
    let primaryShortcutSelection: String?
    let primaryShortcutSelectionExisted: Bool
    let primaryShortcutMode: String?
    let primaryShortcutModeExisted: Bool
    let primaryShortcutData: Data?
    let primaryShortcutDataExisted: Bool
    let primaryShortcutCleared: Bool?
    let primaryShortcutClearedExisted: Bool
    let legacyKeyboardMigrationComplete: Bool
    let legacyCustomMigrationComplete: Bool
}

private struct RuntimeStoredModifierShortcut: Encodable {
    let kind = "modifierOnly"
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt
}

final class RuntimeVoiceInkSession {
    private static let primaryShortcutSelectionKey = "primaryRecordingShortcut"
    private static let pauseMediaEnabledKey = "isPauseMediaEnabled"
    private static let primaryShortcutModeKey = "primaryRecordingShortcutMode"
    private static let primaryShortcutDataKey = "Shortcut_primaryRecording"
    private static let primaryShortcutClearedKey = "Shortcut_primaryRecording_cleared"
    private static let legacyKeyboardMigrationKey = "Shortcut_LegacyKeyboardShortcutsMigrated"
    private static let legacyCustomMigrationKey = "Shortcut_LegacyCustomRecordingShortcutsMigrated"

    let info: RuntimeVoiceInkSessionInfo
    private let journal: RuntimeVoiceInkRestorationJournal
    private let restorationScope: RuntimeRestorationScope
    private var restored = false

    private init(
        info: RuntimeVoiceInkSessionInfo,
        journal: RuntimeVoiceInkRestorationJournal,
        restorationScope: RuntimeRestorationScope
    ) {
        self.info = info
        self.journal = journal
        self.restorationScope = restorationScope
    }

    static func start(
        configuration: RuntimeHarnessConfiguration,
        audioDeviceUID: String,
        restorationScope: RuntimeRestorationScope
    ) throws -> RuntimeVoiceInkSession {
        let resolution = try resolveApplication(configuration: configuration)
        let runningPaths = runningApplications(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            .compactMap { $0.bundleURL?.path }
            .map { restorableApplicationPath($0, configuration: configuration) }
            .sorted()
        let snapshot = preferenceSnapshot(bundleIdentifier: configuration.voiceInkBundleIdentifier)
        guard snapshot.legacyKeyboardMigrationComplete,
              snapshot.legacyCustomMigrationComplete else {
            throw RuntimeVoiceInkSessionError.shortcutMigrationIncomplete
        }
        let specialShortcut = configuration.resolvedSpecialShortcut
        let journal = RuntimeVoiceInkRestorationJournal(
            bundleIdentifier: configuration.voiceInkBundleIdentifier,
            originalAudioInputMode: snapshot.audioInputMode,
            originalAudioInputModeExisted: snapshot.audioInputModeExisted,
            originalSelectedDeviceUID: snapshot.selectedDeviceUID,
            originalSelectedDeviceUIDExisted: snapshot.selectedDeviceUIDExisted,
            originalPauseMediaEnabled: snapshot.pauseMediaEnabled,
            originalPauseMediaEnabledExisted: snapshot.pauseMediaEnabledExisted,
            originalPrimaryShortcutSelection: snapshot.primaryShortcutSelection,
            originalPrimaryShortcutSelectionExisted: snapshot.primaryShortcutSelectionExisted,
            originalPrimaryShortcutMode: snapshot.primaryShortcutMode,
            originalPrimaryShortcutModeExisted: snapshot.primaryShortcutModeExisted,
            originalPrimaryShortcutData: snapshot.primaryShortcutData,
            originalPrimaryShortcutDataExisted: snapshot.primaryShortcutDataExisted,
            originalPrimaryShortcutCleared: snapshot.primaryShortcutCleared,
            originalPrimaryShortcutClearedExisted: snapshot.primaryShortcutClearedExisted,
            originallyRunningPaths: runningPaths
        )
        try writeJournal(journal, to: restorationScope.voiceInkJournalURL)

        do {
            try terminateRunningApplications(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            setPreference("Custom Device", key: "audioInputMode", bundleIdentifier: configuration.voiceInkBundleIdentifier)
            setPreference(audioDeviceUID, key: "selectedAudioDeviceUID", bundleIdentifier: configuration.voiceInkBundleIdentifier)
            setBoolPreference(
                false,
                key: pauseMediaEnabledKey,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            setPreference(
                "custom",
                key: primaryShortcutSelectionKey,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            setPreference(
                "special",
                key: primaryShortcutModeKey,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            let storedShortcut = RuntimeStoredModifierShortcut(
                keyCode: specialShortcut.keyCode,
                modifierFlagsRawValue: modifierFlagsRawValue(for: specialShortcut.modifierFlag)
            )
            setDataPreference(
                try JSONEncoder().encode(storedShortcut),
                key: primaryShortcutDataKey,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            removePreference(
                key: primaryShortcutClearedKey,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
            try synchronize(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            try launchApplication(
                atPath: resolution.path,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
        } catch {
            try? restoreFromJournal(in: restorationScope)
            throw error
        }

        return RuntimeVoiceInkSession(
            info: RuntimeVoiceInkSessionInfo(
                selectedAppPath: resolution.path,
                selectionSource: resolution.source,
                audioDeviceUID: audioDeviceUID,
                specialShortcut: specialShortcut,
                originallyRunningPaths: runningPaths
            ),
            journal: journal,
            restorationScope: restorationScope
        )
    }

    func restore() throws {
        guard !restored else { return }
        try Self.restore(journal: journal, in: restorationScope)
        if FileManager.default.fileExists(atPath: restorationScope.voiceInkJournalURL.path) {
            try FileManager.default.removeItem(at: restorationScope.voiceInkJournalURL)
        }
        restored = true
    }

    func relaunchForRun(bundleIdentifier: String) throws {
        try Self.terminateRunningApplications(bundleIdentifier: bundleIdentifier)
        try Self.launchApplication(atPath: info.selectedAppPath, bundleIdentifier: bundleIdentifier)
    }

    func terminateForSideEffectRestoration() throws {
        try Self.terminateRunningApplications(bundleIdentifier: journal.bundleIdentifier)
    }

    static func restoreFromJournal(in restorationScope: RuntimeRestorationScope) throws {
        let journalURL = restorationScope.voiceInkJournalURL
        let data = try Data(contentsOf: journalURL)
        let journal = try JSONDecoder().decode(RuntimeVoiceInkRestorationJournal.self, from: data)
        try restore(journal: journal, in: restorationScope)
        try FileManager.default.removeItem(at: journalURL)
    }

    static func restoreOrphanedFalseTriggerArtifacts(
        in restorationScope: RuntimeRestorationScope
    ) throws {
        let sideEffectJournalURL = restorationScope.falseTriggerSideEffectJournalURL
        let bundleIdentifier = try RuntimeFalseTriggerSideEffectObserver
            .pendingRestorationBundleIdentifier(at: sideEffectJournalURL)
        let runningPaths = runningApplications(bundleIdentifier: bundleIdentifier)
            .compactMap { $0.bundleURL?.path }
            .sorted()
        try terminateRunningApplications(bundleIdentifier: bundleIdentifier)
        _ = try RuntimeFalseTriggerSideEffectObserver.restoreFromJournal(
            at: sideEffectJournalURL
        )
        for path in runningPaths {
            try launchApplication(atPath: path, bundleIdentifier: bundleIdentifier)
        }
    }

    private static func restore(
        journal: RuntimeVoiceInkRestorationJournal,
        in restorationScope: RuntimeRestorationScope
    ) throws {
        try terminateRunningApplications(bundleIdentifier: journal.bundleIdentifier)
        if FileManager.default.fileExists(
            atPath: restorationScope.falseTriggerSideEffectJournalURL.path
        ) {
            _ = try RuntimeFalseTriggerSideEffectObserver.restoreFromJournal(
                at: restorationScope.falseTriggerSideEffectJournalURL
            )
        }
        restorePreference(
            journal.originalAudioInputMode,
            existed: journal.originalAudioInputModeExisted,
            key: "audioInputMode",
            bundleIdentifier: journal.bundleIdentifier
        )
        restorePreference(
            journal.originalSelectedDeviceUID,
            existed: journal.originalSelectedDeviceUIDExisted,
            key: "selectedAudioDeviceUID",
            bundleIdentifier: journal.bundleIdentifier
        )
        if let existed = journal.originalPauseMediaEnabledExisted {
            restoreBoolPreference(
                journal.originalPauseMediaEnabled,
                existed: existed,
                key: pauseMediaEnabledKey,
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        if let existed = journal.originalPrimaryShortcutSelectionExisted {
            restorePreference(
                journal.originalPrimaryShortcutSelection,
                existed: existed,
                key: primaryShortcutSelectionKey,
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        if let existed = journal.originalPrimaryShortcutModeExisted {
            restorePreference(
                journal.originalPrimaryShortcutMode,
                existed: existed,
                key: primaryShortcutModeKey,
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        if let existed = journal.originalPrimaryShortcutDataExisted {
            restoreDataPreference(
                journal.originalPrimaryShortcutData,
                existed: existed,
                key: primaryShortcutDataKey,
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        if let existed = journal.originalPrimaryShortcutClearedExisted {
            restoreBoolPreference(
                journal.originalPrimaryShortcutCleared,
                existed: existed,
                key: primaryShortcutClearedKey,
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        try synchronize(bundleIdentifier: journal.bundleIdentifier)
        for path in journal.originallyRunningPaths {
            try launchApplication(atPath: path, bundleIdentifier: journal.bundleIdentifier)
        }
    }

    private static func resolveApplication(
        configuration: RuntimeHarnessConfiguration
    ) throws -> RuntimeVoiceInkSelection {
        let bundleIdentifier = configuration.voiceInkBundleIdentifier
        let runningPaths = runningApplications(bundleIdentifier: bundleIdentifier)
            .compactMap { $0.bundleURL?.path }
        let buildDirectoryPath = NSString(string: configuration.voiceInkBuildDirectory).expandingTildeInPath
        let buildDirectoryURL = URL(fileURLWithPath: buildDirectoryPath, isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        let buildCandidates = ((try? FileManager.default.contentsOfDirectory(
            at: buildDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []).compactMap { url -> RuntimeVoiceInkCandidate? in
            guard url.pathExtension.lowercased() == "app",
                  Bundle(url: url)?.bundleIdentifier == bundleIdentifier,
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isDirectory == true else {
                return nil
            }
            return RuntimeVoiceInkCandidate(
                path: url.path,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        let workspacePath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?.path
        guard let selection = RuntimeVoiceInkCandidateSelector.select(
            explicitPath: configuration.voiceInkAppPath.map {
                NSString(string: $0).expandingTildeInPath
            },
            runningPaths: runningPaths,
            buildDirectoryPath: buildDirectoryPath,
            buildCandidates: buildCandidates,
            workspaceInstalledPath: workspacePath
        ) else {
            throw RuntimeVoiceInkSessionError.applicationNotFound(bundleIdentifier)
        }
        return selection
    }

    private static func restorableApplicationPath(
        _ runningPath: String,
        configuration: RuntimeHarnessConfiguration
    ) -> String {
        guard runningPath.contains("/AppTranslocation/") else { return runningPath }
        let buildDirectoryPath = NSString(
            string: configuration.voiceInkBuildDirectory
        ).expandingTildeInPath
        let candidate = URL(fileURLWithPath: buildDirectoryPath, isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: runningPath).lastPathComponent)
        guard Bundle(url: candidate)?.bundleIdentifier == configuration.voiceInkBundleIdentifier else {
            return runningPath
        }
        return candidate.path
    }

    private static func preferenceSnapshot(
        bundleIdentifier: String
    ) -> RuntimeVoiceInkPreferenceSnapshot {
        let appID = bundleIdentifier as CFString
        let audioMode = CFPreferencesCopyAppValue("audioInputMode" as CFString, appID)
        let deviceUID = CFPreferencesCopyAppValue("selectedAudioDeviceUID" as CFString, appID)
        let pauseMediaEnabled = CFPreferencesCopyAppValue(pauseMediaEnabledKey as CFString, appID)
        let primarySelection = CFPreferencesCopyAppValue(primaryShortcutSelectionKey as CFString, appID)
        let primaryMode = CFPreferencesCopyAppValue(primaryShortcutModeKey as CFString, appID)
        let primaryData = CFPreferencesCopyAppValue(primaryShortcutDataKey as CFString, appID)
        let primaryCleared = CFPreferencesCopyAppValue(primaryShortcutClearedKey as CFString, appID)
        let legacyKeyboardMigration = CFPreferencesCopyAppValue(legacyKeyboardMigrationKey as CFString, appID)
        let legacyCustomMigration = CFPreferencesCopyAppValue(legacyCustomMigrationKey as CFString, appID)
        return RuntimeVoiceInkPreferenceSnapshot(
            audioInputMode: audioMode as? String,
            audioInputModeExisted: audioMode != nil,
            selectedDeviceUID: deviceUID as? String,
            selectedDeviceUIDExisted: deviceUID != nil,
            pauseMediaEnabled: pauseMediaEnabled as? Bool,
            pauseMediaEnabledExisted: pauseMediaEnabled != nil,
            primaryShortcutSelection: primarySelection as? String,
            primaryShortcutSelectionExisted: primarySelection != nil,
            primaryShortcutMode: primaryMode as? String,
            primaryShortcutModeExisted: primaryMode != nil,
            primaryShortcutData: primaryData as? Data,
            primaryShortcutDataExisted: primaryData != nil,
            primaryShortcutCleared: primaryCleared as? Bool,
            primaryShortcutClearedExisted: primaryCleared != nil,
            legacyKeyboardMigrationComplete: legacyKeyboardMigration as? Bool == true,
            legacyCustomMigrationComplete: legacyCustomMigration as? Bool == true
        )
    }

    private static func setPreference(
        _ value: String,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            value as CFString,
            bundleIdentifier as CFString
        )
    }

    private static func restorePreference(
        _ value: String?,
        existed: Bool,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            existed ? value as CFString? : nil,
            bundleIdentifier as CFString
        )
    }

    private static func setDataPreference(
        _ value: Data,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            value as CFData,
            bundleIdentifier as CFString
        )
    }

    private static func setBoolPreference(
        _ value: Bool,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            value as CFBoolean,
            bundleIdentifier as CFString
        )
    }

    private static func restoreDataPreference(
        _ value: Data?,
        existed: Bool,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            existed ? value as CFData? : nil,
            bundleIdentifier as CFString
        )
    }

    private static func restoreBoolPreference(
        _ value: Bool?,
        existed: Bool,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            existed ? value as CFBoolean? : nil,
            bundleIdentifier as CFString
        )
    }

    private static func removePreference(key: String, bundleIdentifier: String) {
        CFPreferencesSetAppValue(
            key as CFString,
            nil,
            bundleIdentifier as CFString
        )
    }

    private static func modifierFlagsRawValue(for flag: RuntimeModifierFlag) -> UInt {
        switch flag {
        case .shift: NSEvent.ModifierFlags.shift.rawValue
        case .control: NSEvent.ModifierFlags.control.rawValue
        case .option: NSEvent.ModifierFlags.option.rawValue
        case .command: NSEvent.ModifierFlags.command.rawValue
        case .function: NSEvent.ModifierFlags.function.rawValue
        }
    }

    private static func synchronize(bundleIdentifier: String) throws {
        guard CFPreferencesAppSynchronize(bundleIdentifier as CFString) else {
            throw RuntimeVoiceInkSessionError.preferenceSynchronizationFailed
        }
    }

    private static func runningApplications(bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    private static func terminateRunningApplications(bundleIdentifier: String) throws {
        let applications = runningApplications(bundleIdentifier: bundleIdentifier)
        let processIdentifiers = applications.map(\.processIdentifier)
        for application in applications {
            _ = application.terminate()
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let capturedProcessesExited = processIdentifiers.allSatisfy {
                !processExists(processIdentifier: $0)
            }
            if capturedProcessesExited,
               runningApplications(bundleIdentifier: bundleIdentifier).isEmpty {
                return
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeVoiceInkSessionError.applicationWouldNotTerminate
    }

    private static func processExists(processIdentifier: pid_t) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    private static func launchApplication(atPath path: String, bundleIdentifier: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-n", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeVoiceInkSessionError.launchFailed(path)
        }

        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if runningApplications(bundleIdentifier: bundleIdentifier).contains(where: {
                $0.bundleURL?.standardizedFileURL.path == standardizedPath
            }) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeVoiceInkSessionError.launchTimedOut(path)
    }

    private static func writeJournal(
        _ journal: RuntimeVoiceInkRestorationJournal,
        to journalURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)
    }
}

enum RuntimeVoiceInkSessionError: Error, CustomStringConvertible {
    case applicationNotFound(String)
    case applicationWouldNotTerminate
    case preferenceSynchronizationFailed
    case launchFailed(String)
    case launchTimedOut(String)
    case shortcutMigrationIncomplete

    var description: String {
        switch self {
        case .applicationNotFound(let identifier):
            return "Could not resolve VoiceInk app for \(identifier)"
        case .applicationWouldNotTerminate:
            return "VoiceInk did not terminate within 10 seconds; preferences were not changed"
        case .preferenceSynchronizationFailed:
            return "Could not synchronize VoiceInk audio preferences"
        case .launchFailed(let path):
            return "Could not launch VoiceInk at \(path)"
        case .launchTimedOut(let path):
            return "VoiceInk launch timed out at \(path)"
        case .shortcutMigrationIncomplete:
            return "VoiceInk shortcut migration must complete before the runtime harness can preserve shortcut state"
        }
    }
}
