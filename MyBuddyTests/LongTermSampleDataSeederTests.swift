#if DEBUG
import SwiftData
import XCTest
@testable import MyBuddy

@MainActor
final class LongTermSampleDataSeederTests: XCTestCase {
    func testConfigurationRequiresExplicitFlag() {
        XCTAssertNil(LongTermSampleDataSeeder.configuration(arguments: [], environment: [:]))

        let fromArgument = LongTermSampleDataSeeder.configuration(
            arguments: ["MyBuddy", "--mybuddy-seed-long-term-data"],
            environment: [:]
        )
        XCTAssertEqual(fromArgument?.dayCount, LongTermSampleDataSeeder.Configuration.defaultDayCount)
        XCTAssertEqual(fromArgument?.resetBeforeSeeding, false)

        let fromEnvironment = LongTermSampleDataSeeder.configuration(
            arguments: ["MyBuddy"],
            environment: [
                "MYBUDDY_SEED_LONG_TERM_DATA": "1",
                "MYBUDDY_RESET_BEFORE_LONG_TERM_SEED": "1",
                "MYBUDDY_LONG_TERM_SEED_DAYS": "12"
            ]
        )
        XCTAssertEqual(fromEnvironment?.dayCount, 12)
        XCTAssertEqual(fromEnvironment?.resetBeforeSeeding, true)
    }

    func testDayCountIsClampedToSafeBounds() {
        XCTAssertEqual(LongTermSampleDataSeeder.clampedDayCount(-10), 1)
        XCTAssertEqual(LongTermSampleDataSeeder.clampedDayCount(90), 90)
        XCTAssertEqual(LongTermSampleDataSeeder.clampedDayCount(10_000), 365)
    }

    func testSeedCreatesLongTermDataset() throws {
        let context = try makeContext()

        let result = try LongTermSampleDataSeeder.seedIfNeeded(
            in: context,
            configuration: .init(dayCount: 14, resetBeforeSeeding: false)
        )

        XCTAssertFalse(result.skippedBecauseDataExists)
        XCTAssertEqual(result.insertedDays, 14)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuddyProfile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuddyState>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 14)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiaryNote>()), 42)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationSession>()), 14)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChatMessage>()), 84)
    }

    func testSeedSkipsWhenUserAlreadyExistsWithoutReset() throws {
        let context = try makeContext()
        context.insert(UserProfile(nickname: "既存", onboardingCompleted: true))
        try context.save()

        let result = try LongTermSampleDataSeeder.seedIfNeeded(
            in: context,
            configuration: .init(dayCount: 10, resetBeforeSeeding: false)
        )

        XCTAssertTrue(result.skippedBecauseDataExists)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 0)
    }

    func testSeedResetsExistingDataWhenRequested() throws {
        let context = try makeContext()
        context.insert(UserProfile(nickname: "既存", onboardingCompleted: true))
        context.insert(JournalEntry(title: "古い日記", summaryText: "古い", fullDiaryText: "古い"))
        try context.save()

        let result = try LongTermSampleDataSeeder.seedIfNeeded(
            in: context,
            configuration: .init(dayCount: 5, resetBeforeSeeding: true)
        )

        XCTAssertFalse(result.skippedBecauseDataExists)
        XCTAssertEqual(result.insertedDays, 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 5)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            BuddyProfile.self,
            BuddyState.self,
            JournalEntry.self,
            ConversationSession.self,
            ChatMessage.self,
            DiaryNote.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }
}
#endif
