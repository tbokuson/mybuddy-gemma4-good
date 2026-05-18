import XCTest
@testable import MyBuddy

final class BuddyStateTests: XCTestCase {
    func testRecordCheckInCountsNextAppDayAcrossFourAMBoundary() throws {
        let state = BuddyState(buddyId: UUID())
        let calendar = Calendar(identifier: .gregorian)
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 3, minute: 30)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 5, minute: 10)))

        state.recordCheckIn(at: first)
        state.recordCheckIn(at: second)

        XCTAssertEqual(state.streakDays, 2)
        XCTAssertEqual(state.lastCheckInDate, second)
    }

    func testRecordCheckInDoesNotIncrementTwiceOnSameAppDay() throws {
        let state = BuddyState(buddyId: UUID())
        let calendar = Calendar(identifier: .gregorian)
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 10, minute: 0)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 23, minute: 0)))

        state.recordCheckIn(at: first)
        state.recordCheckIn(at: second)

        XCTAssertEqual(state.streakDays, 1)
        XCTAssertEqual(state.lastCheckInDate, second)
    }
}
