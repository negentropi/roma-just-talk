import Foundation

public enum VoiceInkPowerModeBrowser: Equatable, Sendable {
    case safari
    case arc
    case chrome
    case edge
    case firefox
    case brave
    case opera
    case vivaldi
    case orion
    case zen
    case yandex

    public var scriptName: String {
        switch self {
        case .safari: return "safariURL"
        case .arc: return "arcURL"
        case .chrome: return "chromeURL"
        case .edge: return "edgeURL"
        case .firefox: return "firefoxURL"
        case .brave: return "braveURL"
        case .opera: return "operaURL"
        case .vivaldi: return "vivaldiURL"
        case .orion: return "orionURL"
        case .zen: return "zenURL"
        case .yandex: return "yandexURL"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .arc: return "company.thebrowser.Browser"
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .firefox: return "org.mozilla.firefox"
        case .brave: return "com.brave.Browser"
        case .opera: return "com.operasoftware.Opera"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .orion: return "com.kagi.kagimacOS"
        case .zen: return "app.zen-browser.zen"
        case .yandex: return "ru.yandex.desktop.yandex-browser"
        }
    }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .arc: return "Arc"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .firefox: return "Firefox"
        case .brave: return "Brave"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion: return "Orion"
        case .zen: return "Zen Browser"
        case .yandex: return "Yandex Browser"
        }
    }

    public static let allCases: [VoiceInkPowerModeBrowser] = [
        .safari,
        .arc,
        .chrome,
        .edge,
        .brave,
        .opera,
        .vivaldi,
        .orion,
        .yandex
    ]
}

public enum VoiceInkPowerModeBrowserURLDiagnostics {
    public static let loggerCategory = "browser.applescript"

    public static func scriptNotFoundMessage(scriptName: String) -> String {
        "❌ AppleScript file not found: \(scriptName).scpt"
    }

    public static func attemptingExecutionMessage(browserDisplayName: String) -> String {
        "🔍 Attempting to execute AppleScript for \(browserDisplayName)"
    }

    public static func browserNotRunningMessage(browserDisplayName: String) -> String {
        "❌ Browser not running: \(browserDisplayName)"
    }

    public static func executingScriptMessage(browserDisplayName: String) -> String {
        "▶️ Executing AppleScript for \(browserDisplayName)"
    }

    public static func emptyOutputMessage(browserDisplayName: String) -> String {
        "❌ Empty output from AppleScript for \(browserDisplayName)"
    }

    public static func scriptErrorMessage(browserDisplayName: String, output: String) -> String {
        "❌ AppleScript error for \(browserDisplayName): \(output)"
    }

    public static func successMessage(browserDisplayName: String, output: String) -> String {
        "✅ Successfully retrieved URL from \(browserDisplayName): \(output)"
    }

    public static func outputDecodeFailedMessage(browserDisplayName: String) -> String {
        "❌ Failed to decode output from AppleScript for \(browserDisplayName)"
    }

    public static func executionFailedMessage(
        browserDisplayName: String,
        localizedDescription: String
    ) -> String {
        "❌ AppleScript execution failed for \(browserDisplayName): \(localizedDescription)"
    }

    public static func runningStatusMessage(browserDisplayName: String, isRunning: Bool) -> String {
        "\(browserDisplayName) running status: \(isRunning)"
    }
}
