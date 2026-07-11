import AVFoundation
import Combine
import CoreTransferable
import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers
import VoiceInkCore

struct VoiceInkIOSDiagnosticExport: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.filename)
            try export.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

@MainActor
final class IOSDiagnosticExporter: ObservableObject {
    @Published private(set) var export: VoiceInkIOSDiagnosticExport?
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?

    private let sessionStartDate: Date
    private let settings: AppSettings

    init(sessionStartDate: Date = Date(), settings: AppSettings) {
        self.sessionStartDate = sessionStartDate
        self.settings = settings
    }

    convenience init() {
        self.init(settings: .shared)
    }

    func prepare(range: VoiceInkIOSDiagnosticRange) {
        isPreparing = true
        export = nil
        do {
            let now = Date()
            let content = try makeContent(range: range, now: now)
            export = VoiceInkIOSDiagnosticExport(
                data: Data(content.utf8),
                filename: VoiceInkIOSDiagnosticSupportBundlePolicy.filename(for: now)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    private func makeContent(
        range: VoiceInkIOSDiagnosticRange,
        now: Date
    ) throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let startDate = range.startDate(now: now, sessionStartDate: sessionStartDate)
        let position = store.position(date: startDate)
        let predicate = NSPredicate(
            format: "subsystem == %@",
            VoiceInkAppIdentity.loggingSubsystem
        )
        let entries = try store.getEntries(at: position, matching: predicate)
        var lines = [String]()
        for entry in entries {
            guard let log = entry as? OSLogEntryLog, log.date <= now else { continue }
            let line = VoiceInkDiagnosticLogExportPolicy.logEntryLine(
                date: log.date,
                level: VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: log.level),
                category: log.category,
                message: log.composedMessage
            )
            lines.append(VoiceInkDiagnosticRedactionPolicy.redact(
                line,
                homeDirectory: NSHomeDirectory()
            ))
        }

        return VoiceInkIOSDiagnosticSupportBundlePolicy.content(
            generatedAt: now,
            range: range,
            systemInformation: VoiceInkDiagnosticRedactionPolicy.redact(
                VoiceInkIOSDiagnosticSupportBundlePolicy.systemInformation(systemFacts),
                homeDirectory: NSHomeDirectory()
            ),
            logLines: lines
        )
    }

    private var systemFacts: VoiceInkIOSDiagnosticSystemFacts {
        let device = UIDevice.current
        let selectedMode = settings.modes.first { $0.id == settings.selectedModeId }?.name ?? "None"
        return VoiceInkIOSDiagnosticSystemFacts(
            appVersion: knownBundleText("CFBundleShortVersionString"),
            buildVersion: knownBundleText("CFBundleVersion"),
            operatingSystem: "\(device.systemName) \(device.systemVersion)",
            deviceModel: device.model,
            physicalMemory: ByteCountFormatter.string(
                fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
                countStyle: .memory
            ),
            selectedMode: selectedMode,
            selectedLanguage: settings.selectedTranscriptionLanguage,
            microphonePermission: VoiceInkIOSMicrophonePermissionPresentation.status(
                IOSMicrophonePermissionAdapter.currentStatus()
            ).title,
            keyboardRecordingState: AppGroupCoordinator.shared.isRecording ? "Recording" : "Idle"
        )
    }

    private func knownBundleText(_ key: String) -> String {
        VoiceInkSystemInformationReport.knownText(Bundle.main.infoDictionary?[key] as? String)
    }
}
