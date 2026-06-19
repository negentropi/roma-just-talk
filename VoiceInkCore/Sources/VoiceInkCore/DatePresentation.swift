import Foundation

public enum VoiceInkDatePresentation {
    public static func abbreviatedTimestamp(
        _ date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        ))
    }

    public static func compactTimestamp(
        _ date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        .month(.abbreviated)
        .day()
        .hour()
        .minute())
    }

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
