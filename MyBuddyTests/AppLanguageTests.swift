import XCTest
@testable import MyBuddy

final class AppLanguageTests: XCTestCase {
    func testJapaneseOnboardingEndChatButtonDoesNotConcatPunctuationAndName() {
        let text = AppText(language: .japanese)

        XCTAssertEqual(text.onboardingEndChatButton(buddyName: "Momo"), "これでOK！Momoの姿を見る")
    }

    func testEnglishOnboardingEndChatButtonKeepsExpectedLabel() {
        let text = AppText(language: .english)

        XCTAssertEqual(text.onboardingEndChatButton(buddyName: "Milo"), "Looks good. Meet Milo")
    }
}
