import Foundation

public enum ChineseDateFormatting {
    private static let locale = Locale(identifier: "zh_CN")

    public static func date(
        _ date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: locale,
                timeZone: timeZone
            )
            .year()
            .month(.wide)
            .day()
        )
    }

    public static func dateTime(
        _ date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: locale,
                timeZone: timeZone
            )
            .year()
            .month(.wide)
            .day()
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        )
    }

    public static func fullDate(
        _ date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let weekday = date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: locale,
                timeZone: timeZone
            )
            .weekday(.wide)
        )
        return "\(self.date(date, timeZone: timeZone)) \(weekday)"
    }

    public static func time(
        _ date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: locale,
                timeZone: timeZone
            )
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        )
    }
}
