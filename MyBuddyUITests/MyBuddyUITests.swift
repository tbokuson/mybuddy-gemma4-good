import XCTest
import Foundation

final class MyBuddyUITests: XCTestCase {
    private static let runFlagKey = "MYBUDDY_RUN_UI_E2E_TESTS"
    private let ollamaModel = ProcessInfo.processInfo.environment["MYBUDDY_OLLAMA_MODEL"] ?? "gemma4:e2b"
    private let ollamaBaseURL = ProcessInfo.processInfo.environment["MYBUDDY_OLLAMA_BASE_URL"] ?? "http://127.0.0.1:11434"
    private let diaryGlobalForbiddenTerms = ["テストバディ", "バディ", "AI", "話してくれた", "聞かせてくれた"]

    private struct DiaryTurn {
        let userMessage: String
        let requiredGroups: [[String]]
        let forbiddenTerms: [String]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment[Self.runFlagKey] == "1" || canRunWithoutE2EFlag else {
            throw XCTSkip("UI E2E テストは明示的に有効化した場合のみ実行します")
        }
    }

    private var canRunWithoutE2EFlag: Bool {
        name.contains("testAppearancePickerCanSwitchFromOjisanToMonster")
            || name.contains("testCaptureOnboardingAuditScreens")
            || name.contains("testOnboardingPersonaQuestionShowsFullText")
            || name.contains("testHomeShowsResumeButtonWhenTodaySessionExists")
    }

