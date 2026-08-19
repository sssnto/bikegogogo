import Foundation
import Testing
@testable import BikeGoGoCore

struct ChineseDateFormattingTests {
    private let beijing = TimeZone(identifier: "Asia/Shanghai")!

    @Test func formatsChineseDateVariants() throws {
        let date = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: beijing,
                    year: 2026,
                    month: 8,
                    day: 9,
                    hour: 15,
                    minute: 35
                )
            )
        )

        #expect(ChineseDateFormatting.date(date, timeZone: beijing) == "2026年8月9日")
        #expect(ChineseDateFormatting.dateTime(date, timeZone: beijing) == "2026年8月9日 15:35")
        #expect(ChineseDateFormatting.fullDate(date, timeZone: beijing) == "2026年8月9日 星期日")
        #expect(ChineseDateFormatting.time(date, timeZone: beijing) == "15:35")
    }
}
