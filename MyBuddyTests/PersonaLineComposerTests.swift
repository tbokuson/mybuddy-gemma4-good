import XCTest
@testable import MyBuddy

final class PersonaLineComposerTests: XCTestCase {
    func testDominantKansaiLinesReflectCustomPersona() {
        let seed = BuddySeed(
            bodyId: "round",
            eyeId: "sparkle",
            earId: "round",
            mouthId: "smile",
            paletteId: "warm",
            accentIds: [],
            personaStyle: .cool,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "関西弁",
            personaStyleCustom: "ドS女王様キャラ",
            conversationDistanceCustom: "なんでも話そう",
            memoryPreferenceCustom: "シンプル",
            roomThemeId: "room_default"
        )

        let composer = PersonaLineComposer(displayName: "バーディ", seed: seed)

        XCTAssertTrue(composer.revealGreeting().contains("ついてき"))
        XCTAssertTrue(composer.firstDayGreeting(nickname: "山田").contains("山田、"))
        XCTAssertTrue(composer.firstDayGreeting(nickname: "山田").contains("何があったん"))
        XCTAssertTrue(composer.heroSubtitleFresh().contains("話してみ"))
        XCTAssertTrue(composer.resumeGreeting(nickname: "山田").contains("戻ったんやな"))
    }

    func testFallbackRepliesAlwaysProvidesThreeLines() {
        let composer = PersonaLineComposer(displayName: "モモ", seed: .appDefault)
        XCTAssertEqual(composer.fallbackReplies().count, 3)
        XCTAssertTrue(composer.fallbackReplies().allSatisfy { !$0.isEmpty })
    }

    func testHomeResumeSubtitleFallsBackToPersonaLineWhenSavedTextIsEmpty() {
        let seed = BuddySeed(
            bodyId: "round",
            eyeId: "sparkle",
            earId: "round",
            mouthId: "smile",
            paletteId: "warm",
            accentIds: [],
            personaStyle: .cool,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "関西弁",
            personaStyleCustom: "ドS女王様キャラ",
            conversationDistanceCustom: "なんでも話そう",
            memoryPreferenceCustom: "シンプル",
            roomThemeId: "room_default"
        )
        let buddy = BuddyProfile(displayName: "バーディ", seed: seed)
        buddy.heroSubtitleResume = "   "

        let subtitle = HomeHeroTextProvider.subtitle(for: buddy, hasTodaySession: true)

        XCTAssertEqual(
            subtitle,
            PersonaLineComposer(displayName: "バーディ", seed: seed).heroSubtitleResume()
        )
        XCTAssertTrue(subtitle.contains("話してみ"))
        XCTAssertNotEqual(subtitle, "途中からでも大丈夫。今日の会話の続きを始められます。")
    }

    func testHomeResumeSubtitlePrefersSavedPersonaText() {
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)
        buddy.heroSubtitleResume = "  保存済みの再開コメントです。  "

        XCTAssertEqual(
            HomeHeroTextProvider.subtitle(for: buddy, hasTodaySession: true),
            "保存済みの再開コメントです。"
        )
    }
}
