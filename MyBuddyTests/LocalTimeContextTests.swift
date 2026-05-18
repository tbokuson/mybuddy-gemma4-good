import XCTest
@testable import MyBuddy

final class LocalTimeContextTests: XCTestCase {

    func testMidnightIsDeepNightInTokyo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Asia/Tokyo"),
            year: 2026,
            month: 4,
            day: 13,
            hour: 0,
            minute: 15
        ))!

        let context = LocalTimeContext.make(now: date, timeZoneIdentifier: "Asia/Tokyo")

        XCTAssertEqual(context.timeSlot, "深夜")
        XCTAssertTrue(context.chatTimeHint.contains("今日一日ここまで"))
    }

    func testMorningStaysMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Asia/Tokyo"),
            year: 2026,
            month: 4,
            day: 13,
            hour: 8,
            minute: 0
        ))!

        let context = LocalTimeContext.make(now: date, timeZoneIdentifier: "Asia/Tokyo")

        XCTAssertEqual(context.timeSlot, "朝")
    }

    func testAfternoonHintPrefersTodaySoFarOverCurrentStateQuestion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Asia/Tokyo"),
            year: 2026,
            month: 4,
            day: 13,
            hour: 14,
            minute: 0
        ))!

        let context = LocalTimeContext.make(now: date, timeZoneIdentifier: "Asia/Tokyo")

        XCTAssertEqual(context.timeSlot, "昼〜午後")
        XCTAssertTrue(context.chatTimeHint.contains("今日ここまでの出来事"))
        XCTAssertFalse(context.chatTimeHint.contains("今何してる"))
    }
}
