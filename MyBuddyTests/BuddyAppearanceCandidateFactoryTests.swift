import XCTest
@testable import MyBuddy

final class BuddyAppearanceCandidateFactoryTests: XCTestCase {
    func testMakeDefaultUsesFixedStarterMonster() {
        let seed = BuddySeed.makeDefault()

        XCTAssertEqual(seed.characterType, "monster")
        XCTAssertEqual(seed.bodyId, "round")
        XCTAssertEqual(seed.eyeId, "sparkle")
        XCTAssertEqual(seed.earId, "round")
        XCTAssertEqual(seed.mouthId, "smile")
        XCTAssertEqual(seed.paletteId, "pastel")
    }

    func testMonsterCandidatesPreservePersonality() {
        var seed = BuddySeed.makeRandomMonster(
            personaStyle: .cool,
            conversationDistance: .frank,
            memoryPreference: .feelingAware,
            customTraits: "関西弁で",
            personaStyleCustom: "ツンデレ",
            conversationDistanceCustom: "ズバッと",
            memoryPreferenceCustom: "気持ち多め"
        )
        seed.personalityNotes = "夜型"

        let candidates = BuddyAppearanceCandidateFactory.makeCandidates(from: seed)

        XCTAssertEqual(candidates.count, BuddyAppearanceCandidateFactory.candidateCount)
        XCTAssertTrue(candidates.allSatisfy { $0.characterType == "monster" })
        XCTAssertTrue(candidates.allSatisfy { $0.personaStyle == .cool })
        XCTAssertTrue(candidates.allSatisfy { $0.conversationDistance == .frank })
        XCTAssertTrue(candidates.allSatisfy { $0.memoryPreference == .feelingAware })
        XCTAssertTrue(candidates.allSatisfy { $0.customTraits == "関西弁で" })
        XCTAssertTrue(candidates.allSatisfy { $0.personalityNotes == "夜型" })
    }

    func testOjisanCandidatesPreserveCharacterType() {
        let seed = BuddySeed.makeRandomOjisan(personaStyle: .gentle, conversationDistance: .casual)
        let candidates = BuddyAppearanceCandidateFactory.makeCandidates(from: seed)

        XCTAssertEqual(candidates.count, BuddyAppearanceCandidateFactory.candidateCount)
        XCTAssertTrue(candidates.allSatisfy { $0.characterType == "ojisan" })
        XCTAssertTrue(candidates.allSatisfy { $0.personaStyle == seed.personaStyle })
        XCTAssertTrue(candidates.allSatisfy { $0.conversationDistance == seed.conversationDistance })
    }

    func testOjisanCandidatesDoNotDuplicateBodyId() {
        let base = BuddySeed.makeOjisan(
            variant: "ojisan_keibu",
            personaStyle: .cool,
            conversationDistance: .frank,
            memoryPreference: .feelingAware,
            customTraits: "関西弁で話して",
            personaStyleCustom: "警部っぽく",
            conversationDistanceCustom: "ズバッと",
            memoryPreferenceCustom: "気持ちも残す"
        )

        let candidates = BuddyAppearanceCandidateFactory.makeCandidates(from: base, kind: .ojisan)
        let bodyIds = candidates.map(\.bodyId)

        XCTAssertEqual(candidates.count, BuddyAppearanceCandidateFactory.candidateCount)
        XCTAssertEqual(Set(bodyIds).count, candidates.count)
        XCTAssertTrue(candidates.allSatisfy { $0.customTraits == "関西弁で話して" })
        XCTAssertTrue(candidates.allSatisfy { $0.personaStyleCustom == "警部っぽく" })
    }

    func testOjisanAppearanceDisplayNames() {
        XCTAssertEqual(BuddySeed.ojisanDisplayName(for: "ojisan_keibu"), "警部")
        XCTAssertEqual(BuddySeed.ojisanDisplayName(for: "ojisan_timid"), "気弱")
        XCTAssertEqual(BuddySeed.ojisanDisplayName(for: "unknown"), "おじさん")
        XCTAssertEqual(BuddySeed.makeOjisan(variant: "ojisan_baldglasses").appearanceDisplayName, "はげ")
    }

    func testDailyChangeKeyUsesAppDayBoundary() throws {
        let calendar = Calendar(identifier: .gregorian)
        let earlyMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 3, minute: 30)))
        let previousNight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 22, minute: 0)))

        XCTAssertEqual(
            BuddyAppearanceCandidateFactory.dailyChangeKey(for: earlyMorning),
            BuddyAppearanceCandidateFactory.dailyChangeKey(for: previousNight)
        )
    }
}
