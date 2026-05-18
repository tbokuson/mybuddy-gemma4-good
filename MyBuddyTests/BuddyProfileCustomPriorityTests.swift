import XCTest
@testable import MyBuddy

final class BuddyProfileCustomPriorityTests: XCTestCase {

    func testBuildSystemPromptPrefersCustomOverEnumDescriptions() {
        let seed = BuddySeed(
            bodyId: "round",
            eyeId: "sparkle",
            earId: "round",
            mouthId: "smile",
            paletteId: "warm",
            accentIds: [],
            personaStyle: .gentle,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "語尾は短め",
            personaStyleCustom: "ツンデレ",
            conversationDistanceCustom: "ちょっと生意気に",
            memoryPreferenceCustom: "出来事も気持ちも残す",
            roomThemeId: "room_default"
        )

        let prompt = BuddyProfile.buildSystemPrompt(displayName: "モモ", seed: seed)

        XCTAssertTrue(prompt.contains("あなたは「モモ」"))
        XCTAssertTrue(prompt.contains("ツンデレ"))
        XCTAssertTrue(prompt.contains("キャラ像:"))
        XCTAssertTrue(prompt.contains("語尾は短め"))
        XCTAssertTrue(prompt.contains("基本の人柄:"))
        XCTAssertTrue(prompt.contains("基本の口調:"))
    }

    func testCustomFirstJournalInstructionPutsRawCustomBeforeEnumInstruction() {
        let instruction = MemoryPreference.feelingAware.customFirstJournalInstruction(custom: "出来事も気持ちも残す")

        XCTAssertTrue(instruction.contains("最優先の希望: 出来事も気持ちも残す"))
        XCTAssertTrue(instruction.contains("補足:"))
        XCTAssertTrue(instruction.contains(MemoryPreference.feelingAware.journalInstruction))
    }

    func testBuildSystemPromptDefaultsToStandardJapaneseWithoutDialectRequest() {
        let prompt = BuddyProfile.buildSystemPrompt(displayName: "モモ", seed: .appDefault)
        XCTAssertTrue(prompt.contains("標準語で話す"))
        XCTAssertTrue(prompt.contains("方言"))
    }

    func testBuildSystemPromptDropsDirectiveDistanceCustomFromPrompt() {
        let seed = BuddySeed(
            bodyId: "round",
            eyeId: "sparkle",
            earId: "round",
            mouthId: "smile",
            paletteId: "warm",
            accentIds: [],
            personaStyle: .gentle,
            conversationDistance: .frank,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "",
            personaStyleCustom: "やさしい感じ",
            conversationDistanceCustom: "素直に答えて",
            memoryPreferenceCustom: "",
            roomThemeId: "room_default"
        )

        let prompt = BuddyProfile.buildSystemPrompt(displayName: "モモ", seed: seed)

        XCTAssertFalse(prompt.contains("素直に答えて"))
        XCTAssertTrue(prompt.contains(ConversationDistance.frank.promptDescription))
    }
}
