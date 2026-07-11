import Foundation

public enum VoiceInkIOSDiagnosticRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case fifteenMinutes
    case oneHour
    case oneDay
    case currentSession

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fifteenMinutes: "Last 15 Minutes"
        case .oneHour: "Last Hour"
        case .oneDay: "Last 24 Hours"
        case .currentSession: "Current Session"
        }
    }

    public func startDate(now: Date, sessionStartDate: Date) -> Date {
        switch self {
        case .fifteenMinutes: now.addingTimeInterval(-15 * 60)
        case .oneHour: now.addingTimeInterval(-60 * 60)
        case .oneDay: now.addingTimeInterval(-24 * 60 * 60)
        case .currentSession: sessionStartDate
        }
    }
}

public struct VoiceInkIOSDiagnosticSystemFacts: Equatable, Sendable {
    public let appVersion: String
    public let buildVersion: String
    public let operatingSystem: String
    public let deviceModel: String
    public let physicalMemory: String
    public let selectedMode: String
    public let selectedLanguage: String
    public let microphonePermission: String
    public let keyboardRecordingState: String

    public init(
        appVersion: String,
        buildVersion: String,
        operatingSystem: String,
        deviceModel: String,
        physicalMemory: String,
        selectedMode: String,
        selectedLanguage: String,
        microphonePermission: String,
        keyboardRecordingState: String
    ) {
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.operatingSystem = operatingSystem
        self.deviceModel = deviceModel
        self.physicalMemory = physicalMemory
        self.selectedMode = selectedMode
        self.selectedLanguage = selectedLanguage
        self.microphonePermission = microphonePermission
        self.keyboardRecordingState = keyboardRecordingState
    }
}

public enum VoiceInkIOSDiagnosticSupportBundlePolicy {
    public static let noLogsMessage = "No matching app logs were found for the selected range."
    public static let defaultFilenamePrefix = "Roma_Just_Talk_iOS_Diagnostics_"

    public static func systemInformation(_ facts: VoiceInkIOSDiagnosticSystemFacts) -> String {
        [
            "=== roma just talk iOS Diagnostics ===",
            "App Version: \(facts.appVersion)",
            "Build: \(facts.buildVersion)",
            "Operating System: \(facts.operatingSystem)",
            "Device: \(facts.deviceModel)",
            "Physical Memory: \(facts.physicalMemory)",
            "Selected Mode: \(facts.selectedMode)",
            "Selected Language: \(facts.selectedLanguage)",
            "Microphone Permission: \(facts.microphonePermission)",
            "Keyboard Recording State: \(facts.keyboardRecordingState)"
        ].joined(separator: "\n")
    }

    public static func content(
        generatedAt: Date,
        range: VoiceInkIOSDiagnosticRange,
        systemInformation: String,
        logLines: [String]
    ) -> String {
        let logs = logLines.isEmpty ? [noLogsMessage] : logLines
        return [
            systemInformation,
            "Generated: \(VoiceInkDiagnosticLogExportPolicy.formattedTimestamp(generatedAt))",
            "Range: \(range.title)",
            "",
            "=== App Logs ===",
            logs.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    public static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = VoiceInkDiagnosticLogExportPolicy.fileNameDateFormat
        return "\(defaultFilenamePrefix)\(formatter.string(from: date)).log"
    }
}

public enum VoiceInkDiagnosticRedactionPolicy {
    public static let redactedText = "<redacted>"

    public static func redact(_ text: String, homeDirectory: String? = nil) -> String {
        var result = text
        if let homeDirectory, !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        result = replacing(
            pattern: #"(?i)\b(api[-_ ]?key|authorization|bearer|token|secret|password)(\s*[:=]\s*|\s+)([^\s,;]+)"#,
            in: result,
            template: "$1$2\(redactedText)"
        )
        result = replacing(
            pattern: #"(?i)([?&](?:key|api_key|token|secret)=)[^&\s]+"#,
            in: result,
            template: "$1\(redactedText)"
        )
        result = replacing(
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: result,
            options: [.caseInsensitive],
            template: redactedText
        )
        return result
    }

    private static func replacing(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}
