import Foundation

public enum VoiceInkDatePresentation {
    public static func relativeTimestamp(
        _ date: Date,
        relativeTo referenceDate: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