    @MainActor
    func testCaptureOnboardingAuditScreens() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        let welcomeTitle = app.staticTexts["onboarding.welcomeTitle"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 10))
        captureScreenshot(named: "01_onboarding_welcome")

        app.buttons["onboarding.welcomeStartButton"].tap()
        let privacyTitle = app.staticTexts["onboarding.privacyTitle"]
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 10))
        captureScreenshot(named: "02_onboarding_privacy")

        app.buttons["onboarding.privacyNextButton"].tap()
        let namingTitle = app.staticTexts["onboarding.namingTitle"]
        XCTAssertTrue(namingTitle.waitForExistence(timeout: 10))
        captureScreenshot(named: "03_onboarding_naming")
    }

    @MainActor
    func testCaptureRevealAuditScreen() throws {
        let app = makeApp(skipOnboarding: false)
        app.launchEnvironment["MYBUDDY_UI_TEST_ONBOARDING_STEP"] = "reveal"
        app.launch()

        let revealTitle = app.staticTexts["onboarding.revealTitle"]
        XCTAssertTrue(revealTitle.waitForExistence(timeout: 10))
        let revealGreeting = app.staticTexts["onboarding.revealGreeting"]
        XCTAssertTrue(revealGreeting.waitForExistence(timeout: 10))
        captureScreenshot(named: "04_onboarding_reveal")
        assertReadableAssistantText(revealTitle.label, context: "audit.revealTitle")
        assertReadableAssistantText(revealGreeting.label, context: "audit.revealGreeting")
    }

    @MainActor
    func testOnboardingPersonaQuestionShowsFullText() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.welcomeStartButton"].waitForExistence(timeout: 10))
        app.buttons["onboarding.welcomeStartButton"].tap()

        XCTAssertTrue(app.buttons["onboarding.privacyNextButton"].waitForExistence(timeout: 10))
        app.buttons["onboarding.privacyNextButton"].tap()

        let buddyNameField = app.textFields["onboarding.buddyNameField"]
        XCTAssertTrue(buddyNameField.waitForExistence(timeout: 10))
        buddyNameField.tap()
        buddyNameField.typeText("モモ")
        app.buttons["onboarding.namingConfirmButton"].tap()

        let onboardingInput = app.textFields["onboarding.chatInputField"]
        XCTAssertTrue(onboardingInput.waitForExistence(timeout: 30))
        onboardingInput.tap()
        onboardingInput.typeText("たろう")

        let sendButton = app.buttons["onboarding.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 10))
        sendButton.tap()

        XCTAssertTrue(waitForBuddyMessage(containing: "って呼んでいい？", in: app, timeout: 30))
        onboardingInput.tap()
        onboardingInput.typeText("はい")
        XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 10))
        sendButton.tap()

        let expectedTail = "やさしい、クール、元気とか、なんでもいいよ！"
        XCTAssertTrue(waitForBuddyMessage(containing: expectedTail, in: app, timeout: 30))
        captureScreenshot(named: "onboarding_persona_question_full_text")
    }

    @MainActor
    func testCaptureMainAppAuditScreens() throws {
        let app = makeApp(skipOnboarding: true, scenario: "uiAudit")
        app.launch()

        let startButton = app.buttons["home.startChatButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        captureScreenshot(named: "05_home")

        let profileButton = app.buttons["home.buddyProfileButton"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 10))
        profileButton.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        captureScreenshot(named: "06_profile")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        startButton.tap()
        let inputField = app.textFields["chat.inputField"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 10))
        captureScreenshot(named: "07_chat")

        let journalButton = app.buttons["chat.viewJournalButton"]
        XCTAssertTrue(journalButton.waitForExistence(timeout: 10))
        journalButton.tap()
        let previewBody = app.staticTexts["chat.journalPreviewBody"]
        XCTAssertTrue(previewBody.waitForExistence(timeout: 10))
        captureScreenshot(named: "08_journal_preview")
        app.buttons["chat.journalPreviewDoneButton"].tap()

        app.buttons["chat.closeButton"].tap()

        app.tabBars.buttons["日記"].tap()
        let journalRow = app.buttons["journal.entryRow"].firstMatch.exists
            ? app.buttons["journal.entryRow"].firstMatch
            : app.otherElements["journal.entryRow"].firstMatch
        XCTAssertTrue(journalRow.waitForExistence(timeout: 10))
        captureScreenshot(named: "09_journal_list")
        journalRow.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        captureScreenshot(named: "10_journal_detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        captureScreenshot(named: "11_settings")
    }

    @MainActor
    func testHomeShowsResumeButtonWhenTodaySessionExists() throws {
        let app = makeApp(skipOnboarding: true, scenario: "uiAudit")
        app.launch()

        let startButton = app.buttons["home.startChatButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilEnabled(startButton, timeout: 20))

        let resumeLabel = NSPredicate(format: "label CONTAINS %@", "会話の続きをはじめる")
        let expectation = XCTNSPredicateExpectation(predicate: resumeLabel, object: startButton)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "今日の会話が保存済みの場合は再開ボタンにする必要があります。実際のラベル: \(startButton.label)"
        )
        captureScreenshot(named: "home_resume_button")
    }

    @MainActor
    func testAppearancePickerCanSwitchFromOjisanToMonster() throws {
        let app = makeApp(skipOnboarding: true, scenario: "ojisanSeeded")
        app.launch()

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))

        let currentKind = app.staticTexts["settings.currentAppearanceKind"]
        XCTAssertTrue(currentKind.waitForExistence(timeout: 10))
        XCTAssertTrue(currentKind.label.contains("おじさん"))

        app.buttons["settings.changeAppearanceButton"].tap()
        let monsterType = app.buttons["settings.appearanceType.monster"]
        let ojisanType = app.buttons["settings.appearanceType.ojisan"]
        XCTAssertTrue(monsterType.waitForExistence(timeout: 10))
        XCTAssertTrue(ojisanType.waitForExistence(timeout: 10))
        captureScreenshot(named: "appearance_picker_ojisan_candidates")

        monsterType.tap()
        let monsterCandidate = app.buttons["settings.appearanceCandidate.monster.1"]
        XCTAssertTrue(monsterCandidate.waitForExistence(timeout: 10))
        captureScreenshot(named: "appearance_picker_monster_candidates")
        monsterCandidate.tap()

        let previewAvatar = app.images["settings.appearancePreviewAvatar"].exists
            ? app.images["settings.appearancePreviewAvatar"]
            : app.otherElements["settings.appearancePreviewAvatar"]
        XCTAssertTrue(previewAvatar.waitForExistence(timeout: 10))
        let confirmButton = app.buttons["settings.confirmAppearanceButton"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))
        XCTAssertTrue(confirmButton.label.contains("テストバディをこの見た目にする"))
        captureScreenshot(named: "appearance_picker_confirm_modal")
        confirmButton.tap()

        let changedKind = app.staticTexts["settings.currentAppearanceKind"]
        XCTAssertTrue(changedKind.waitForExistence(timeout: 10))
        XCTAssertTrue(changedKind.label.contains("モンスター"))
        XCTAssertTrue(app.buttons["settings.changeAppearanceButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.changeAppearanceButton"].isEnabled)
        captureScreenshot(named: "appearance_picker_changed_to_monster")
    }

    @MainActor
    func testChatFlowWithLocalOllamaOnSimulator() throws {
        let app = makeApp(skipOnboarding: true)
        app.launch()

        let startButton = app.buttons["home.startChatButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15))

        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: enabledPredicate, evaluatedWith: startButton)
        waitForExpectations(timeout: 20)
        startButton.tap()

        let inputField = app.textFields["chat.inputField"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 10))
        inputField.tap()
        inputField.typeText("今日はテストの確認をしてるよ")

        let sendButton = app.buttons["chat.sendButton"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        let userMessage = app.staticTexts["chat.userMessageText"].firstMatch
        XCTAssertTrue(userMessage.waitForExistence(timeout: 10))

        let buddyMessage = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").element(boundBy: 1)
        XCTAssertTrue(buddyMessage.waitForExistence(timeout: 40))
        assertReadableAssistantText(buddyMessage.label, context: "chat.firstReply")
    }

    @MainActor
    func testDiaryGenerationFromPostOnboardingScenarioWithLocalOllama() throws {
        let app = makeApp(skipOnboarding: true, scenario: "postOnboardingReady")
        app.launch()

        runDiaryGenerationFlow(in: app)
    }

    @MainActor
    func testDiaryAutoGenerationAndUpdateDefaultBuddyDailyPattern() throws {
        let app = makeApp(skipOnboarding: true, scenario: "defaultSeeded")
        app.launch()

        runDiaryQualityFlow(
            in: app,
            turns: [
                DiaryTurn(
                    userMessage: "今朝は神田のカフェでチーズトーストを食べた。外が晴れていて気分が軽かった。",
                    requiredGroups: [["神田", "カフェ"], ["チーズトースト", "トースト"], ["晴れ", "晴れて"], ["気分が軽", "軽かった"]],
                    forbiddenTerms: ["病院", "検査結果"]
                ),
                DiaryTurn(
                    userMessage: "午後は新しい企画の打ち合わせをした。少し緊張したけど、最後は手応えがあって安心した。",
                    requiredGroups: [["企画", "打ち合わせ"], ["緊張"], ["安心", "手応え"]],
                    forbiddenTerms: ["公園", "散歩"]
                )
            ]
        )
    }

    @MainActor
    func testDiaryAutoGenerationAndUpdateDefaultBuddyStressPattern() throws {
        let app = makeApp(skipOnboarding: true, scenario: "defaultSeeded")
        app.launch()

        runDiaryQualityFlow(
            in: app,
            turns: [
                DiaryTurn(
                    userMessage: "午前中は病院で検査結果を聞いた。待ち時間が長くて不安だった。",
                    requiredGroups: [["病院"], ["検査結果"], ["不安"]],
                    forbiddenTerms: ["カフェ", "トースト"]
                ),
                DiaryTurn(
                    userMessage: "帰りに上野公園を散歩したら風が気持ちよくて、少し落ち着いた。",
                    requiredGroups: [["上野公園", "公園"], ["散歩"], ["風"], ["落ち着", "気持ちよ"]],
                    forbiddenTerms: ["企画", "打ち合わせ"]
                )
            ]
        )
    }

    @MainActor
    func testDiaryAutoGenerationAndUpdateCustomBuddyDailyPattern() throws {
        let app = makeApp(skipOnboarding: true, scenario: "postOnboardingReady")
        app.launch()

        runDiaryQualityFlow(
            in: app,
            turns: [
                DiaryTurn(
                    userMessage: "今朝は神田のカフェでチーズトーストを食べた。外が晴れていて気分が軽かった。",
                    requiredGroups: [["神田", "カフェ"], ["チーズトースト", "トースト"], ["晴れ", "晴れて"], ["気分が軽", "軽かった"]],
                    forbiddenTerms: ["病院", "検査結果"]
                ),
                DiaryTurn(
                    userMessage: "午後は新しい企画の打ち合わせをした。少し緊張したけど、最後は手応えがあって安心した。",
                    requiredGroups: [["企画", "打ち合わせ"], ["緊張"], ["安心", "手応え"]],
                    forbiddenTerms: ["公園", "散歩"]
                )
            ]
        )
    }

    @MainActor
    func testDiaryAutoGenerationAndUpdateCustomBuddyStressPattern() throws {
        let app = makeApp(skipOnboarding: true, scenario: "postOnboardingReady")
        app.launch()

        runDiaryQualityFlow(
            in: app,
            turns: [
                DiaryTurn(
                    userMessage: "午前中は病院で検査結果を聞いた。待ち時間が長くて不安だった。",
                    requiredGroups: [["病院"], ["検査結果"], ["不安"]],
                    forbiddenTerms: ["カフェ", "トースト"]
                ),
                DiaryTurn(
                    userMessage: "帰りに上野公園を散歩したら風が気持ちよくて、少し落ち着いた。",
                    requiredGroups: [["上野公園", "公園"], ["散歩"], ["風"], ["落ち着", "気持ちよ"]],
                    forbiddenTerms: ["企画", "打ち合わせ"]
                )
            ]
        )
    }

    @MainActor
    func testDiaryLongConversation20TurnsPerformanceAndQuality() throws {
        let app = makeApp(skipOnboarding: true, scenario: "postOnboardingReady")
        app.launch()
        runLongConversation20TurnsAndValidate(in: app)
    }

    @MainActor
    func testTopicShiftPatternsConversationAndDiaryQuality() throws {
        let app = makeApp(skipOnboarding: true, scenario: "postOnboardingReady")
        app.launch()
        runTopicShiftPatternFlowAndValidate(in: app)
    }

    @MainActor
    func testFullE2EFromFreshOnboardingToLongConversation20Turns() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        let welcomeTitle = app.staticTexts["onboarding.welcomeTitle"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(welcomeTitle.label, context: "onboarding.welcomeTitle")
        let welcomeSubtitle = app.staticTexts["onboarding.welcomeSubtitle"]
        XCTAssertTrue(welcomeSubtitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(welcomeSubtitle.label, context: "onboarding.welcomeSubtitle")
        let welcomeStartButton = app.buttons["onboarding.welcomeStartButton"]
        XCTAssertTrue(welcomeStartButton.waitForExistence(timeout: 10))
        assertElementVisibleInWindow(welcomeTitle, in: app, context: "onboarding.welcomeTitle")
        assertElementVisibleInWindow(welcomeStartButton, in: app, context: "onboarding.welcomeStartButton")
        assertVerticalOrder(welcomeTitle, below: welcomeStartButton, context: "onboarding.welcome")
        app.buttons["onboarding.welcomeStartButton"].tap()

        let privacyTitle = app.staticTexts["onboarding.privacyTitle"]
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(privacyTitle.label, context: "onboarding.privacyTitle")
        let privacySubtitle = app.staticTexts["onboarding.privacySubtitle"]
        XCTAssertTrue(privacySubtitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(privacySubtitle.label, context: "onboarding.privacySubtitle")
        let privacyButton = app.buttons["onboarding.privacyNextButton"]
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10))
        assertElementVisibleInWindow(privacyTitle, in: app, context: "onboarding.privacyTitle")
        assertElementVisibleInWindow(privacyButton, in: app, context: "onboarding.privacyNextButton")
        assertVerticalOrder(privacyTitle, below: privacyButton, context: "onboarding.privacy")
        app.buttons["onboarding.privacyNextButton"].tap()

        let namingTitle = app.staticTexts["onboarding.namingTitle"]
        XCTAssertTrue(namingTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(namingTitle.label, context: "onboarding.namingTitle")
        let buddyNameField = app.textFields["onboarding.buddyNameField"]
        XCTAssertTrue(buddyNameField.waitForExistence(timeout: 10))
        assertElementVisibleInWindow(namingTitle, in: app, context: "onboarding.namingTitle")
        assertElementVisibleInWindow(buddyNameField, in: app, context: "onboarding.buddyNameField")
        buddyNameField.tap()
        buddyNameField.typeText("テストバディ")
        app.buttons["onboarding.namingConfirmButton"].tap()

        let onboardingInput = app.textFields["onboarding.chatInputField"]
        XCTAssertTrue(onboardingInput.waitForExistence(timeout: 30))
        let onboardingFirstMessage = app.descendants(matching: .any).matching(identifier: "onboarding.buddyMessageText").firstMatch
        XCTAssertTrue(onboardingFirstMessage.waitForExistence(timeout: 10))
        assertReadableAssistantText(onboardingFirstMessage.label, context: "onboarding.firstGreeting")

        let onboardingAnswers = [
            "たろうって呼んで",
            "うん、それで大丈夫",
            "やさしくて安心できる感じがいい",
            "友達みたいに気軽な感じがいい",
            "短く読み返しやすい感じがいい",
            "特にないよ"
        ]
        let fallbackAnswer = "特にないよ"
        let maxOnboardingTurns = 12
        var didConfirmOnboarding = false

        for turnIndex in 0..<maxOnboardingTurns {
            if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 2) {
                didConfirmOnboarding = true
                break
            }

            if !onboardingInput.waitForExistence(timeout: 10) {
                if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 1) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 1) {
                    didConfirmOnboarding = true
                    break
                }
                XCTFail("オンボーディング入力欄が見つかりませんでした")
            }
            onboardingInput.tap()
            onboardingInput.typeText(turnIndex < onboardingAnswers.count ? onboardingAnswers[turnIndex] : fallbackAnswer)

            let sendButton = app.buttons["onboarding.sendButton"]
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 40))
            sendButton.tap()
        }

        if !didConfirmOnboarding && !tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) {
            XCTAssertTrue(app.buttons["onboarding.endChatButton"].waitForExistence(timeout: 20))
            app.buttons["onboarding.endChatButton"].tap()
            didConfirmOnboarding = true
        } else {
            didConfirmOnboarding = true
        }

        XCTAssertTrue(didConfirmOnboarding, "オンボーディング確定ボタンが表示されませんでした")
        XCTAssertFalse(app.progressIndicators["onboarding.stepProgressBar"].exists, "確認後に進捗バーが残っています")

        let revealCompleteButton = app.buttons["onboarding.revealCompleteButton"]
        XCTAssertTrue(revealCompleteButton.waitForExistence(timeout: 90))
        let revealTitle = app.staticTexts["onboarding.revealTitle"]
        XCTAssertTrue(revealTitle.waitForExistence(timeout: 10))
        XCTAssertFalse(revealTitle.label.contains("姿"), "revealの見出しが不自然です: \(revealTitle.label)")
        assertReadableAssistantText(revealTitle.label, context: "onboarding.revealTitle")
        let revealGreeting = app.staticTexts["onboarding.revealGreeting"]
        XCTAssertTrue(revealGreeting.waitForExistence(timeout: 10))
        assertReadableAssistantText(revealGreeting.label, context: "onboarding.revealGreeting")
        assertElementVisibleInWindow(revealTitle, in: app, context: "onboarding.revealTitle")
        assertElementVisibleInWindow(revealGreeting, in: app, context: "onboarding.revealGreeting")
        assertElementVisibleInWindow(revealCompleteButton, in: app, context: "onboarding.revealCompleteButton")
        assertVerticalOrder(revealGreeting, below: revealCompleteButton, context: "onboarding.reveal")
        revealCompleteButton.tap()

        runLongConversation20TurnsAndValidate(in: app)
    }

    /// 通常人格（やさしい系）でオンボーディング→日記作成→日記更新を検証
    @MainActor
    func testE2ENormalPersonaOnboardingToDiary() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        performOnboardingWithScreenshots(
            in: app,
            buddyName: "ゆき",
            answers: [
                "たろうって呼んで",
                "うん、それで大丈夫",
                "やさしくて安心できる感じがいい",
                "友達みたいに気軽な感じがいい",
                "短く読み返しやすい感じがいい",
                "特にないよ"
            ],
            screenshotPrefix: "normal"
        )

        runDiaryCreationAndUpdateFlow(in: app, screenshotPrefix: "normal")
    }

    /// カスタム人格（ドS女王様ツンデレ）でオンボーディング→日記作成→日記更新を検証
    @MainActor
    func testE2ECustomPersonaOnboardingToDiary() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        performOnboardingWithScreenshots(
            in: app,
            buddyName: "女王様",
            answers: [
                "たろうって呼んで",
                "うん、それでいい",
                "ドSな女王様みたいに上から目線で来てほしい",
                "ツンデレでたまに甘えてくる感じがいい",
                "辛口で容赦なくまとめてほしい",
                "毎回オーッホッホッって笑ってほしい"
            ],
            screenshotPrefix: "custom"
        )

        runDiaryCreationAndUpdateFlow(in: app, screenshotPrefix: "custom")
    }

    @MainActor
    private func runLongConversation20TurnsAndValidate(in app: XCUIApplication) {
        openChatScreenIfNeeded(in: app)

        let longTurns = [
            "朝は神田のカフェでコーヒーを飲んで、気持ちが落ち着いた。",
            "通勤電車は少し混んでいて、正直ちょっと疲れた。",
            "午前は企画書の修正をして、集中できて手応えがあった。",
            "昼は同僚と定食屋で唐揚げを食べて、ほっとした。",
            "午後の会議は議論が長くて、少し焦った。",
            "会議後にタスク整理をしたら、頭がすっきりした。",
            "夕方に急な問い合わせが来て、緊張した。",
            "でも落ち着いて対応できて、最後は安心した。",
            "退勤前にメール整理をして、達成感があった。",
            "帰り道は上野公園を少し歩いて、気分転換できた。",
            "夜は家でパスタを作って、ゆっくりできた。",
            "食後に本を少し読んで、気持ちが穏やかになった。",
            "そのあと洗い物を片づけて、生活が整った感じがした。",
            "明日の準備で資料を見直して、少し不安も出てきた。",
            "不安はあるけど、やることが見えて前向きになれた。",
            "外を見たら雨が降っていて、静かな気分になった。",
            "寝る前にストレッチして、体のこわばりが取れた。",
            "スマホ通知を切ったら、気持ちが軽くなった。",
            "明日は朝から打ち合わせがあるので、少し緊張している。",
            "でも今日は全体として、落ち着いて過ごせた一日だった。"
        ]

        let conversationStart = Date()
        var responseLatencies: [TimeInterval] = []
        var diarySnapshots: [String] = []
        let responseForbiddenTerms = ["ハワイ", "飛行機", "犬の散歩", "新幹線", "海外旅行"]
        var conversationTranscript: [(turn: Int, user: String, buddy: String, latency: TimeInterval)] = []

        for (idx, turn) in longTurns.enumerated() {
            let previousBuddyCount = buddyMessageCount(in: app)
            sendChatMessage(turn, in: app)
            guard let payload = waitForNextBuddyMessagePayload(in: app, previousCount: previousBuddyCount) else {
                return XCTFail("バディ返答の取得に失敗: turn=\(idx + 1)")
            }
            responseLatencies.append(payload.latency)
            conversationTranscript.append((turn: idx + 1, user: turn, buddy: payload.text, latency: payload.latency))
            XCTAssertGreaterThanOrEqual(approximateSentenceCount(of: payload.text), 1, "返答が短すぎます: \(payload.text)")
            XCTAssertLessThanOrEqual(approximateSentenceCount(of: payload.text), 8, "返答が長すぎます: \(payload.text)")
            assertReadableAssistantText(payload.text, context: "longChat.turn\(idx + 1)")
            assertText(payload.text, doesNotContain: responseForbiddenTerms)
            print("[LONG-CHAT][TURN \(idx + 1)] user=\(turn)")
            print("[LONG-CHAT][TURN \(idx + 1)] buddy=\(payload.text)")
            print("[LONG-CHAT][TURN \(idx + 1)] latency=\(String(format: "%.2f", payload.latency))s")

            // 初回日記は turnIntervalThreshold (5) ターン後に非同期コンパイルされるため、
            // Turn 5 (idx=4) 時点ではまだ完了していない。Turn 10 以降でチェックする。
            if [9, 14, 19].contains(idx) {
                let snapshot = openDiaryPreviewAndGetSnapshot(in: app)
                XCTAssertFalse(snapshot.body.isEmpty)
                assertEmotionTagsQuality(snapshot.emotionTags, context: "longChat.snapshot.turn\(idx + 1)")
                if let previous = diarySnapshots.last {
                    XCTAssertNotEqual(snapshot.body, previous)
                }
                diarySnapshots.append(snapshot.body)
            }
        }

        let totalSeconds = Date().timeIntervalSince(conversationStart)
        XCTAssertLessThan(totalSeconds, 900, "20往復会話+日記更新に15分以上かかっています: \(totalSeconds)秒")
        XCTAssertEqual(responseLatencies.count, 20)

        let firstFiveAvg = responseLatencies.prefix(5).reduce(0, +) / 5
        let lastFiveAvg = responseLatencies.suffix(5).reduce(0, +) / 5
        let worstLatency = responseLatencies.max() ?? 0
        XCTAssertLessThanOrEqual(worstLatency, 90, "単一ターン応答が遅すぎます: \(worstLatency)秒")
        XCTAssertLessThanOrEqual(lastFiveAvg, firstFiveAvg * 3.0 + 1.0, "後半の応答劣化が大きいです。前半平均=\(firstFiveAvg), 後半平均=\(lastFiveAvg)")

        guard let finalDiary = diarySnapshots.last else {
            return XCTFail("最終日記が取得できていません")
        }
        print("[LONG-CHAT][FINAL-DIARY]\n\(finalDiary)")
        XCTAssertGreaterThan(finalDiary.count, 180, "20往復に対して日記本文が短すぎます")
        let keyGroups = [["神田", "カフェ"], ["会議", "焦"], ["上野公園", "公園"], ["雨", "静か"], ["緊張"], ["安心", "前向き"]]
        let matchedGroups = matchedGroupCount(in: finalDiary, groups: keyGroups)
        XCTAssertGreaterThanOrEqual(matchedGroups, 5, "重要情報の反映が不足: matched=\(matchedGroups)/\(keyGroups.count) diary=\(finalDiary)")
        assertText(finalDiary, doesNotContain: diaryGlobalForbiddenTerms + ["ハワイ", "飛行機", "犬の散歩", "新幹線"])

        print("Long diary metrics total=\(Int(totalSeconds))s first5Avg=\(String(format: "%.2f", firstFiveAvg))s last5Avg=\(String(format: "%.2f", lastFiveAvg))s max=\(String(format: "%.2f", worstLatency))s bodyLen=\(finalDiary.count)")
        for item in conversationTranscript {
            print("[LONG-CHAT][SUMMARY][TURN \(item.turn)] latency=\(String(format: "%.2f", item.latency))s")
            print("[LONG-CHAT][SUMMARY][TURN \(item.turn)] user=\(item.user)")
            print("[LONG-CHAT][SUMMARY][TURN \(item.turn)] buddy=\(item.buddy)")
        }

        app.buttons["chat.closeButton"].tap()
        XCTAssertTrue(app.staticTexts["home.todayJournalCreatedBadge"].waitForExistence(timeout: 20))
    }

    @MainActor
    private func runTopicShiftPatternFlowAndValidate(in app: XCUIApplication) {
        openChatScreenIfNeeded(in: app)

        let initialBuddyMessage = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").firstMatch
        XCTAssertTrue(initialBuddyMessage.waitForExistence(timeout: 20))
        assertReadableAssistantText(initialBuddyMessage.label, context: "topicShift.initialGreeting")

        let topicShiftTurns = [
            "午前は仕様レビューで集中して、かなり頭を使った。",
            "昼過ぎに急ぎの修正が入って、焦ってしまった。",
            "夕方は目の疲れが強くて、少ししんどかった。",
            "帰り道にコンビニで温かいスープを買って、ほっとした。",
            "夜はギターを20分だけ弾いたら、気分が切り替わった。",
            "そのあと昔のライブ映像を見て、懐かしくなった。",
            "家族から電話が来て、最近の近況を話した。",
            "父の体調が安定していると聞いて、安心した。",
            "明日の朝イチで発表があるのを思い出して、少し緊張してる。",
            "でも準備はできてるから、やれる気もしている。"
        ]

        var responseLatencies: [TimeInterval] = []
        var transcript: [(turn: Int, user: String, buddy: String)] = []

        for (idx, turn) in topicShiftTurns.enumerated() {
            let previousBuddyCount = buddyMessageCount(in: app)
            sendChatMessage(turn, in: app)
            guard let payload = waitForNextBuddyMessagePayload(in: app, previousCount: previousBuddyCount) else {
                return XCTFail("話題転換テストで返答取得に失敗: turn=\(idx + 1)")
            }
            responseLatencies.append(payload.latency)
            transcript.append((turn: idx + 1, user: turn, buddy: payload.text))

            XCTAssertGreaterThanOrEqual(approximateSentenceCount(of: payload.text), 1, "返答が短すぎます: \(payload.text)")
            XCTAssertLessThanOrEqual(approximateSentenceCount(of: payload.text), 8, "返答が長すぎます: \(payload.text)")
            assertReadableAssistantText(payload.text, context: "topicShift.turn\(idx + 1)")

            print("[TOPIC-SHIFT][TURN \(idx + 1)] user=\(turn)")
            print("[TOPIC-SHIFT][TURN \(idx + 1)] buddy=\(payload.text)")
            print("[TOPIC-SHIFT][TURN \(idx + 1)] latency=\(String(format: "%.2f", payload.latency))s")
        }

        let worstLatency = responseLatencies.max() ?? 0
        XCTAssertLessThanOrEqual(worstLatency, 90, "単一ターン応答が遅すぎます: \(worstLatency)秒")

        XCTAssertTrue(ensureJournalButtonReady(in: app), "日記プレビューボタンが表示されません")
        let finalSnapshot = openDiaryPreviewAndGetSnapshot(in: app)
        assertEmotionTagsQuality(finalSnapshot.emotionTags, context: "topicShift.finalDiary")
        let finalDiary = finalSnapshot.body
        XCTAssertGreaterThan(finalDiary.count, 160, "日記本文が短すぎます: \(finalDiary.count)")

        let topicGroups = [
            ["仕様レビュー", "レビュー", "修正"],
            ["目の疲れ", "しんど", "疲れ"],
            ["スープ", "ほっと"],
            ["ギター", "ライブ"],
            ["家族", "父", "電話"],
            ["発表", "緊張", "やれる"]
        ]
        let matchedGroups = matchedGroupCount(in: finalDiary, groups: topicGroups)
        XCTAssertGreaterThanOrEqual(
            matchedGroups,
            5,
            "話題転換後の情報保持が不足: matched=\(matchedGroups)/\(topicGroups.count) diary=\(finalDiary)"
        )
        assertText(finalDiary, doesNotContain: diaryGlobalForbiddenTerms)

        print("[TOPIC-SHIFT][FINAL-DIARY]\n\(finalDiary)")
        for item in transcript {
            print("[TOPIC-SHIFT][SUMMARY][TURN \(item.turn)] user=\(item.user)")
            print("[TOPIC-SHIFT][SUMMARY][TURN \(item.turn)] buddy=\(item.buddy)")
        }

        app.buttons["chat.journalPreviewDoneButton"].tap()
        app.buttons["chat.closeButton"].tap()
        XCTAssertTrue(app.staticTexts["home.todayJournalCreatedBadge"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testOnboardingToFirstDiaryCreationWithLocalOllama() throws {
        let app = makeApp(skipOnboarding: false)
        app.launch()

        let welcomeTitle = app.staticTexts["onboarding.welcomeTitle"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(welcomeTitle.label, context: "onboarding.welcomeTitle")
        app.buttons["onboarding.welcomeStartButton"].tap()
        let privacyTitle = app.staticTexts["onboarding.privacyTitle"]
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(privacyTitle.label, context: "onboarding.privacyTitle")
        app.buttons["onboarding.privacyNextButton"].tap()

        let namingTitle = app.staticTexts["onboarding.namingTitle"]
        XCTAssertTrue(namingTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(namingTitle.label, context: "onboarding.namingTitle")
        let buddyNameField = app.textFields["onboarding.buddyNameField"]
        XCTAssertTrue(buddyNameField.waitForExistence(timeout: 10))
        buddyNameField.tap()
        buddyNameField.typeText("テストバディ")
        app.buttons["onboarding.namingConfirmButton"].tap()

        let onboardingInput = app.textFields["onboarding.chatInputField"]
        XCTAssertTrue(onboardingInput.waitForExistence(timeout: 30))

        let onboardingAnswers = [
            "たろうって呼んで",
            "うん、それで大丈夫",
            "やさしくて安心できる感じがいい",
            "友達みたいに気軽な感じがいい",
            "短く読み返しやすい感じがいい",
            "特にないよ"
        ]
        let fallbackAnswer = "特にないよ"
        let maxOnboardingTurns = 12

        var didConfirmOnboarding = false

        for turnIndex in 0..<maxOnboardingTurns {
            if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 2) {
                didConfirmOnboarding = true
                break
            }

            if !onboardingInput.waitForExistence(timeout: 10) {
                if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 1) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 1) {
                    didConfirmOnboarding = true
                    break
                }
                XCTFail("オンボーディング入力欄が見つかりませんでした")
            }
            onboardingInput.tap()
            let answer = turnIndex < onboardingAnswers.count ? onboardingAnswers[turnIndex] : fallbackAnswer
            onboardingInput.typeText(answer)

            let sendButton = app.buttons["onboarding.sendButton"]
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 40))
            sendButton.tap()
        }

        if !didConfirmOnboarding && !tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) {
            XCTAssertTrue(app.buttons["onboarding.endChatButton"].waitForExistence(timeout: 60))
            app.buttons["onboarding.endChatButton"].tap()
        } else {
            didConfirmOnboarding = true
        }

        XCTAssertFalse(app.progressIndicators["onboarding.stepProgressBar"].waitForExistence(timeout: 2))

        let revealCompleteButton = app.buttons["onboarding.revealCompleteButton"]
        XCTAssertTrue(revealCompleteButton.waitForExistence(timeout: 90))
        let revealTitle = app.staticTexts["onboarding.revealTitle"]
        XCTAssertTrue(revealTitle.waitForExistence(timeout: 10))
        XCTAssertFalse(revealTitle.label.contains("姿"), "revealの見出しが不自然です: \(revealTitle.label)")
        let revealGreeting = app.staticTexts["onboarding.revealGreeting"]
        XCTAssertTrue(revealGreeting.waitForExistence(timeout: 10))
        assertReadableAssistantText(revealGreeting.label, context: "onboarding.revealGreeting")
        revealCompleteButton.tap()

        runDiaryGenerationFlow(in: app)
    }

    @MainActor
    private func runDiaryGenerationFlow(in app: XCUIApplication) {
        openChatScreenIfNeeded(in: app)

        let initialBuddyMessage = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").firstMatch
        XCTAssertTrue(initialBuddyMessage.waitForExistence(timeout: 15))
        assertReadableAssistantText(initialBuddyMessage.label, context: "daily.firstGreeting")

        let chatInput = app.textFields["chat.inputField"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 10))
        chatInput.tap()
        chatInput.typeText("今日は初期設定の確認をして、そのあと散歩したよ")

        let chatSendButton = app.buttons["chat.sendButton"]
        XCTAssertTrue(chatSendButton.isEnabled)
        chatSendButton.tap()
        let sendAt = Date()

        let userMessage = app.staticTexts["chat.userMessageText"].firstMatch
        XCTAssertTrue(userMessage.waitForExistence(timeout: 10))

        let buddyMessage = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").element(boundBy: 1)
        XCTAssertTrue(buddyMessage.waitForExistence(timeout: 60))
        assertReadableAssistantText(buddyMessage.label, context: "daily.firstReply")
        let buddyLatency = Date().timeIntervalSince(sendAt)
        print("[E2E][Chat] latency=\(String(format: "%.2f", buddyLatency))s")
        print("Observed buddy response: \(buddyMessage.label)")

        let journalButton = app.buttons["chat.viewJournalButton"]
        XCTAssertTrue(journalButton.waitForExistence(timeout: 60))
        let journalReadyLatency = Date().timeIntervalSince(sendAt)
        print("[E2E][Diary] readyLatency=\(String(format: "%.2f", journalReadyLatency))s")
        journalButton.tap()

        let journalPreviewDoneButton = app.buttons["chat.journalPreviewDoneButton"]
        XCTAssertTrue(journalPreviewDoneButton.waitForExistence(timeout: 10))
        if app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 2) {
            print("Observed journal title: \(app.navigationBars.element(boundBy: 0).identifier)")
        }
        journalPreviewDoneButton.tap()

        let chatCloseButton = app.buttons["chat.closeButton"]
        XCTAssertTrue(chatCloseButton.waitForExistence(timeout: 10))
        chatCloseButton.tap()

        let todayJournalBadge = app.staticTexts["home.todayJournalCreatedBadge"]
        XCTAssertTrue(todayJournalBadge.waitForExistence(timeout: 20))

        app.tabBars.buttons["日記"].tap()
        XCTAssertTrue(app.buttons["journal.entryRow"].firstMatch.waitForExistence(timeout: 10) || app.otherElements["journal.entryRow"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    private func runDiaryQualityFlow(in app: XCUIApplication, turns: [DiaryTurn]) {
        openChatScreenIfNeeded(in: app)

        let journalButton = app.buttons["chat.viewJournalButton"]
        XCTAssertFalse(journalButton.waitForExistence(timeout: 2))

        var accumulatedRequiredGroups: [[String]] = []
        var previousPreviewBody: String?

        for turn in turns {
            let previousBuddyCount = buddyMessageCount(in: app)
            let sendAt = Date()
            sendChatMessage(turn.userMessage, in: app)
            let buddyPayload = waitForNextBuddyMessagePayload(in: app, previousCount: previousBuddyCount)
            XCTAssertNotNil(buddyPayload)
            if let buddyPayload {
                print("[E2E][Chat] latency=\(String(format: "%.2f", buddyPayload.latency))s")
                print("[E2E][Chat] buddy=\(buddyPayload.text)")
                assertReadableAssistantText(buddyPayload.text, context: "diaryQualityFlow")
            }

            XCTAssertTrue(journalButton.waitForExistence(timeout: 60))
            let journalReadyLatency = Date().timeIntervalSince(sendAt)
            print("[E2E][Diary] readyLatency=\(String(format: "%.2f", journalReadyLatency))s")
            let snapshot = openDiaryPreviewAndGetSnapshot(in: app, previousBody: previousPreviewBody)
            let bodyText = snapshot.body
            assertEmotionTagsQuality(snapshot.emotionTags, context: "diaryQualityFlow")

            accumulatedRequiredGroups.append(contentsOf: turn.requiredGroups)
            assertText(bodyText, containsAnyInEach: accumulatedRequiredGroups)
            assertText(bodyText, doesNotContain: diaryGlobalForbiddenTerms + turn.forbiddenTerms)

            previousPreviewBody = bodyText
        }

        app.buttons["chat.closeButton"].tap()

        let todayJournalBadge = app.staticTexts["home.todayJournalCreatedBadge"]
        XCTAssertTrue(todayJournalBadge.waitForExistence(timeout: 20))

        app.tabBars.buttons["日記"].tap()
        XCTAssertTrue(app.buttons["journal.entryRow"].firstMatch.waitForExistence(timeout: 10) || app.otherElements["journal.entryRow"].firstMatch.waitForExistence(timeout: 10))
    }

    // MARK: - オンボーディング→日記フロー共通ヘルパー

    @MainActor
    private func performOnboardingWithScreenshots(
        in app: XCUIApplication,
        buddyName: String,
        answers: [String],
        screenshotPrefix: String
    ) {
        // Welcome
        let welcomeTitle = app.staticTexts["onboarding.welcomeTitle"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 10))
        captureScreenshot(named: "\(screenshotPrefix)_01_welcome")
        app.buttons["onboarding.welcomeStartButton"].tap()

        // Privacy
        let privacyTitle = app.staticTexts["onboarding.privacyTitle"]
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 10))
        captureScreenshot(named: "\(screenshotPrefix)_02_privacy")
        app.buttons["onboarding.privacyNextButton"].tap()

        // Naming
        let namingTitle = app.staticTexts["onboarding.namingTitle"]
        XCTAssertTrue(namingTitle.waitForExistence(timeout: 10))
        let buddyNameField = app.textFields["onboarding.buddyNameField"]
        XCTAssertTrue(buddyNameField.waitForExistence(timeout: 10))
        buddyNameField.tap()
        buddyNameField.typeText(buddyName)
        captureScreenshot(named: "\(screenshotPrefix)_03_naming")
        app.buttons["onboarding.namingConfirmButton"].tap()

        // オンボーディング会話
        let onboardingInput = app.textFields["onboarding.chatInputField"]
        XCTAssertTrue(onboardingInput.waitForExistence(timeout: 30))
        let onboardingFirstMessage = app.descendants(matching: .any).matching(identifier: "onboarding.buddyMessageText").firstMatch
        XCTAssertTrue(onboardingFirstMessage.waitForExistence(timeout: 10))
        assertReadableAssistantText(onboardingFirstMessage.label, context: "\(screenshotPrefix).onboarding.firstGreeting")
        captureScreenshot(named: "\(screenshotPrefix)_04_chat_start")

        let fallbackAnswer = "特にないよ"
        let maxOnboardingTurns = 12
        var didConfirmOnboarding = false

        for turnIndex in 0..<maxOnboardingTurns {
            if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 2) {
                didConfirmOnboarding = true
                break
            }

            if !onboardingInput.waitForExistence(timeout: 10) {
                if tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 1) || tapIfExists(app.buttons["onboarding.endChatButton"], timeout: 1) {
                    didConfirmOnboarding = true
                    break
                }
                XCTFail("オンボーディング入力欄が見つかりませんでした")
            }
            onboardingInput.tap()
            onboardingInput.typeText(turnIndex < answers.count ? answers[turnIndex] : fallbackAnswer)

            let sendButton = app.buttons["onboarding.sendButton"]
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 40))
            sendButton.tap()

            // 会話途中のスクリーンショット
            if turnIndex == 2 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 3.0))
                captureScreenshot(named: "\(screenshotPrefix)_05_chat_mid")
            }
        }

        if !didConfirmOnboarding && !tapIfExists(app.buttons["onboarding.confirmButton"], timeout: 2) {
            XCTAssertTrue(app.buttons["onboarding.endChatButton"].waitForExistence(timeout: 20))
            app.buttons["onboarding.endChatButton"].tap()
        }

        // 見た目タイプ選択画面（モンスターのシルエットをタップ）
        let monsterSilhouette = app.buttons["onboarding.monsterSilhouette"]
        if monsterSilhouette.waitForExistence(timeout: 10) {
            captureScreenshot(named: "\(screenshotPrefix)_05b_choosing_appearance")
            monsterSilhouette.tap()
            let firstCandidate = app.buttons["onboarding.appearanceCandidate.1"]
            XCTAssertTrue(firstCandidate.waitForExistence(timeout: 10))
            captureScreenshot(named: "\(screenshotPrefix)_05c_appearance_candidates")
            firstCandidate.tap()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))
        }

        // お披露目画面
        let revealCompleteButton = app.buttons["onboarding.revealCompleteButton"]
        XCTAssertTrue(revealCompleteButton.waitForExistence(timeout: 90))
        let revealTitle = app.staticTexts["onboarding.revealTitle"]
        XCTAssertTrue(revealTitle.waitForExistence(timeout: 10))
        assertReadableAssistantText(revealTitle.label, context: "\(screenshotPrefix).revealTitle")
        let revealGreeting = app.staticTexts["onboarding.revealGreeting"]
        XCTAssertTrue(revealGreeting.waitForExistence(timeout: 10))
        assertReadableAssistantText(revealGreeting.label, context: "\(screenshotPrefix).revealGreeting")
        captureScreenshot(named: "\(screenshotPrefix)_06_reveal")
        print("[\(screenshotPrefix.uppercased())][REVEAL] title=\(revealTitle.label)")
        print("[\(screenshotPrefix.uppercased())][REVEAL] greeting=\(revealGreeting.label)")
        revealCompleteButton.tap()
    }

    @MainActor
    private func runDiaryCreationAndUpdateFlow(in app: XCUIApplication, screenshotPrefix: String) {
        openChatScreenIfNeeded(in: app)

        let initialBuddyMessage = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").firstMatch
        XCTAssertTrue(initialBuddyMessage.waitForExistence(timeout: 20))
        assertReadableAssistantText(initialBuddyMessage.label, context: "\(screenshotPrefix).chat.initialGreeting")
        captureScreenshot(named: "\(screenshotPrefix)_07_chat_home")

        let chatTurns = [
            "朝は近所のパン屋でクロワッサンを買って食べたよ。焼きたてで美味しかった。",
            "午前中は部屋の掃除をして、気持ちがすっきりした。",
            "昼過ぎに友達と駅前のラーメン屋に行った。味噌ラーメンが最高だった。",
            "午後は本屋で気になってた小説を買った。表紙が綺麗だった。",
            "帰りに公園を通ったら桜が満開で、写真を撮った。",
            "夕方は買ってきた小説を少し読んだ。引き込まれて止まらなかった。",
            "夜ご飯は自分でカレーを作った。玉ねぎをじっくり炒めたら甘くなった。",
            "食後にお風呂でゆっくりして、一日の疲れが取れた感じ。",
            "寝る前にまた小説の続きを読んで、ワクワクして眠れなかった。",
            "でも結局すぐ寝落ちしてた。充実した一日だった。",
            "明日は久しぶりに映画を観に行く予定。楽しみだなあ。",
            "今日一日を振り返ると、穏やかで幸せな休日だったと思う。"
        ]

        var responseLatencies: [TimeInterval] = []
        var diarySnapshots: [String] = []
        var conversationTranscript: [(turn: Int, user: String, buddy: String, latency: TimeInterval)] = []

        for (idx, turn) in chatTurns.enumerated() {
            let previousBuddyCount = buddyMessageCount(in: app)
            sendChatMessage(turn, in: app)
            guard let payload = waitForNextBuddyMessagePayload(in: app, previousCount: previousBuddyCount) else {
                return XCTFail("バディ返答の取得に失敗: turn=\(idx + 1)")
            }
            responseLatencies.append(payload.latency)
            conversationTranscript.append((turn: idx + 1, user: turn, buddy: payload.text, latency: payload.latency))
            XCTAssertGreaterThanOrEqual(approximateSentenceCount(of: payload.text), 1, "返答が短すぎます: \(payload.text)")
            XCTAssertLessThanOrEqual(approximateSentenceCount(of: payload.text), 8, "返答が長すぎます: \(payload.text)")
            assertReadableAssistantText(payload.text, context: "\(screenshotPrefix).turn\(idx + 1)")

            print("[\(screenshotPrefix.uppercased())][TURN \(idx + 1)] user=\(turn)")
            print("[\(screenshotPrefix.uppercased())][TURN \(idx + 1)] buddy=\(payload.text)")
            print("[\(screenshotPrefix.uppercased())][TURN \(idx + 1)] latency=\(String(format: "%.2f", payload.latency))s")

            // Turn 9 (idx=8): 初回日記確認（turnIntervalThreshold=5 到達後に非同期コンパイル）
            if idx == 8 {
                let snapshot = openDiaryPreviewAndGetSnapshot(in: app)
                XCTAssertFalse(snapshot.body.isEmpty, "初回日記が空です")
                assertEmotionTagsQuality(snapshot.emotionTags, context: "\(screenshotPrefix).firstDiary")
                XCTAssertFalse(snapshot.emotionTags.isEmpty, "初回日記の感情タグが空です")
                diarySnapshots.append(snapshot.body)
                captureScreenshot(named: "\(screenshotPrefix)_08_first_diary")
                print("[\(screenshotPrefix.uppercased())][FIRST-DIARY] tags=\(snapshot.emotionTags)")
                print("[\(screenshotPrefix.uppercased())][FIRST-DIARY]\n\(snapshot.body)")
            }

            // Turn 12 (idx=11): 日記更新確認
            if idx == 11 {
                let snapshot = openDiaryPreviewAndGetSnapshot(in: app, previousBody: diarySnapshots.last)
                XCTAssertFalse(snapshot.body.isEmpty, "更新日記が空です")
                assertEmotionTagsQuality(snapshot.emotionTags, context: "\(screenshotPrefix).updatedDiary")
                XCTAssertFalse(snapshot.emotionTags.isEmpty, "更新日記の感情タグが空です")
                if let previous = diarySnapshots.last {
                    XCTAssertNotEqual(snapshot.body, previous, "日記が更新されていません")
                }
                diarySnapshots.append(snapshot.body)
                captureScreenshot(named: "\(screenshotPrefix)_09_updated_diary")
                print("[\(screenshotPrefix.uppercased())][UPDATED-DIARY] tags=\(snapshot.emotionTags)")
                print("[\(screenshotPrefix.uppercased())][UPDATED-DIARY]\n\(snapshot.body)")
            }
        }

        // 最終日記の品質チェック
        let keyGroups = [
            ["パン屋", "クロワッサン"],
            ["掃除", "すっきり"],
            ["ラーメン", "味噌"],
            ["小説", "本屋", "本"],
            ["桜", "公園"],
            ["カレー", "玉ねぎ"],
            ["映画"]
        ]
        guard let finalDiary = diarySnapshots.last else {
            return XCTFail("日記が取得できていません")
        }
        let matchedGroups = matchedGroupCount(in: finalDiary, groups: keyGroups)
        XCTAssertGreaterThanOrEqual(matchedGroups, 4, "重要情報の反映が不足: matched=\(matchedGroups)/\(keyGroups.count) diary=\(finalDiary)")
        assertText(finalDiary, doesNotContain: diaryGlobalForbiddenTerms)

        let worstLatency = responseLatencies.max() ?? 0
        XCTAssertLessThanOrEqual(worstLatency, 90, "単一ターン応答が遅すぎます: \(worstLatency)秒")

        captureScreenshot(named: "\(screenshotPrefix)_10_final_chat")

        // 会話ログ出力
        for item in conversationTranscript {
            print("[\(screenshotPrefix.uppercased())][SUMMARY][TURN \(item.turn)] latency=\(String(format: "%.2f", item.latency))s")
            print("[\(screenshotPrefix.uppercased())][SUMMARY][TURN \(item.turn)] user=\(item.user)")
            print("[\(screenshotPrefix.uppercased())][SUMMARY][TURN \(item.turn)] buddy=\(item.buddy)")
        }

        app.buttons["chat.closeButton"].tap()
        XCTAssertTrue(app.staticTexts["home.todayJournalCreatedBadge"].waitForExistence(timeout: 20))
        captureScreenshot(named: "\(screenshotPrefix)_11_home_badge")
    }

    private func makeApp(skipOnboarding: Bool, scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MYBUDDY_LLM_BACKEND"] = "ollama"
        app.launchEnvironment["MYBUDDY_OLLAMA_MODEL"] = ollamaModel
        app.launchEnvironment["MYBUDDY_OLLAMA_BASE_URL"] = ollamaBaseURL
        app.launchEnvironment["MYBUDDY_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MYBUDDY_UI_TEST_SKIP_ONBOARDING"] = skipOnboarding ? "1" : "0"
        if let scenario {
            app.launchEnvironment["MYBUDDY_UI_TEST_SCENARIO"] = scenario
        }
        return app
    }

    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func openChatScreenIfNeeded(in app: XCUIApplication) {
        let startButton = app.buttons["home.startChatButton"]
        if startButton.waitForExistence(timeout: 30) {
            XCTAssertTrue(waitUntilEnabled(startButton, timeout: 30))
            startButton.tap()
            return
        }

        let chatInput = app.textFields["chat.inputField"]
        if chatInput.waitForExistence(timeout: 3) {
            return
        }

        if app.buttons["onboarding.welcomeStartButton"].exists || app.staticTexts["onboarding.welcomeTitle"].exists {
            XCTFail("ホームではなくオンボーディング画面にいます。UIテスト環境初期化を確認してください。")
            return
        }

        XCTFail("チャット開始導線に到達できませんでした。UI階層:\n\(app.debugDescription)")
    }

    @MainActor
    private func ensureJournalButtonReady(in app: XCUIApplication, initialTimeout: TimeInterval = 20) -> Bool {
        let journalButton = app.buttons["chat.viewJournalButton"]
        if journalButton.waitForExistence(timeout: initialTimeout) {
            return true
        }

        if app.buttons["chat.closeButton"].waitForExistence(timeout: 2) {
            app.buttons["chat.closeButton"].tap()
            _ = app.staticTexts["home.todayJournalCreatedBadge"].waitForExistence(timeout: 90)
            openChatScreenIfNeeded(in: app)
            return journalButton.waitForExistence(timeout: 30)
        }

        return false
    }

    private func sendChatMessage(_ message: String, in app: XCUIApplication) {
        let inputField = app.textFields["chat.inputField"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 10))
        inputField.tap()
        inputField.typeText(message)

        let sendButton = app.buttons["chat.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        if !sendButton.isEnabled {
            let returnKey = app.keyboards.buttons["return"]
            if returnKey.exists {
                returnKey.tap()
            } else {
                inputField.typeText("\n")
            }
        }
        if !waitUntilEnabled(sendButton, timeout: 30) {
            let previousBuddyCount = buddyMessageCount(in: app)
            _ = waitForNextBuddyMessage(in: app, previousCount: previousBuddyCount)
            inputField.tap()
            inputField.typeText(message)
            if !sendButton.isEnabled {
                let returnKey = app.keyboards.buttons["return"]
                if returnKey.exists {
                    returnKey.tap()
                } else {
                    inputField.typeText("\n")
                }
            }
        }
        XCTAssertTrue(waitUntilEnabled(sendButton, timeout: 30))
        if sendButton.isHittable {
            sendButton.tap()
        } else {
            let returnKey = app.keyboards.buttons["return"]
            if returnKey.exists {
                returnKey.tap()
            } else {
                inputField.typeText("\n")
            }
        }

        // sendMessage() が実行されたことの確認:
        // isTyping=true になるため sendButton が disabled になる。
        // LazyVStack のレンダリング遅延でメッセージバブルの出現確認は不安定なため、
        // ボタンの disabled 状態で送信成功を判定する。
        let sendProcessed = waitUntilDisabled(sendButton, timeout: 5)
        if !sendProcessed {
            // 送信が効かなかった場合、再度タップ
            if sendButton.isHittable && sendButton.isEnabled {
                sendButton.tap()
                _ = waitUntilDisabled(sendButton, timeout: 5)
            }
        }
    }

    private func waitUntilDisabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNextBuddyMessage(in app: XCUIApplication, previousCount: Int) -> Bool {
        if let latency = waitForNextBuddyMessageLatency(in: app, previousCount: previousCount) {
            print("[E2E][Chat] latency=\(String(format: "%.2f", latency))s")
            return true
        }
        return false
    }

    private func waitForNextBuddyMessagePayload(in app: XCUIApplication, previousCount: Int) -> (text: String, latency: TimeInterval)? {
        let start = Date()
        let deadline = Date().addingTimeInterval(120)
        let ignoredGreetingPhrases = [
            "これから今日のことを少しずつ一緒に残していこう",
            "話してくれたことをもとに、あとで日記にまとめるね"
        ]
        var candidateText: String?
        var settledText = ""
        var lastTextChangeAt = Date()

        while Date() < deadline {
            let messages = app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText")
            let count = messages.count
            if count > previousCount {
                var latestNonEmpty: String?
                for index in stride(from: count - 1, through: previousCount, by: -1) {
                    let text = messages.element(boundBy: index).label.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    if ignoredGreetingPhrases.contains(where: { text.contains($0) }) {
                        continue
                    }
                    latestNonEmpty = text
                    break
                }

                if let latestNonEmpty {
                    if candidateText == nil {
                        candidateText = latestNonEmpty
                        settledText = latestNonEmpty
                        lastTextChangeAt = Date()
                    } else if latestNonEmpty != settledText {
                        settledText = latestNonEmpty
                        lastTextChangeAt = Date()
                    }

                    if !settledText.isEmpty,
                       Date().timeIntervalSince(lastTextChangeAt) >= 1.5 {
                        return (text: settledText, latency: Date().timeIntervalSince(start))
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return nil
    }

    private func waitForNextBuddyMessageLatency(in app: XCUIApplication, previousCount: Int) -> TimeInterval? {
        waitForNextBuddyMessagePayload(in: app, previousCount: previousCount)?.latency
    }

    private func buddyMessageCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: "chat.buddyMessageText").count
    }

    private func userMessageCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: "chat.userMessageText").count
    }

    private func waitForElementCountIncrease(
        in app: XCUIApplication,
        identifier: String,
        previousCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = app.descendants(matching: .any).matching(identifier: identifier).count
            if count > previousCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func openDiaryPreviewAndGetSnapshot(in app: XCUIApplication, previousBody: String? = nil) -> (body: String, emotionTags: [String]) {
        let journalButton = app.buttons["chat.viewJournalButton"]
        let deadline = Date().addingTimeInterval(previousBody == nil ? 20 : 45)
        var latestBodyText = ""
        var latestEmotionTags: [String] = []

        repeat {
            XCTAssertTrue(journalButton.waitForExistence(timeout: 120))
            journalButton.tap()

            let previewBody = app.staticTexts["chat.journalPreviewBody"]
            XCTAssertTrue(previewBody.waitForExistence(timeout: 10))
            latestBodyText = previewBody.label.trimmingCharacters(in: .whitespacesAndNewlines)
            latestEmotionTags = readEmotionTagsFromPreview(in: app)

            let doneButton = app.buttons["chat.journalPreviewDoneButton"]
            XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

            if let previousBody, latestBodyText == previousBody {
                doneButton.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            } else {
                doneButton.tap()
                return (body: latestBodyText, emotionTags: latestEmotionTags)
            }
        } while Date() < deadline

        XCTAssertNotEqual(latestBodyText, previousBody, "日記プレビューが更新されませんでした")
        return (body: latestBodyText, emotionTags: latestEmotionTags)
    }

    private func readEmotionTagsFromPreview(in app: XCUIApplication) -> [String] {
        // .accessibilityElement(children: .combine) を付けた FlowLayout は
        // otherElements ではなく staticTexts として検出される場合がある。
        // descendants で型を問わず検索する。
        let tagElement = app.descendants(matching: .any).matching(identifier: "chat.journalPreviewEmotionTags").firstMatch
        guard tagElement.waitForExistence(timeout: 5) else {
            // フォールバック: "#" で始まる StaticText から直接タグを読む
            let hashTexts = app.staticTexts.allElementsBoundByAccessibilityElement
                .filter { $0.label.hasPrefix("#") }
                .map { $0.label }
            if let combined = hashTexts.first, combined.contains(",") {
                return parseEmotionTagString(combined)
            }
            return hashTexts.flatMap { parseEmotionTagString($0) }
        }

        let raw = tagElement.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        return parseEmotionTagString(raw)
    }

    private func parseEmotionTagString(_ raw: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",、"))
        return raw
            .components(separatedBy: separators)
            .map {
                $0.replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "。.!?！？「」()（）[]"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func assertEmotionTagsQuality(
        _ tags: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(tags.count, 4, "感情タグが多すぎます [\(context)]: \(tags)", file: file, line: line)
        let forbidden = ["不明", "なし", "無し", "none", "n/a", "na", "-", "ー", "—"]
        for tag in tags {
            XCTAssertFalse(forbidden.contains(tag.lowercased()), "禁止タグが含まれています [\(context)]: \(tags)", file: file, line: line)
            XCTAssertFalse(tag.contains("不明"), "禁止タグが含まれています [\(context)]: \(tags)", file: file, line: line)
        }
    }

    private func assertText(_ text: String, containsAnyInEach groups: [[String]], file: StaticString = #filePath, line: UInt = #line) {
        for group in groups {
            XCTAssertTrue(group.contains { text.localizedCaseInsensitiveContains($0) }, "Expected one of \(group) in diary text: \(text)", file: file, line: line)
        }
    }

    private func matchedGroupCount(in text: String, groups: [[String]]) -> Int {
        groups.reduce(0) { partial, group in
            partial + (group.contains { text.localizedCaseInsensitiveContains($0) } ? 1 : 0)
        }
    }

    private func assertText(_ text: String, doesNotContain terms: [String], file: StaticString = #filePath, line: UInt = #line) {
        for term in terms {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(term), "Unexpected term '\(term)' in diary text: \(text)", file: file, line: line)
        }
    }

    private func approximateSentenceCount(of text: String) -> Int {
        text.components(separatedBy: CharacterSet(charactersIn: "。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func assertReadableAssistantText(
        _ text: String,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmed.isEmpty, "空の返答です: \(context)", file: file, line: line)
        XCTAssertFalse(trimmed.contains("�"), "文字化けの疑いがある返答です [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.contains("<|"), "制御トークンが混入しています [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.hasSuffix("」"), "末尾に不自然なカギ括弧があります [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.hasSuffix("』"), "末尾に不自然なカギ括弧があります [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.hasPrefix("「"), "先頭に不自然なカギ括弧があります [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.hasPrefix("『"), "先頭に不自然なカギ括弧があります [\(context)]: \(trimmed)", file: file, line: line)
        XCTAssertFalse(trimmed.contains("姿が決まった"), "プロダクト文言が不自然です [\(context)]: \(trimmed)", file: file, line: line)
    }

    private func assertElementVisibleInWindow(
        _ element: XCUIElement,
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "windowが取得できません [\(context)]", file: file, line: line)
        XCTAssertTrue(element.exists, "要素が存在しません [\(context)]", file: file, line: line)
        XCTAssertTrue(element.isHittable, "要素がタップ可能範囲にありません [\(context)]", file: file, line: line)
        XCTAssertGreaterThan(element.frame.width, 0, "幅が0です [\(context)]", file: file, line: line)
        XCTAssertGreaterThan(element.frame.height, 0, "高さが0です [\(context)]", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, window.frame.minY, "要素が画面上に食い込んでいます [\(context)]", file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, window.frame.maxY, "要素が画面下にはみ出しています [\(context)]", file: file, line: line)
    }

    private func assertVerticalOrder(
        _ upper: XCUIElement,
        below lower: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThan(upper.frame.minY, lower.frame.minY, "縦方向の並び順が不自然です [\(context)]", file: file, line: line)
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForBuddyMessage(containing expectedText: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let messages = app.descendants(matching: .any)
                .matching(identifier: "onboarding.buddyMessageText")
                .allElementsBoundByIndex
            if messages.contains(where: { $0.label.contains(expectedText) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func captureScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
