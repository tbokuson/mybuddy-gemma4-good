import XCTest
@testable import MyBuddy

final class OnboardingPromptBuilderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguageMode.japanese.rawValue, forKey: AppLanguageMode.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguageMode.storageKey)
        super.tearDown()
    }

    func testMatchedConfirmationPromptIncludesBuddyNameAndTopic() {
        let (system, user) = OnboardingPromptBuilder.matchedConfirmationPrompt(
            buddyName: "モモ",
            section: .persona,
            userInput: "クール"
        )
        XCTAssertTrue(system.contains("モモ"))
        XCTAssertTrue(system.contains("キャラ"))
        XCTAssertTrue(user.contains("クール"))
    }

    func testNullishPromptIncludesBuddyName() {
        let (system, _) = OnboardingPromptBuilder.nullishPrompt(buddyName: "モモ", section: .distance)
        XCTAssertTrue(system.contains("モモ"))
        XCTAssertTrue(system.contains("距離感"))
    }

    func testUnknownClarifyPromptIncludesExamples() {
        let (system, user) = OnboardingPromptBuilder.unknownClarifyPrompt(
            buddyName: "モモ",
            section: .persona,
            userInput: "よくわからない入力"
        )
        // 例が含まれる
        XCTAssertTrue(system.contains("やさしい") || system.contains("クール"))
        XCTAssertTrue(user.contains("よくわからない入力"))
    }

    func testSectionClassificationPromptParsesValidValues() {
        XCTAssertEqual(
            OnboardingPromptBuilder.parseSectionClassification("casual", section: .distance),
            "casual"
        )
        XCTAssertEqual(
            OnboardingPromptBuilder.parseSectionClassification("答えは feelingAware です", section: .diaryStyle),
            "feelingAware"
        )
        XCTAssertNil(OnboardingPromptBuilder.parseSectionClassification("unknown", section: .persona))
        XCTAssertNil(OnboardingPromptBuilder.parseSectionClassification("casual", section: .persona))
    }

    func testCustomTraitsFreeResponsePromptInstructsUnknownBehavior() {
        let (system, user) = OnboardingPromptBuilder.customTraitsFreeResponsePrompt(
            buddyName: "モモ",
            userInput: "語尾に『にゃ』つけて"
        )
        XCTAssertTrue(system.contains("モモ"))
        XCTAssertTrue(system.contains("わからない"))
        XCTAssertTrue(user.contains("にゃ"))
    }

    // MARK: - isUnknownResponse

    func testIsUnknownResponseDetectsUnknownKeywords() {
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("わからない"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("わかんないな〜"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("ごめん、ちょっとわからなかった"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("うーん、それはピンとこないな"))
    }

    func testIsUnknownResponseAcceptsUnderstoodReplies() {
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("にゃ語尾！了解にゃ！"))
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("関西弁ね、やってみる"))
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("楽しそう！"))
    }

    func testIsUnknownResponseIgnoresFarAwayUnknownKeyword() {
        // 先頭 20 文字以内に含まれないケースは理解済みとして扱う
        let response = "その気持ちすごくわかる。あとで時間があったら教えてね、わからないこと" // 20文字以降に「わからない」
        // 20文字以内に「わかる」しかないので、誤判定しない
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse(response))
    }

    // MARK: - customTraitsClassificationPrompt

    func testCustomTraitsClassificationPromptIncludesUserInputAndYN() {
        let (system, user) = OnboardingPromptBuilder.customTraitsClassificationPrompt(userInput: "語尾にゃ")
        XCTAssertTrue(system.contains("Y"))
        XCTAssertTrue(system.contains("N"))
        XCTAssertTrue(user.contains("語尾にゃ"))
        XCTAssertTrue(user.contains("Y") || user.contains("N"))
    }

    // MARK: - parseCustomTraitsClassification

    func testParseCustomTraitsClassificationAcceptsY() {
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Y"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("y"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Yes"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification(" Y "))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("「Y」"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("はい"))
    }

    func testParseCustomTraitsClassificationRejectsN() {
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("N"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("n"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("No"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification(" N "))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("いいえ"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("否"))
    }

    func testParseCustomTraitsClassificationDefaultsToYOnAmbiguous() {
        // 曖昧・解釈不能は通す方に倒す
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification(""))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("？"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("わからない"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("123"))
    }
}
