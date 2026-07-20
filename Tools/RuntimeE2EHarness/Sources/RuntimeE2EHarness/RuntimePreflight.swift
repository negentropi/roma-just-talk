import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreAudio
import Foundation
import RuntimeE2ECore

struct RuntimeAudioDevice: Codable {
    let id: UInt32
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int

    var isFullDuplex: Bool {
        inputChannels > 0 && outputChannels > 0
    }
}

struct RuntimeAudioFixtureInfo: Codable {
    let path: String
    let durationSeconds: Double?
    let sampleRate: Double?
    let channelCount: Int?
    let error: String?
}

struct RuntimeApplicationInfo: Codable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let installed: Bool
    let bundlePath: String?
    let version: String?
    let runningPaths: [String]
    let selectionSource: String?
}

struct RuntimePreflightReport: Codable {
    let generatedAt: Date
    let accessibilityGranted: Bool
    let audioDirectory: String
    let audioFixtures: [RuntimeAudioFixtureInfo]
    let requestedAudioDeviceName: String
    let requestedAudioDevice: RuntimeAudioDevice?
    let voiceInk: RuntimeApplicationInfo
    let targets: [RuntimeApplicationInfo]
    let selectedTargetIDs: [String]
    let skippedTargetIDs: [String]
    let targetAvailabilityPolicy: RuntimeHarnessConfiguration.TargetAvailabilityPolicy
    let minimumTargetCount: Int
    let failures: [String]
    let passed: Bool
}

enum RuntimePreflight {
    static func run(
        configuration: RuntimeHarnessConfiguration,
        promptForAccessibility: Bool = false
    ) -> RuntimePreflightReport {
        let audioDirectory = NSString(string: configuration.audioDirectory).expandingTildeInPath
        let fixtures = fixtureInfo(in: URL(fileURLWithPath: audioDirectory, isDirectory: true))
        let devices = (try? RuntimeAudioDeviceCatalog.devices()) ?? []
        let requestedDevice = devices.first {
            $0.name.localizedCaseInsensitiveCompare(configuration.audioDeviceName) == .orderedSame
        }
        let voiceInk = voiceInkApplicationInfo(configuration: configuration)
        let targets = configuration.targets.map {
            applicationInfo(id: $0.id, displayName: $0.displayName, bundleIdentifier: $0.bundleIdentifier)
        }
        let runningBundleIdentifiers = Set(
            targets
                .filter { !$0.runningPaths.isEmpty }
                .map(\.bundleIdentifier)
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
        let accessibilityGranted: Bool
        if promptForAccessibility {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibilityGranted = AXIsProcessTrusted()
        }

        var failures: [String] = []
        if !accessibilityGranted {
            failures.append("Accessibility is not granted to the runtime harness")
        }
        if fixtures.isEmpty {
            failures.append("No supported audio fixtures found in \(audioDirectory)")
        }
        if fixtures.contains(where: { $0.durationSeconds == nil }) {
            failures.append("One or more audio fixtures could not be decoded")
        }
        if requestedDevice == nil {
            failures.append("Audio device \(configuration.audioDeviceName) was not found")
        } else if requestedDevice?.isFullDuplex != true {
            failures.append("Audio device \(configuration.audioDeviceName) is not full duplex")
        }
        if !voiceInk.installed {
            failures.append("VoiceInk bundle \(configuration.voiceInkBundleIdentifier) is not installed")
        }
        switch configuration.targetAvailabilityPolicy {
        case .runningOnly:
            break
        case .launchIfNeeded:
            for target in targets where !target.installed {
                failures.append("Target app \(target.displayName) is not installed")
            }
        }
        if configuration.minimumTargetCount <= 0 {
            failures.append("minimumTargetCount must be greater than zero")
        } else if selectedTargets.count < configuration.minimumTargetCount {
            failures.append(
                "Only \(selectedTargets.count) target apps satisfy \(configuration.targetAvailabilityPolicy.rawValue); "
                + "at least \(configuration.minimumTargetCount) are required"
            )
        }

        return RuntimePreflightReport(
            generatedAt: Date(),
            accessibilityGranted: accessibilityGranted,
            audioDirectory: audioDirectory,
            audioFixtures: fixtures,
            requestedAudioDeviceName: configuration.audioDeviceName,
            requestedAudioDevice: requestedDevice,
            voiceInk: voiceInk,
            targets: targets,
            selectedTargetIDs: selectedTargetIDs,
            skippedTargetIDs: skippedTargetIDs,
            targetAvailabilityPolicy: configuration.targetAvailabilityPolicy,
            minimumTargetCount: configuration.minimumTargetCount,
            failures: failures,
            passed: failures.isEmpty
        )
    }

    private static func fixtureInfo(in directoryURL: URL) -> [RuntimeAudioFixtureInfo] {
        let supportedExtensions = Set(["wav", "wave", "aif", "aiff", "caf", "m4a", "mp3", "flac"])
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                do {
                    let file = try AVAudioFile(forReading: url)
                    let sampleRate = file.processingFormat.sampleRate
                    return RuntimeAudioFixtureInfo(
                        path: url.path,
                        durationSeconds: sampleRate > 0 ? Double(file.length) / sampleRate : nil,
                        sampleRate: sampleRate,
                        channelCount: Int(file.processingFormat.channelCount),
                        error: nil
                    )
                } catch {
                    return RuntimeAudioFixtureInfo(
                        path: url.path,
                        durationSeconds: nil,
                        sampleRate: nil,
                        channelCount: nil,
                        error: String(describing: error)
                    )
                }
            }
    }

