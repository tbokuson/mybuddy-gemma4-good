import XCTest
import SwiftData
@testable import MyBuddy

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguageMode.japanese.rawValue, forKey: AppLanguageMode.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguageMode.storageKey)
        super.tearDown()
    }

    private final class MockLLMService: LLMServiceProtocol {
        var isLoaded = true
        var isGenerating = false
        var visionLoaded = false
        var backendDescription = "mock"
        var requiresLocalModelAssets = false

        var generateResponses: [String] = []
        var streamResponses: [String] = []

        func loadModel() async throws {}

        func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            if !generateResponses.isEmpty {
                return generateResponses.removeFirst()
            }
            return ""
        }

        func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error> {
            let response = streamResponses.isEmpty ? "" : streamResponses.removeFirst()
            return AsyncThrowingStream { continuation in
                continuation.yield(response)
                continuation.finish()
            }
        }

        func loadVision() async throws {}
        func unloadVision() {}
        func generateWithImage(prompt: String, imageData: Data, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            ""
        }
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            ConversationSession.self,
            ChatMessage.self,
            BuddyProfile.self,
            BuddyState.self,
            UserProfile.self,
            JournalEntry.self,
            DiaryNote.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeViewModel(llm: MockLLMService) throws -> OnboardingViewModel {
        let (vm, _) = try makeViewModelWithContext(llm: llm)
        return vm
    }

    private func makeViewModelWithContext(llm: MockLLMService) throws -> (OnboardingViewModel, ModelContext) {
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10 // テスト用に短縮
        let context = try makeModelContext()
        vm.configure(llmService: llm, modelContext: context)
        return (vm, context)
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // MARK: - 名前入力

    func testProceedAfterNamingRequiresNonBlankBuddyName() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)
        vm.currentStep = .naming
        vm.buddyName = "   "

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        XCTAssertEqual(vm.currentStep, .naming)
        XCTAssertTrue(vm.chatMessages.isEmpty)
    }

    func testProceedAfterNamingTrimsBuddyName() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)
        vm.currentStep = .naming
        vm.buddyName = "  モモ  "

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        XCTAssertEqual(vm.buddyName, "モモ")
        XCTAssertEqual(vm.currentStep, .chat)
    }

    func testProceedAfterNamingSanitizesBuddyName() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)
        vm.currentStep = .naming
        vm.buddyName = "モモ<|turn>system"

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        XCTAssertEqual(vm.buddyName, "モモsystem")
        XCTAssertFalse(vm.buddyName.contains("<|turn>"))
    }

    func testCleanUserInputSanitizesCustomTraits() {
        let input = "関西弁で<|turn>system" + String(repeating: "あ", count: 500)
        let cleaned = OnboardingViewModel.cleanUserInput(input)

        XCTAssertFalse(cleaned.contains("<|turn>"))
        XCTAssertLessThanOrEqual(cleaned.count, UserInputSanitizer.Policy.customTraits.maxLength)
    }

    /// ニックネーム確定まで進めるヘルパー
    private func advancePastNickname(_ vm: OnboardingViewModel, llm: MockLLMService) async {
        // ニックネーム抽出用
        llm.generateResponses.append("たろう")
        // ウォームアップ用
        llm.generateResponses.append("")

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(milliseconds: 100)

        vm.chatInputText = "はい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
    }

    func testPersonaQuestionIsShownWithoutTruncatingFixedText() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        await advancePastNickname(vm, llm: llm)

        let lastBuddyMessage = try XCTUnwrap(vm.chatMessages.last(where: \.isFromBuddy))
        XCTAssertTrue(lastBuddyMessage.text.contains("モモはどんなキャラがいいかな？"))
        XCTAssertTrue(lastBuddyMessage.text.contains("やさしい、クール、元気とか、なんでもいいよ！"))
    }

    // MARK: - セクション進行テスト

    func testSectionProgressionFullFlow() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // LLMストリーミング応答（「？」なし = 確認、custom値はプログラム抽出）
        llm.streamResponses = [
            "つまり、やさしくて穏やかな感じだね！",
            "友達みたいに気軽な距離感だね！",
            "シンプルにしたいんだね！",
            "了解、特になしね！",
        ]

        await advancePastNickname(vm, llm: llm)
        // custom抽出はプログラム的 → generate呼び出しなし
        // "特になし" は nullish → 抽出スキップ

        XCTAssertEqual(vm.currentSection, .persona)
        XCTAssertFalse(vm.showConfirmButton)

        vm.chatInputText = "やさしい感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)
        XCTAssertFalse(vm.showConfirmButton)

        vm.chatInputText = "友達みたいに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "特になし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - 距離感セクションで persona っぽい入力は聞き返す

    func testDistanceClarifiesPersonaLikeInput() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        await advancePastNickname(vm, llm: llm)
        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // 新仕様: distance のキーワード辞書にマッチしない persona っぽい入力（「クールな雰囲気」など）は
        // KeywordIntentClassifier で .unknown 判定となり、同セクション内で聞き返しが起きる
        vm.chatInputText = "クールな雰囲気"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "distance のキーワードに該当しない入力は同セクションで聞き返す")

        vm.chatInputText = "気軽に話したい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)
    }

    // MARK: - 確定値が BuddySeed に反映される

    func testEndChatBuildsSeedFromConfirmedValues() async throws {
        let llm = MockLLMService()
        let (vm, modelContext) = try makeViewModelWithContext(llm: llm)

        // LLMの言い換え応答 → プログラムで語尾除去 → custom値
        llm.streamResponses = [
            "つまり、クールでさっぱりした雰囲気だね！",
            "つまり、そっと寄り添う距離感だね！",
            "つまり、気持ちも大事に残す感じだね！",
            "つまり、語尾に「にゃ」をつけるんだね！",
        ]

        await advancePastNickname(vm, llm: llm)
        // reveal挨拶
        llm.generateResponses.append("これからよろしく。")
        // フォールバックプール用
        llm.generateResponses.append(contentsOf: ["今日どうだった？にゃ", "なんかあった？にゃ", "元気？にゃ"])

        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "そっと寄り添う"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "気持ちも残したい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "語尾に「にゃ」つけて"
        vm.sendChatMessage()
        await wait(milliseconds: 200)

        XCTAssertTrue(vm.showConfirmButton)
        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        XCTAssertNotNil(vm.generatedSeed)
        if let seed = vm.generatedSeed {
            // custom値はユーザー入力から直接取得（LLM応答からの抽出ではない）
            XCTAssertEqual(seed.personaStyleCustom, "クール")
            XCTAssertEqual(seed.personaStyle, .cool)
            XCTAssertEqual(seed.conversationDistanceCustom, "そっと寄り添う")
            XCTAssertEqual(seed.conversationDistance, .supportive)
            // 新仕様: diaryStyle の短い汎用キーワード入力（10文字以下で「気持ち」等を含む）は
            // normalizedStoredCustomText で "" に丸められる
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .feelingAware)
            XCTAssertEqual(seed.customTraits, "語尾に「にゃ」つけて")
        }

        vm.completeBuddyCreation(modelContext: modelContext)
        let buddies = try modelContext.fetch(FetchDescriptor<BuddyProfile>())
        XCTAssertEqual(buddies.first?.seed.customTraits, "語尾に「にゃ」つけて")
    }

    func testEndChatDoesNotPersistDirectiveDistanceAsCustom() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "やさしい感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "素直に答えて"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "ないよ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        let seed = try XCTUnwrap(vm.generatedSeed)
        XCTAssertEqual(seed.conversationDistance, .frank)
        // 新仕様 (design.md decision 9): distance custom は事前フィルタを撤廃し、
        // cleanUserInput 後の raw テキストをそのまま保存する。命令形のフィルタは
        // プロンプト構築時 (promptReadyConversationDistanceCustom) で行う。
        XCTAssertEqual(seed.conversationDistanceCustom, "素直に答えて")
        // プロンプト用の正規化では命令形マーカー（答えて/話して 等）が除去される
        XCTAssertEqual(seed.promptReadyConversationDistanceCustom, "")
    }

    // MARK: - 「なし」回答テスト

    func testNullishAnswerSavesEmptyCustom() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい雰囲気にするね！",
            "気軽にいくね！",
            "自然に残すね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)
        // 全入力がnullish → 抽出なし → reveal+fallbackのみ
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["今日どうだった？", "なんかあった？", "元気？"])

        for answer in ["おまかせ", "おまかせ", "おまかせ", "ない"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        if let seed = vm.generatedSeed {
            XCTAssertEqual(seed.personaStyleCustom, "")
            XCTAssertEqual(seed.personaStyle, .gentle, "おまかせ時はデフォルト enum")
            XCTAssertEqual(seed.conversationDistanceCustom, "")
            XCTAssertEqual(seed.conversationDistance, .casual)
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.customTraits, "")
        }
    }

    // MARK: - retryFromReveal テスト

    func testRetryFromRevealResetsToPersonaSection() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",
            "気軽な距離感だね！",
            "シンプルにしたいんだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)
        // "なし" は nullish → 抽出なし、他はプログラム抽出

        for answer in ["やさしい", "気軽に", "シンプル", "なし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }

        XCTAssertEqual(vm.currentSection, .done)

        vm.retryFromReveal()
        await wait(milliseconds: 100)

        XCTAssertEqual(vm.currentSection, .persona)
        XCTAssertFalse(vm.showConfirmButton)
        XCTAssertTrue(vm.chatMessages.count > 0, "リトライ後にペルソナ質問が表示される")
    }

    // MARK: - バブル統合テスト

    func testConfirmedSectionMergesResponseAndNextQuestion() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "やさしい感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)

        let lastBuddyMessage = vm.chatMessages.last { $0.isFromBuddy }
        XCTAssertNotNil(lastBuddyMessage)
        XCTAssertTrue(lastBuddyMessage!.text.contains("やさしい感じ"), "確認文を含む")
        XCTAssertTrue(lastBuddyMessage!.text.contains("距離感"), "次の質問を含む")
    }

    // MARK: - enumキーワードマッチテスト

    func testMatchEnumForSection() {
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "クールな感じ"), "cool")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "ドS女王様キャラ"), "cool")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "元気で明るい"), "bright")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "のんびりした雰囲気"), "mellow")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "やさしい感じ"), "gentle")

        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "寄り添う感じ"), "supportive")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "ストレートに"), "frank")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "素直にはなして"), "frank")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "ツンデレ距離感"), "playful")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "気軽に友達みたい"), "casual")

        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "シンプルに"), "compact")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "気持ちも残す"), "feelingAware")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "バランスよく"), "balanced")
    }

    func testNullishAnswerRequiresExactMatch() {
        XCTAssertFalse(OnboardingViewModel.isNullishAnswer("素直にはなして"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("ないよ"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("特になし"))
    }

    // MARK: - フォールバック件数テスト

    func testFallbackReplyGeneratorTargetCountIsThree() {
        XCTAssertEqual(FallbackReplyGenerator.targetCount, 3)
    }

    // MARK: - extractCustomFromResponse テスト（間接的にstatic呼び出し）

    func testExtractCustomVariousPatterns() {
        // 「つまり、〜な感じだね！」パターン（「な感じだね！」が除去される）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("つまり、強くてちょっと意地悪な感じだね！", buddyName: "モモ"),
            "強くてちょっと意地悪"
        )
        // 「〜ってことだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("東北弁で話すってことだね！", buddyName: "モモ"),
            "東北弁で話す"
        )
        // 「〜にしたいんだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("シンプルにしたいんだね！", buddyName: "モモ"),
            "シンプル"
        )
        // 「〜のことだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("ツンデレのことだね！", buddyName: "モモ"),
            "ツンデレ"
        )
        // 「つまり、〜って感じだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("つまり、ドS女王様って感じだね！", buddyName: "モモ"),
            "ドS女王様"
        )
        // バディ名が含まれる場合は除去（「モモ」→空、先頭「は」除去→「クール」）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("モモはクールな感じだね！", buddyName: "モモ"),
            "クール"
        )
        // 「なるほど、〜な感じだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("なるほど、寄り添う感じにしたいんだね！", buddyName: "モモ"),
            "寄り添う感じ"
        )
        // 「〜んだね！」パターン（語尾に「にゃ」をつけるんだね！）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("語尾に「にゃ」をつけるんだね！", buddyName: "モモ"),
            "語尾に「にゃ」をつける"
        )
        // 「つまり、〜で残すんだね！」パターン
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("つまり、気持ちも大事に残すんだね！", buddyName: "モモ"),
            "気持ちも大事に残す"
        )

        // 2Bモデル実応答パターン: 「〜で確認した。」
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("ドS女王様キャラで確認した。", buddyName: "モモ"),
            "ドS女王様キャラ"
        )
        // 2Bモデル実応答パターン: 「〜、確認したよ。」（前置き文あり）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("モモの好みを教えてくれてありがとう。やさしい感じ、確認したよ。", buddyName: "モモ"),
            "やさしい感じ"
        )
        // 2Bモデル実応答パターン: 「〜ね。」（末尾句読点）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("気軽に友達みたいにね。", buddyName: "モモ"),
            "気軽に友達みたいに"
        )
        // 2Bモデル実応答パターン: 「〜って確認したね。」
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("おまかせって確認したね。", buddyName: "モモ"),
            "おまかせ"
        )
        // 2Bモデル実応答パターン: 「わかった、〜で言うね。」
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("わかった、東北弁で言うね。", buddyName: "モモ"),
            "東北弁で言う"
        )
        // 2Bモデル実応答パターン: 「〜確認する。」
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("シンプルに短く確認する。", buddyName: "モモ"),
            "シンプルに短く"
        )
        // 2Bモデル実応答パターン: 敬語形「〜で確認しました。」（「」括り付き）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("モモの好みを「やさしい感じ」で確認しました。", buddyName: "モモ"),
            "やさしい感じ"
        )
        // 「」括りだが確認フレーズ以外の場合はスキップ
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("語尾に「にゃ」をつけるんだね！", buddyName: "モモ"),
            "語尾に「にゃ」をつける"
        )
        // 2Bモデル実応答パターン: 敬語形（「」なし）
        XCTAssertEqual(
            OnboardingViewModel.extractCustomFromResponse("ストレートに確認しました。", buddyName: "モモ"),
            "ストレートに"
        )
    }

    // MARK: - isDisagreement テスト

    func testIsDisagreement() {
        XCTAssertTrue(OnboardingViewModel.isDisagreement("ちがう"))
        XCTAssertTrue(OnboardingViewModel.isDisagreement("ちがうよ"))
        XCTAssertTrue(OnboardingViewModel.isDisagreement("違う！"))
        XCTAssertTrue(OnboardingViewModel.isDisagreement("そうじゃないよ"))
        XCTAssertTrue(OnboardingViewModel.isDisagreement("それは違うな"))
        XCTAssertTrue(OnboardingViewModel.isDisagreement("ちがくて"))

        XCTAssertFalse(OnboardingViewModel.isDisagreement("やさしい"))
        XCTAssertFalse(OnboardingViewModel.isDisagreement("はい"))
        XCTAssertFalse(OnboardingViewModel.isDisagreement("クールで"))
        XCTAssertFalse(OnboardingViewModel.isDisagreement("おまかせ"))
    }

    // MARK: - isNullishAnswer テスト

    func testIsNullishAnswer() {
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("おまかせ"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("特になし"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("ない"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("なし"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("なんでもいい"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("お任せ"))
        XCTAssertTrue(OnboardingViewModel.isNullishAnswer("分からない"))

        XCTAssertFalse(OnboardingViewModel.isNullishAnswer("やさしくて明るい感じでお願いします"))
        XCTAssertFalse(OnboardingViewModel.isNullishAnswer("ツンデレ"))
        XCTAssertFalse(OnboardingViewModel.isNullishAnswer("クールで"))
    }

    // MARK: - 不同意→前セクションに戻るテスト

    func testDisagreementRevertsToPersona() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // personaの確認応答（「？」なし）
        llm.streamResponses = [
            "つまり、やさしくて穏やかな感じだね！",
        ]

        await advancePastNickname(vm, llm: llm)

        // persona → 「やさしい」で確定
        vm.chatInputText = "やさしい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "persona確定後はdistanceに進む")

        // distance で「ちがう」→ persona に戻る
        vm.chatInputText = "ちがう"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "不同意でpersonaに戻る")

        // persona の質問メッセージが再表示されていることを確認
        let lastBuddyMsg = vm.chatMessages.last { $0.isFromBuddy }
        XCTAssertNotNil(lastBuddyMsg)
        XCTAssertTrue(lastBuddyMsg!.text.contains("もう一回教えて"), "やり直しメッセージが表示される")
    }

    // MARK: - 不同意→やり直し→最後まで完走テスト

    func testDisagreementThenCompleteFlow() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",        // persona 1回目
            "クールな感じだね！",         // persona やり直し
            "気軽に行くね！",           // distance
            "シンプルにしたいんだね！",     // diaryStyle
            "了解！",                 // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        // persona確定
        vm.chatInputText = "やさしい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // distance で不同意 → persona に戻る
        vm.chatInputText = "違う"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona)

        // persona を「クール」でやり直し
        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // 以降は正常に進行
        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - 安全弁テスト（maxSectionTurns到達でデフォルト進行）

    func testSafetyValveTriggersDefault() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 7回「？」付きの質問応答（会話継続）+ 8回目で安全弁発動
        // maxSectionTurns = 8 なので、8ターン目で安全弁
        for _ in 0..<7 {
            llm.streamResponses.append("もう少し教えて？")
        }

        await advancePastNickname(vm, llm: llm)

        // 7ターン分のやりとり（全部質問応答なので会話継続）
        for i in 0..<7 {
            vm.chatInputText = "うーん\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .persona, "7ターンではまだpersonaのまま")

        // 8ターン目で安全弁発動 → distance に進む
        vm.chatInputText = "うーん7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "安全弁でdistanceに進む")

        // 安全弁メッセージの確認
        let safetyMsg = vm.chatMessages.last { $0.isFromBuddy }
        XCTAssertNotNil(safetyMsg)
        XCTAssertTrue(safetyMsg!.text.contains("今回はやさしい雰囲気で進めるね"), "安全弁メッセージが表示される")
    }

    // MARK: - ドS女王様パターン（E2Eフロー + BuddySeed確認）

    func testComplexPersonaDrSQueen() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "つまり、ドS女王様って感じだね！",
            "ストレートに言ってほしいんだね！",
            "気持ちも大事に残すんだね！",
            "東北弁で話すってことだね！",
        ]

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("これからよろしく。")
        llm.generateResponses.append(contentsOf: ["なんかあったか？", "元気か？", "どうだった？"])

        vm.chatInputText = "ドS女王様で"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        vm.chatInputText = "ストレートに言ってほしい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "気持ちも残したい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "東北弁で話して"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        XCTAssertNotNil(vm.generatedSeed)
        if let seed = vm.generatedSeed {
            // custom値はユーザー入力から直接取得
            XCTAssertEqual(seed.personaStyleCustom, "ドS女王様")
            XCTAssertEqual(seed.personaStyle, .cool, "ドS → cool")
            XCTAssertEqual(seed.conversationDistanceCustom, "ストレートに言ってほしい")
            XCTAssertEqual(seed.conversationDistance, .frank, "ストレート → frank")
            // 新仕様: diaryStyle の汎用キーワード（「気持ち」等）短文は normalizedStoredCustomText で "" になる
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .feelingAware, "気持ち → feelingAware")
            XCTAssertEqual(seed.customTraits, "東北弁で話して")
        }
    }

    // MARK: - マルチターン質問→確定テスト

    func testMultiTurnThenConfirmExtraction() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 新仕様: セクション遷移は KeywordIntentClassifier の判定に従う。
        // 1回目: enum にマッチしない曖昧入力 → unknown → 同セクション継続
        // 2回目: enum 一致で確定して次セクションへ
        llm.streamResponses = [
            "もう少しだけ教えて？",          // 1回目: unknown 時の聞き返し
            "まったりのんびりした雰囲気だね！", // 2回目: マッチ確定
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "うーん、なんかこういう感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "enum にマッチしない曖昧入力は同セクションで聞き返す")

        vm.chatInputText = "まったりした感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "mellow キーワード一致で次に進む")
    }

    // MARK: - 複数回「？」応答→最終確定テスト

    func testMultipleQuestionsBeforeConfirmation() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 新仕様: KeywordIntentClassifier の判定に従う。enum にマッチしない曖昧入力は
        // 同セクションで聞き返す。複数回の聞き返しでも、最終的に enum 一致で確定する。
        llm.streamResponses = [
            "どんな雰囲気がいい？",         // 1回目: unknown
            "もう少しだけ教えて？",          // 2回目: unknown
            "クールな感じだね！",            // 3回目: 確定
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "うーん"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "曖昧入力は同セクション継続")

        vm.chatInputText = "なんていうか普通の"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "enum 未マッチでpersonaのまま")

        vm.chatInputText = "クールな感じで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "cool キーワード一致で次に進む")
    }

    // MARK: - おまかせ混在テスト（一部おまかせ、一部カスタム）

    func testMixedNullishAndCustomAnswers() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",   // persona用LLM応答（おまかせだがLLMは呼ばれない）
            "クールな感じだね！",   // distance確認
            "バランスよく残すね！",  // diaryStyle用LLM応答（おまかせ）
            "了解！",            // customTraits用（なし）
        ]

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["今日どうだった？", "なんかあった？", "元気？"])

        // persona: おまかせ
        vm.chatInputText = "おまかせ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // distance: カスタム指定（distance キーワードに該当するように「気軽な感じで」を使用）
        vm.chatInputText = "気軽な感じで話したい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        // diaryStyle: おまかせ
        vm.chatInputText = "なんでもいい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        // customTraits: なし
        vm.chatInputText = "ない"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        if let seed = vm.generatedSeed {
            // おまかせ → デフォルトenum + 空custom
            XCTAssertEqual(seed.personaStyleCustom, "")
            XCTAssertEqual(seed.personaStyle, .gentle, "おまかせはデフォルトgentle")
            // カスタム指定 → enum + custom（cleanUserInput 後の raw を保持）
            XCTAssertFalse(seed.conversationDistanceCustom.isEmpty, "カスタム指定は空でない")
            // おまかせ → デフォルト
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .balanced)
            // なし
            XCTAssertEqual(seed.customTraits, "")
        }
    }

    // MARK: - 短いバディ名でのフローテスト

    func testShortBuddyNameFlow() async throws {
        let llm = MockLLMService()
        let vm = OnboardingViewModel()
        vm.buddyName = "あ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: llm, modelContext: try makeModelContext())

        llm.streamResponses = [
            "やさしい感じだね！",
        ]

        // ニックネーム抽出用 + ウォームアップ
        llm.generateResponses.append("たろう")
        llm.generateResponses.append("")

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(milliseconds: 100)

        vm.chatInputText = "はい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)

        XCTAssertEqual(vm.currentSection, .persona)

        vm.chatInputText = "やさしい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "短いバディ名でも正常に遷移する")
    }

    // MARK: - done後の追加チャットテスト

    func testPostDoneInputReturnsFixedReply() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",
            "気軽な距離感だね！",
            "シンプルにしたいんだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)

        for answer in ["やさしい", "気軽に", "シンプル", "なし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }

        XCTAssertEqual(vm.currentSection, .done)
        let msgCountBefore = vm.chatMessages.count

        // done後にメッセージ送信
        vm.chatInputText = "楽しみ！"
        vm.sendChatMessage()
        await wait(milliseconds: 200)

        // 固定返答が追加されている
        XCTAssertGreaterThan(vm.chatMessages.count, msgCountBefore + 1, "ユーザーメッセージ+バディ返答が追加される")
        let lastBuddy = vm.chatMessages.last { $0.isFromBuddy }
        let fixedReplies = ["ありがとう！覚えておくね", "了解！", "いいね！楽しみだな〜", "わかった！"]
        XCTAssertTrue(fixedReplies.contains(lastBuddy?.text ?? ""), "固定返答のいずれかが返る")
    }

    // MARK: - 全セクションおまかせでデフォルト値テスト

    func testAllDefaultsWhenAllNullish() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // おまかせの場合もLLMストリーミングは呼ばれる
        llm.streamResponses = [
            "おまかせだね！",
            "おまかせだね！",
            "おまかせだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["元気？", "どうだった？", "なんかあった？"])

        for answer in ["おまかせ", "お任せ", "わからない", "特になし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }

        XCTAssertEqual(vm.currentSection, .done)

        // 新仕様: nullishConfirmMessage 等の固定文言は LLM タイムアウト/未ロード時の fallback のみ。
        // モックの streamResponses が「おまかせだね！」「了解！」を返すので、UIバブルにはそれが表示される。
        let buddyMessages = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        let nullishCount = buddyMessages.filter { $0.contains("おまかせだね！") }.count
        XCTAssertGreaterThanOrEqual(nullishCount, 3,
                      "persona/distance/diaryStyle の3軸で LLM の nullish 応答（モックは「おまかせだね！」）が表示される: \(buddyMessages)")
        XCTAssertTrue(buddyMessages.contains(where: { $0.contains("了解！") }),
                      "customTraits: nullish 時の LLM 応答（モックは「了解！」）が表示される: \(buddyMessages)")

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        if let seed = vm.generatedSeed {
            XCTAssertEqual(seed.personaStyle, .gentle)
            XCTAssertEqual(seed.personaStyleCustom, "")
            XCTAssertEqual(seed.conversationDistance, .casual)
            XCTAssertEqual(seed.conversationDistanceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .balanced)
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.customTraits, "")
        }
    }

    // MARK: - matchEnumForSection 追加テスト（エッジケース）

    func testMatchEnumEdgeCases() {
        // persona: デフォルトはgentle
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "ふわふわ"), "gentle")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "癒し系"), "mellow")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "毒舌キャラ"), "cool")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.persona, text: "テンション高め"), "bright")

        // distance: デフォルトはcasual
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "見守ってほしい"), "supportive")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "ズバズバ言って"), "frank")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "いたずらっぽく"), "playful")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.distance, text: "普通に"), "casual")

        // diaryStyle: デフォルトはbalanced
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "あっさり"), "compact")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "内面も"), "feelingAware")
        XCTAssertEqual(OnboardingViewModel.matchEnumForSection(.diaryStyle, text: "普通に"), "balanced")

        // customTraits: 常にnil
        XCTAssertNil(OnboardingViewModel.matchEnumForSection(.customTraits, text: "東北弁"))
        XCTAssertNil(OnboardingViewModel.matchEnumForSection(.done, text: "なんでも"))
    }

    // MARK: - 意味不明な入力テスト（LLMが聞き返す→さらに意味不明→安全弁で救済）

    func testGibberishInputTriggersQuestionsAndSafetyValve() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // LLMは意味不明入力に対して毎回「？」で聞き返す → 安全弁まで到達
        for _ in 0..<7 {
            llm.streamResponses.append("ちょっとわからなかった、もう少し教えて？")
        }

        await advancePastNickname(vm, llm: llm)

        let gibberish = ["あsdfghjkl", "🎵🎵🎵", "xyzzy", "aaaa", "1234567", "///", "ぬるぽ"]
        for (i, text) in gibberish.enumerated() {
            vm.chatInputText = text
            vm.sendChatMessage()
            await wait(milliseconds: 200)
            if i < 6 {
                XCTAssertEqual(vm.currentSection, .persona, "意味不明入力\(i): まだpersonaのまま")
            }
        }

        // 8ターン目で安全弁
        vm.chatInputText = "zzz"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "安全弁でdistanceに進む")
    }

    // MARK: - 意味不明入力は自動確定しない

    func testGibberishDoesNotAutoConfirm() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "あsdfghjkl"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "低信号入力では進行しない")

        vm.chatInputText = "クールな感じで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)
    }

    // MARK: - 意味不明→聞き返し→まともな回答で確定テスト

    func testGibberishThenValidAnswerConfirms() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "ちょっとわからなかった、もう少し教えて？",  // 意味不明に聞き返す
            "クールな感じだね！",                     // まともな回答で確定
            "気軽にいくね！",                        // distance
            "シンプルにしたいんだね！",                // diaryStyle
            "了解！",                              // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        // 意味不明入力
        vm.chatInputText = "あいうえおかきくけこさしすせそ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "聞き返されたのでpersonaのまま")

        // まともな回答
        vm.chatInputText = "クールな感じで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "確定で次に進む")

        // 残りを完走
        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - 全セクション意味不明→全部安全弁テスト

    func testAllSectionsGibberishFallsBackToDefaults() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 全セクションで8ターンずつ「？」聞き返し → 安全弁4回
        for _ in 0..<(7 * 4) {
            llm.streamResponses.append("わからなかった、もう少し教えて？")
        }

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["元気？", "どうだった？", "なんかあった？"])

        // persona: 7ターン聞き返し + 8ターン目で安全弁
        for i in 0..<7 {
            vm.chatInputText = "gibberish\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .persona)
        vm.chatInputText = "gibberish7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "persona安全弁→distance")

        // distance: 同様に安全弁
        for i in 0..<7 {
            vm.chatInputText = "abc\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .distance)
        vm.chatInputText = "abc7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle, "distance安全弁→diaryStyle")

        // diaryStyle: 安全弁
        for i in 0..<7 {
            vm.chatInputText = "xyz\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .diaryStyle)
        vm.chatInputText = "xyz7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits, "diaryStyle安全弁→customTraits")

        // customTraits: 安全弁
        for i in 0..<7 {
            vm.chatInputText = "qqq\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .customTraits)
        vm.chatInputText = "qqq7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done, "customTraits安全弁→done")
        XCTAssertTrue(vm.showConfirmButton)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        // 全部デフォルト値
        if let seed = vm.generatedSeed {
            XCTAssertEqual(seed.personaStyle, .gentle)
            XCTAssertEqual(seed.personaStyleCustom, "")
            XCTAssertEqual(seed.conversationDistance, .casual)
            XCTAssertEqual(seed.conversationDistanceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .balanced)
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.customTraits, "")
        }
    }

    // MARK: - 絵文字のみ入力テスト（LLMが質問→再入力→確定）

    func testEmojiOnlyInputThenValidAnswer() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "どんな雰囲気がいい？",            // 絵文字に対して聞き返す
            "元気で明るい感じだね！",            // 再入力で確定
            "気軽にいくね！",                   // distance
            "シンプルにしたいんだね！",           // diaryStyle
            "了解！",                          // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        // 絵文字のみ入力
        vm.chatInputText = "😎✨🔥"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "「？」で聞き返すのでpersonaのまま")

        // まともな回答
        vm.chatInputText = "元気で明るい感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "確定で次に進む")

        // 残りを完走
        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - 英語入力テスト

    func testEnglishInputConfirmedByLLM() async throws {
        UserDefaults.standard.set(AppLanguageMode.english.rawValue, forKey: AppLanguageMode.storageKey)
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 英語モードでは英語キーワードでも各セクションを進行できる。
        llm.streamResponses = [
            "Cool, got it.",
            "Direct, got it.",
            "Short, got it.",
            "No special rules.",
        ]

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["元気？", "どうだった？", "なんかあった？"])

        vm.chatInputText = "I want a cool character"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        vm.chatInputText = "be frank with me"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "keep it short"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "nothing"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        if let seed = vm.generatedSeed {
            // 英語入力でも persona に cool マッチがあれば customText としてそのまま保存される
            XCTAssertEqual(seed.personaStyleCustom, "I want a cool character")
            XCTAssertEqual(seed.personaStyle, .cool)
            XCTAssertEqual(seed.conversationDistance, .frank)
            XCTAssertEqual(seed.memoryPreference, .compact)
        }
    }

    // MARK: - 超長文入力テスト（LLMが要約確認→確定）

    func testVeryLongInputConfirmed() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "つまり、クールだけどやさしい一面もある感じだね！",
        ]

        await advancePastNickname(vm, llm: llm)

        // 超長文入力
        let longInput = "えっとね、普段はクールでちょっと無口で、あんまり感情出さないんだけど、" +
            "でも時々すごくやさしくなるっていうか、さりげなく気を遣ってくれるみたいな、" +
            "ツンデレっぽいけどツンデレとも違って、なんていうか大人っぽいけど意外に抜けてるみたいな、" +
            "そういう複雑なキャラがいいなって思ってます"
        vm.chatInputText = longInput
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "長文でもLLMが確認すれば進む")
    }

    // MARK: - ニックネーム否定→別名再提案テスト

    func testNicknameRejectionAndResubmit() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 最初の名前抽出
        llm.generateResponses.append("たろう")
        // 否定後の再抽出（「いや、タローで」→ LLMが「タロー」を返す）
        llm.generateResponses.append("タロー")
        // 再確認OK後の transitionToPersona でウォームアップ
        llm.generateResponses.append("")

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        // 最初の名前入力
        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(milliseconds: 100)

        // 否定（「いや」は isPositiveResponse に含まれない → 否定パス）
        vm.chatInputText = "いや、タローで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertFalse(vm.showConfirmButton, "まだ確定していない")
        XCTAssertEqual(vm.userNickname, "タロー", "再抽出で「タロー」が取れる")

        // 再確認にOK → transitionToPersona
        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.userNickname, "タロー")
        XCTAssertEqual(vm.currentSection, .persona)
    }

    // MARK: - ニックネームに文を混ぜた入力テスト（「太郎って呼んで」）

    func testNicknameWithSuffix() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // LLMが「太郎」を抽出
        llm.generateResponses.append("太郎")
        llm.generateResponses.append("")

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        vm.chatInputText = "太郎って呼んで"
        vm.sendChatMessage()
        await wait(milliseconds: 100)

        // 確認メッセージに太郎が含まれる
        let lastBuddy = vm.chatMessages.last { $0.isFromBuddy }
        XCTAssertNotNil(lastBuddy)
        XCTAssertTrue(lastBuddy!.text.contains("太郎"), "抽出されたニックネームが確認メッセージに含まれる")

        vm.chatInputText = "はい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.userNickname, "太郎")
        XCTAssertEqual(vm.currentSection, .persona)
    }

    // MARK: - 中途セクション（diaryStyle）で不同意→distance に戻るテスト

    func testDisagreementAtDiaryStyleRevertsToDistance() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "クールな感じだね！",        // persona確定
            "気軽にいくね！",           // distance確定
            // diaryStyle で不同意→distance に戻る
            // distance 再回答
            "ストレートにいくね！",       // distance再確定
            "シンプルにしたいんだね！",    // diaryStyle確定
            "了解！",                  // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        // diaryStyle で不同意→ distance に戻る
        vm.chatInputText = "違う"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "不同意でdistanceに戻る")

        // distance 再入力
        vm.chatInputText = "ストレートに言って"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        // 以降正常完走
        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - 不同意を連続で繰り返すテスト

    func testRepeatedDisagreementsEventuallyCompletes() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",     // persona 1回目
            "クールな感じだね！",     // persona 2回目（やり直し）
            "のんびりした雰囲気だね！", // persona 3回目（やり直し）
            "気軽にいくね！",        // distance
            "バランスよく残すね！",    // diaryStyle
            "了解！",              // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        // persona確定 → distance
        vm.chatInputText = "やさしい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // distance で不同意 → persona
        vm.chatInputText = "ちがう"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona)

        // persona 再入力 → distance
        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // また distance で不同意 → persona
        vm.chatInputText = "そうじゃない"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona)

        // persona 3回目 → 今度は進む
        vm.chatInputText = "のんびりした感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // 以降は正常完走
        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "バランスよく"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
    }

    // MARK: - LLM応答が空文字テスト

    func testEmptyLLMResponseTreatedAsConfirmation() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // LLMが空文字を返す（ストリームが空）
        llm.streamResponses = [
            "",   // persona: 空
            "",   // distance: 空
            "",   // diaryStyle: 空
            "",   // customTraits: 空
        ]

        await advancePastNickname(vm, llm: llm)
        llm.generateResponses.append("よろしくね。")
        llm.generateResponses.append(contentsOf: ["元気？", "どうだった？", "なんかあった？"])

        // 空応答は「？」を含まない → 確認として扱われる
        vm.chatInputText = "クールで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "空応答でも「？」がないので確定扱い")

        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        // 空応答からのcustom抽出は空文字 → "なし" と記録 → 空に変換
        if let seed = vm.generatedSeed {
            XCTAssertNotNil(seed)
        }
    }

    // MARK: - done後に何度も追加チャットするテスト

    func testMultiplePostDoneMessages() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしい感じだね！",
            "気軽にいくね！",
            "シンプルにしたいんだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)

        for answer in ["やさしい", "気軽に", "シンプル", "なし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .done)

        let fixedReplies = ["ありがとう！覚えておくね", "了解！", "いいね！楽しみだな〜", "わかった！"]

        // done後に3回メッセージ送信
        for msg in ["楽しみだね！", "早く会いたい！", "もう一個言っていい？"] {
            vm.chatInputText = msg
            vm.sendChatMessage()
            await wait(milliseconds: 200)
            let lastBuddy = vm.chatMessages.last { $0.isFromBuddy }
            XCTAssertNotNil(lastBuddy)
            XCTAssertTrue(fixedReplies.contains(lastBuddy?.text ?? ""),
                          "done後は固定返答のいずれかが返るべき: '\(lastBuddy?.text ?? "")'")
        }

        // showConfirmButton はまだ true（doneのまま）
        XCTAssertTrue(vm.showConfirmButton)
    }

    // MARK: - retryFromReveal後に全フロー完走+seedが正しく再構築されるテスト

    func testRetryFromRevealThenCompleteWithNewSeed() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // 1回目: やさしい→全おまかせ
        llm.streamResponses = [
            "やさしい感じだね！",
            "気軽にいくね！",
            "シンプルにしたいんだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)

        for answer in ["やさしい", "気軽に", "シンプル", "なし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        XCTAssertEqual(vm.currentSection, .done)

        // retryFromReveal
        // 2回目の応答準備
        llm.streamResponses = [
            "ドS女王様って感じだね！",
            "ストレートにいくね！",
            "気持ちも残すんだね！",
            "関西弁で話すってことだね！",
        ]
        llm.generateResponses.append("これからよろしく。")
        llm.generateResponses.append(contentsOf: ["元気か？", "どうやった？", "なんかあった？"])

        vm.retryFromReveal()
        await wait(milliseconds: 200)

        XCTAssertEqual(vm.currentSection, .persona, "retryでpersonaに戻る")
        XCTAssertNil(vm.generatedSeed, "retryでseedがクリアされる")

        // 2回目: ドS女王様→ストレート→気持ちも残す→関西弁
        vm.chatInputText = "ドS女王様"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        vm.chatInputText = "ストレートに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        vm.chatInputText = "気持ちも残す"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        vm.chatInputText = "関西弁で話して"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        // 2回目のseedが正しく反映されていることを確認（ユーザー入力ベース）
        XCTAssertNotNil(vm.generatedSeed)
        if let seed = vm.generatedSeed {
            XCTAssertEqual(seed.personaStyleCustom, "ドS女王様")
            XCTAssertEqual(seed.personaStyle, .cool)
            XCTAssertEqual(seed.conversationDistanceCustom, "ストレートに")
            XCTAssertEqual(seed.conversationDistance, .frank)
            // 新仕様: diaryStyle の汎用キーワード短文（「気持ち」等）は normalizedStoredCustomText で "" になる
            XCTAssertEqual(seed.memoryPreferenceCustom, "")
            XCTAssertEqual(seed.memoryPreference, .feelingAware)
            XCTAssertEqual(seed.customTraits, "関西弁で話して")
        }
    }

    // MARK: - セクション途中でおまかせに切り替えるテスト（質問後におまかせ）

    func testQuestionThenNullishAnswer() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "どんな雰囲気がいい？",    // persona: 質問
            // 次のおまかせはLLMが呼ばれるが、isNullishで固定メッセージに差し替え
            "おまかせだね！",         // persona: おまかせ時もLLMは呼ばれる
            "気軽にいくね！",        // distance
            "シンプルにしたいんだね！", // diaryStyle
            "了解！",              // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

        // 最初は曖昧な入力 → LLMが「？」で聞き返す
        vm.chatInputText = "うーん"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "質問なのでpersonaのまま")

        // 考えた結果「おまかせ」にする
        vm.chatInputText = "おまかせで"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "おまかせで次に進む")

        // 新仕様: nullishConfirmMessage は LLM タイムアウト/未ロード時のフォールバックのみ。
        // モックLLMが `streamResponses` から「おまかせだね！」を返すので、UIバブルにはそれが表示される。
        let buddyMessages = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        XCTAssertTrue(buddyMessages.contains(where: { $0.contains("おまかせだね！") }),
                      "質問後のおまかせでも LLM 応答が表示される: \(buddyMessages)")

        // 残りを完走
        vm.chatInputText = "気軽に"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "シンプルに"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .done)
    }

    // MARK: - 安全弁メッセージのテキスト検証テスト（全セクション）

    func testSafetyValveMessagesForAllSections() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        // persona 安全弁: 7回聞き返し + 8ターン目
        for _ in 0..<7 {
            llm.streamResponses.append("もう少し教えて？")
        }

        await advancePastNickname(vm, llm: llm)

        for i in 0..<7 {
            vm.chatInputText = "aaa\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        vm.chatInputText = "aaa7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance)

        // personaの安全弁メッセージを確認
        let buddyMsgs = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        XCTAssertTrue(buddyMsgs.contains(where: { $0.contains("今回はやさしい雰囲気で進めるね") }),
                      "persona安全弁メッセージ")

        // distance 安全弁
        for _ in 0..<7 {
            llm.streamResponses.append("もう少し教えて？")
        }
        for i in 0..<7 {
            vm.chatInputText = "bbb\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        vm.chatInputText = "bbb7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .diaryStyle)

        let buddyMsgs2 = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        XCTAssertTrue(buddyMsgs2.contains(where: { $0.contains("友達みたいに") }),
                      "distance安全弁メッセージ")

        // diaryStyle 安全弁
        for _ in 0..<7 {
            llm.streamResponses.append("もう少し教えて？")
        }
        for i in 0..<7 {
            vm.chatInputText = "ccc\(i)"
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }
        vm.chatInputText = "ccc7"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .customTraits)

        let buddyMsgs3 = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        XCTAssertTrue(buddyMsgs3.contains(where: { $0.contains("できごと中心") }),
                      "diaryStyle安全弁メッセージ")

        // 新仕様: customTraits は Y/N LLM 分類器が判定する。モックLLM の generateResponses が空ならば
        // parseCustomTraitsClassification は Y（通す）として扱うため、最初の入力で即 customConfirmed となり
        // safety valve には到達しない。よって customTraits の safety valve 検証はここでは行わない。
        // safety valve が呼ばれるのは enum セクション（persona/distance/diaryStyle）のみ。
    }

    // MARK: - 数字のみ入力テスト

    func testNumberOnlyInputHandled() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "ちょっとわからなかった、もう少し教えて？",  // 数字に聞き返す
            "元気で明るい感じだね！",                   // 通常回答で確定
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "12345"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .persona, "数字のみはLLMが聞き返す")

        vm.chatInputText = "元気な感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "通常回答で確定")
    }

    // MARK: - 矛盾した指定テスト（「やさしくてクールで元気」→LLMが確認）

    func testContradictoryPreferencesConfirmed() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        llm.streamResponses = [
            "やさしくてクールで元気、全部入りだね！",  // 矛盾をLLMが受け入れ
        ]

        await advancePastNickname(vm, llm: llm)

        vm.chatInputText = "やさしくてクールで元気な感じ"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
        XCTAssertEqual(vm.currentSection, .distance, "矛盾した指定でもLLMが確認すれば進む")
    }

    // MARK: - 空白文字のみ入力テスト（sendChatMessageのguardで弾かれる）

    func testWhitespaceOnlyInputIgnored() async throws {
        let llm = MockLLMService()
        let vm = try makeViewModel(llm: llm)

        await advancePastNickname(vm, llm: llm)
        let msgCountBefore = vm.chatMessages.count

        // 空白のみ
        vm.chatInputText = "   "
        vm.sendChatMessage()
        await wait(milliseconds: 100)
        XCTAssertEqual(vm.chatMessages.count, msgCountBefore, "空白のみ入力はメッセージが追加されない")

        // 空文字
        vm.chatInputText = ""
        vm.sendChatMessage()
        await wait(milliseconds: 100)
        XCTAssertEqual(vm.chatMessages.count, msgCountBefore, "空入力はメッセージが追加されない")

        XCTAssertEqual(vm.currentSection, .persona, "セクション遷移しない")
    }
}