    private static func applicationInfo(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        selectedBundleURL: URL? = nil,
        selectionSource: String? = nil
    ) -> RuntimeApplicationInfo {
        let bundleURL = selectedBundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        let runningPaths = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .compactMap { $0.bundleURL?.path }
            .sorted()
        return RuntimeApplicationInfo(
            id: id,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            installed: bundleURL != nil,
            bundlePath: bundleURL?.path,
            version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            runningPaths: runningPaths,
            selectionSource: selectionSource
        )
    }

    private static func voiceInkApplicationInfo(
        configuration: RuntimeHarnessConfiguration
    ) -> RuntimeApplicationInfo {
        let bundleIdentifier = configuration.voiceInkBundleIdentifier
        let runningPaths = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .compactMap { $0.bundleURL?.path }
        let buildDirectoryURL = URL(
            fileURLWithPath: NSString(string: configuration.voiceInkBuildDirectory).expandingTildeInPath,
            isDirectory: true
        )
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
        let selection = RuntimeVoiceInkCandidateSelector.select(
            explicitPath: configuration.voiceInkAppPath.map {
                NSString(string: $0).expandingTildeInPath
            },
            runningPaths: runningPaths,
            buildDirectoryPath: buildDirectoryURL.path,
            buildCandidates: buildCandidates,
            workspaceInstalledPath: workspacePath
        )

        return applicationInfo(
            id: "voiceink",
            displayName: "roma just talk",
            bundleIdentifier: bundleIdentifier,
            selectedBundleURL: selection.map { URL(fileURLWithPath: $0.path) },
            selectionSource: selection?.source.rawValue
        )
    }
}

enum RuntimeAudioDeviceCatalog {
    static func devices() throws -> [RuntimeAudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ))

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ))

        return ids.compactMap { id in
            guard let name = stringProperty(id, selector: kAudioDevicePropertyDeviceNameCFString),
                  let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            return RuntimeAudioDevice(
                id: id,
                uid: uid,
                name: name,
                inputChannels: channelCount(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(id, scope: kAudioDevicePropertyScopeOutput)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func stringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }

    private static func channelCount(
        _ id: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else {
            return 0
        }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw RuntimeAudioDeviceCatalogError.osStatus(status)
        }
    }
}

enum RuntimeAudioDeviceCatalogError: Error {
    case osStatus(OSStatus)
}
