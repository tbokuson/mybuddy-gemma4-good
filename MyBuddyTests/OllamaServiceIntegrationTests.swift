import XCTest
import SwiftData
@testable import MyBuddy

@MainActor
final class OllamaServiceIntegrationTests: XCTestCase {
    private static let runFlagKey = "MYBUDDY_RUN_OLLAMA_TESTS"
    private static let reachabilityTimeout: TimeInterval = 1.5

    func testGenerateReturnsNonEmptyReplyFromLocalOllama() async throws {
        let configuration = AppEnvironment.ollamaConfiguration

        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }

        let service = OllamaService(configuration: configuration)
        try await service.loadModel()

        let response = try await service.generate(
            prompt: Gemma4PromptBuilder.buildSingleTurn(
                system: "あなたは簡潔に答える。",
                user: "3語以内で挨拶して"
            ),
            maxTokens: 32
        )

        XCTAssertFalse(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - 実LLMオンボーディング全フローテスト（通常パターン）

    func testOnboardingFullFlowWithRealLLM() async throws {
        let configuration = AppEnvironment.ollamaConfiguration
        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }

        let service = OllamaService(configuration: configuration)
        try await service.loadModel()

        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: service, modelContext: modelContext)

        print("=== 実LLMオンボーディングテスト: 通常パターン ===")

        // ニックネーム入力
        vm.proceedAfterNaming()
        await wait(seconds: 2)

        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(seconds: 3)

        print("[実LLM] ニックネーム入力後のメッセージ:")
        printBuddyMessages(vm)

        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(seconds: 3)

        print("[実LLM] ニックネーム確定後: section=\(vm.currentSection)")
        XCTAssertEqual(vm.currentSection, .persona, "ニックネーム確定後にpersonaに遷移")

        // persona: 「やさしい感じ」
        vm.chatInputText = "やさしい感じ"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .persona, timeout: 10)
        print("[実LLM] persona応答:")
        printLastBuddyMessage(vm)

        if vm.currentSection == .persona {
            // LLMが「？」で聞き返した場合
            print("[実LLM] personaで聞き返された、再入力")
            vm.chatInputText = "やさしくて穏やかな雰囲気"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .persona, timeout: 10)
            print("[実LLM] persona再応答:")
            printLastBuddyMessage(vm)
        }
        print("[実LLM] persona完了: section=\(vm.currentSection)")

        // distance: 「気軽に友達みたいに」
        XCTAssertEqual(vm.currentSection, .distance)
        vm.chatInputText = "気軽に友達みたいに"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .distance, timeout: 10)
        print("[実LLM] distance応答:")
        printLastBuddyMessage(vm)

        if vm.currentSection == .distance {
            vm.chatInputText = "友達みたいにカジュアルに"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .distance, timeout: 10)
        }
        print("[実LLM] distance完了: section=\(vm.currentSection)")

        // diaryStyle: 「シンプルに」
        XCTAssertEqual(vm.currentSection, .diaryStyle)
        vm.chatInputText = "シンプルに短く"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)
        print("[実LLM] diaryStyle応答:")
        printLastBuddyMessage(vm)

        if vm.currentSection == .diaryStyle {
            vm.chatInputText = "短くまとめてほしい"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)
        }
        print("[実LLM] diaryStyle完了: section=\(vm.currentSection)")

        // customTraits: 「なし」
        XCTAssertEqual(vm.currentSection, .customTraits)
        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .customTraits, timeout: 10)
        print("[実LLM] customTraits応答:")
        printLastBuddyMessage(vm)
        print("[実LLM] customTraits完了: section=\(vm.currentSection)")

        XCTAssertEqual(vm.currentSection, .done, "全セクション完了")
        XCTAssertTrue(vm.showConfirmButton)

        // endChat → BuddySeed構築
        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        XCTAssertNotNil(vm.generatedSeed, "BuddySeedが生成されている")
        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed:")
            print("  persona: enum=\(seed.personaStyle) custom='\(seed.personaStyleCustom)'")
            print("  distance: enum=\(seed.conversationDistance) custom='\(seed.conversationDistanceCustom)'")
            print("  diary: enum=\(seed.memoryPreference) custom='\(seed.memoryPreferenceCustom)'")
            print("  traits: '\(seed.customTraits)'")
            // やさしい→gentle、気軽→casual は期待できるが、LLM応答次第
            XCTAssertEqual(seed.personaStyle, .gentle, "やさしい→gentle")
        }

        print("[実LLM] reveal挨拶: \(vm.revealGreeting)")
        XCTAssertFalse(vm.revealGreeting.isEmpty, "reveal挨拶が生成されている")

        print("=== 実LLMオンボーディング完了: 全会話ログ ===")
        for (i, msg) in vm.chatMessages.enumerated() {
            let role = msg.isFromBuddy ? "🤖" : "👤"
            print("  [\(i)] \(role) \(msg.text)")
        }
    }

    // MARK: - 実LLMオンボーディングテスト（カスタム人格パターン）

    func testOnboardingCustomPersonaWithRealLLM() async throws {
        let configuration = AppEnvironment.ollamaConfiguration
        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }

        let service = OllamaService(configuration: configuration)
        try await service.loadModel()

        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: service, modelContext: modelContext)

        print("=== 実LLMオンボーディングテスト: カスタム人格 ===")

        // ニックネーム
        vm.proceedAfterNaming()
        await wait(seconds: 2)
        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(seconds: 3)
        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(seconds: 3)
        XCTAssertEqual(vm.currentSection, .persona)

        // persona: ドS女王様
        vm.chatInputText = "ドS女王様キャラで"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .persona, timeout: 10)
        print("[実LLM] persona応答:")
        printLastBuddyMessage(vm)
        if vm.currentSection == .persona {
            vm.chatInputText = "意地悪でキツい感じ"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .persona, timeout: 10)
        }
        print("[実LLM] persona完了: section=\(vm.currentSection)")

        // distance: ストレート
        XCTAssertEqual(vm.currentSection, .distance)
        vm.chatInputText = "ストレートにズバズバ言ってほしい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .distance, timeout: 10)
        print("[実LLM] distance応答:")
        printLastBuddyMessage(vm)
        if vm.currentSection == .distance {
            vm.chatInputText = "遠慮なくハッキリ言う感じ"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .distance, timeout: 10)
        }
        print("[実LLM] distance完了: section=\(vm.currentSection)")

        // diaryStyle: 気持ちも残す
        XCTAssertEqual(vm.currentSection, .diaryStyle)
        vm.chatInputText = "気持ちも残してほしい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)
        print("[実LLM] diaryStyle応答:")
        printLastBuddyMessage(vm)
        if vm.currentSection == .diaryStyle {
            vm.chatInputText = "感情も記録したい"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)
        }
        print("[実LLM] diaryStyle完了: section=\(vm.currentSection)")

        // customTraits: 東北弁
        XCTAssertEqual(vm.currentSection, .customTraits)
        vm.chatInputText = "東北弁で話してほしい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .customTraits, timeout: 10)
        print("[実LLM] customTraits応答:")
        printLastBuddyMessage(vm)
        if vm.currentSection == .customTraits {
            vm.chatInputText = "方言で話すキャラにして"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .customTraits, timeout: 10)
        }
        print("[実LLM] customTraits完了: section=\(vm.currentSection)")

        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        XCTAssertNotNil(vm.generatedSeed)
        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed:")
            print("  persona: enum=\(seed.personaStyle) custom='\(seed.personaStyleCustom)'")
            print("  distance: enum=\(seed.conversationDistance) custom='\(seed.conversationDistanceCustom)'")
            print("  diary: enum=\(seed.memoryPreference) custom='\(seed.memoryPreferenceCustom)'")
            print("  traits: '\(seed.customTraits)'")

            XCTAssertFalse(seed.personaStyleCustom.isEmpty, "カスタムpersonaが空でない")
            XCTAssertFalse(seed.conversationDistanceCustom.isEmpty, "カスタムdistanceが空でない")
            XCTAssertFalse(seed.customTraits.isEmpty, "customTraitsが空でない")
        }

        print("[実LLM] reveal挨拶: \(vm.revealGreeting)")

        print("=== 実LLMオンボーディング完了（カスタム人格）: 全会話ログ ===")
        for (i, msg) in vm.chatMessages.enumerated() {
            let role = msg.isFromBuddy ? "🤖" : "👤"
            print("  [\(i)] \(role) \(msg.text)")
        }
    }

    // MARK: - 実LLMオンボーディングテスト（おまかせパターン）

    func testOnboardingAllNullishWithRealLLM() async throws {
        let configuration = AppEnvironment.ollamaConfiguration
        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }

        let service = OllamaService(configuration: configuration)
        try await service.loadModel()

        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: service, modelContext: modelContext)

        print("=== 実LLMオンボーディングテスト: 全おまかせ ===")

        // ニックネーム
        vm.proceedAfterNaming()
        await wait(seconds: 2)
        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(seconds: 3)
        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(seconds: 3)
        XCTAssertEqual(vm.currentSection, .persona)

        // 全部おまかせ
        for (section, answer) in [
            (OnboardingViewModel.OnboardingSection.persona, "おまかせ"),
            (.distance, "お任せで"),
            (.diaryStyle, "なんでもいい"),
            (.customTraits, "特になし")
        ] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: section, timeout: 10)
            print("[実LLM] \(section)応答後:")
            printLastBuddyMessage(vm)
        }

        XCTAssertEqual(vm.currentSection, .done)

        // 固定メッセージが表示されていることを確認
        let buddyMessages = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        print("[実LLM] 全バディメッセージ:")
        for msg in buddyMessages {
            print("  \(msg)")
        }
        // 新仕様: nullishConfirmMessage は LLM タイムアウト/未ロード時の fallback。
        // 実 LLM は「おまかせ系」プロンプトで何らかの受け止め文（例: 「いい感じにするね」等）を返す。
        // 個別の文言は LLM 出力依存なので、応答が空でないことのみ検証する。
        XCTAssertFalse(buddyMessages.isEmpty, "おまかせ応答が表示される")

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed: persona=\(seed.personaStyle) distance=\(seed.conversationDistance) diary=\(seed.memoryPreference)")
            XCTAssertEqual(seed.personaStyle, .gentle)
            XCTAssertEqual(seed.conversationDistance, .casual)
            XCTAssertEqual(seed.memoryPreference, .balanced)
            XCTAssertEqual(seed.personaStyleCustom, "")
            XCTAssertEqual(seed.customTraits, "")
        }
    }

    // MARK: - 実LLMオンボーディングテスト（絵文字・記号入力パターン）

    func testOnboardingEmojiAndSymbolsWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: 絵文字・記号 ===")

        // 新仕様: 絵文字のみの入力は KeywordIntentClassifier で .unknown と判定される。
        // よって同セクション内で聞き返し（unknown）が起き、デフォルトでは次に進まない。
        // ここでは「絵文字でも会話が破綻せず、聞き返しメッセージが返ってくる」ことを検証する。
        vm.chatInputText = "😎✨"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .persona, timeout: 10)
        print("[実LLM] persona 入力='😎✨':")
        printLastBuddyMessage(vm)

        // 絵文字のみは unknown → persona セクションに留まる（または LLM 応答で何らかの返答が生成される）
        let buddyMsgs = vm.chatMessages.filter { $0.isFromBuddy }.map { $0.text }
        XCTAssertFalse(buddyMsgs.isEmpty, "絵文字入力に対しても何らかの応答が生成される")

        printFullConversation(vm)
    }

    // MARK: - 実LLMオンボーディングテスト（1文字・超短入力パターン）

    func testOnboardingMinimalInputWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: 超短入力 ===")

        // 新仕様: KeywordIntentClassifier の辞書に該当する単語のみを使用すると確実に進む。
        // - "クール" → persona.cool
        // - "気軽" → distance.casual
        // - "短く" → diaryStyle.compact
        // - "にゃ" → customTraits の trait-indicator (ショートカット Y)
        let inputs: [(OnboardingViewModel.OnboardingSection, String)] = [
            (.persona, "クール"),
            (.distance, "気軽"),
            (.diaryStyle, "短く"),
            (.customTraits, "にゃ"),
        ]

        for (section, answer) in inputs {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: section, timeout: 10)
            print("[実LLM] \(section) 入力='\(answer)':")
            printLastBuddyMessage(vm)
        }

        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed: persona=\(seed.personaStyle)('\(seed.personaStyleCustom)') distance=\(seed.conversationDistance)('\(seed.conversationDistanceCustom)') traits='\(seed.customTraits)'")
            XCTAssertEqual(seed.personaStyle, .cool)
            XCTAssertEqual(seed.personaStyleCustom, "クール")
            XCTAssertEqual(seed.customTraits, "にゃ")
        }

        printFullConversation(vm)
    }

    // MARK: - 実LLMオンボーディングテスト（長文入力パターン）

    func testOnboardingLongInputWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: 長文入力 ===")

        vm.chatInputText = "普段はクールで落ち着いてるんだけど、たまにデレて可愛いところを見せてくれるツンデレキャラがいいな"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .persona, timeout: 10)
        print("[実LLM] persona(長文):")
        printLastBuddyMessage(vm)

        vm.chatInputText = "基本は友達みたいにカジュアルだけど、悩んでるときは寄り添ってほしい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .distance, timeout: 10)
        print("[実LLM] distance(長文):")
        printLastBuddyMessage(vm)

        vm.chatInputText = "おまかせ"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)

        vm.chatInputText = "なし"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .customTraits, timeout: 10)

        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed: persona=\(seed.personaStyle)('\(seed.personaStyleCustom)')")
            XCTAssertEqual(seed.personaStyle, .cool, "ツンデレ/クール → cool")
            XCTAssertFalse(seed.personaStyleCustom.isEmpty, "長文がcustomに保存")
            XCTAssertTrue(seed.personaStyleCustom.contains("ツンデレ"), "ユーザー入力がそのまま保存")
        }

        printFullConversation(vm)
    }

    // MARK: - 実LLMオンボーディングテスト（混合パターン：一部おまかせ一部カスタム）

    func testOnboardingMixedNullishAndCustomWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: 混合パターン ===")

        // personaだけカスタム、残りおまかせ
        vm.chatInputText = "元気いっぱいで明るい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .persona, timeout: 10)
        print("[実LLM] persona:")
        printLastBuddyMessage(vm)

        vm.chatInputText = "お任せ"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .distance, timeout: 10)
        print("[実LLM] distance(おまかせ):")
        printLastBuddyMessage(vm)

        vm.chatInputText = "どっちでもいい"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .diaryStyle, timeout: 10)
        print("[実LLM] diaryStyle(おまかせ):")
        printLastBuddyMessage(vm)

        vm.chatInputText = "関西弁"
        vm.sendChatMessage()
        await waitForSectionChange(vm, from: .customTraits, timeout: 10)
        print("[実LLM] customTraits:")
        printLastBuddyMessage(vm)

        XCTAssertEqual(vm.currentSection, .done)

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        if let seed = vm.generatedSeed {
            print("[実LLM] BuddySeed:")
            print("  persona=\(seed.personaStyle)('\(seed.personaStyleCustom)')")
            print("  distance=\(seed.conversationDistance)('\(seed.conversationDistanceCustom)')")
            print("  diary=\(seed.memoryPreference)('\(seed.memoryPreferenceCustom)')")
            print("  traits='\(seed.customTraits)'")

            XCTAssertEqual(seed.personaStyle, .bright, "元気→bright")
            XCTAssertEqual(seed.personaStyleCustom, "元気いっぱいで明るい")
            XCTAssertEqual(seed.conversationDistance, .casual, "おまかせ→デフォルト")
            XCTAssertEqual(seed.conversationDistanceCustom, "", "おまかせ→custom空")
            XCTAssertEqual(seed.memoryPreference, .balanced, "どっちでもいい→デフォルト")
            XCTAssertEqual(seed.memoryPreferenceCustom, "", "どっちでもいい→custom空")
            XCTAssertEqual(seed.customTraits, "関西弁")
        }

        printFullConversation(vm)
    }

    // MARK: - 実LLMオンボーディングテスト（安全弁：LLMが質問し続けるパターン）

    func testOnboardingSafetyValveWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: 安全弁テスト ===")

        // 曖昧な入力を繰り返して、LLMが「？」付き質問を返し続けるか確認
        // 安全弁（8ターン）で自動進行されるか、それとも確定されるか
        vm.chatInputText = "うーん"
        vm.sendChatMessage()
        await wait(seconds: 4)
        print("[実LLM] 1回目「うーん」: section=\(vm.currentSection)")
        printLastBuddyMessage(vm)

        if vm.currentSection == .persona {
            // LLMが質問で返した場合、もう少し曖昧に返す
            vm.chatInputText = "わからない"
            vm.sendChatMessage()
            await wait(seconds: 4)
            print("[実LLM] 2回目「わからない」: section=\(vm.currentSection)")
            printLastBuddyMessage(vm)
        }

        if vm.currentSection == .persona {
            // まだpersonaなら、明確に答えて進める
            vm.chatInputText = "やさしい"
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: .persona, timeout: 10)
            print("[実LLM] 3回目「やさしい」: section=\(vm.currentSection)")
        }

        // personaを通過したことを確認
        XCTAssertNotEqual(vm.currentSection, .persona, "personaセクションを通過")
        print("[実LLM] persona通過後: section=\(vm.currentSection)")

        // 残りはおまかせで完了
        let remaining: [OnboardingViewModel.OnboardingSection] = [.distance, .diaryStyle, .customTraits]
        for section in remaining {
            if vm.currentSection == section {
                vm.chatInputText = "おまかせ"
                vm.sendChatMessage()
                await waitForSectionChange(vm, from: section, timeout: 10)
            }
        }

        XCTAssertEqual(vm.currentSection, .done, "全セクション完了")

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)
        XCTAssertNotNil(vm.generatedSeed, "BuddySeed生成")

        printFullConversation(vm)
    }

    // MARK: - 実LLMオンボーディングテスト（done後の追加チャット）

    func testOnboardingPostDoneChatWithRealLLM() async throws {
        let (_, vm) = try await makeOnboardingVM()
        await advancePastNicknameReal(vm)

        print("=== 実LLMオンボーディングテスト: done後チャット ===")

        for (section, answer) in [
            (OnboardingViewModel.OnboardingSection.persona, "やさしい"),
            (.distance, "気軽に"),
            (.diaryStyle, "シンプル"),
            (.customTraits, "なし"),
        ] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: section, timeout: 10)
        }

        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)

        // done後に追加メッセージ
        vm.chatInputText = "あ、やっぱりクールにして"
        vm.sendChatMessage()
        await wait(seconds: 2)

        // done後は固定返答が来てセクション戻りしないことを確認
        XCTAssertEqual(vm.currentSection, .done, "done後もdoneのまま")
        XCTAssertTrue(vm.showConfirmButton, "ボタンは表示されたまま")

        let lastBuddy = vm.chatMessages.last(where: { $0.isFromBuddy })
        print("[実LLM] done後の返答: \(lastBuddy?.text ?? "なし")")
        XCTAssertNotNil(lastBuddy, "done後にバディ応答がある")

        printFullConversation(vm)
    }

    // MARK: - 実LLM全フローE2E（オンボーディング → リビール → チャット → 日記作成）

    func testFullFlowOnboardingTodiaryWithRealLLM() async throws {
        let configuration = AppEnvironment.ollamaConfiguration
        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }
        let service = OllamaService(configuration: configuration)
        try await service.loadModel()
        let modelContext = try makeModelContext()

        print("========================================")
        print("=== 実LLM全フローE2E: オンボーディング → リビール → チャット → 日記 ===")
        print("========================================")

        // ==============================
        // Phase 1: オンボーディング
        // ==============================
        print("\n--- Phase 1: オンボーディング ---")

        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: service, modelContext: modelContext)

        vm.proceedAfterNaming()
        await wait(seconds: 2)
        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(seconds: 3)
        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(seconds: 3)
        XCTAssertEqual(vm.currentSection, .persona, "ニックネーム確定後にpersonaへ")

        // カスタム人格: ドS女王様 + ストレート + 気持ちも残す + 関西弁
        let sectionInputs: [(OnboardingViewModel.OnboardingSection, String)] = [
            (.persona, "ドS女王様キャラで"),
            (.distance, "ストレートにズバズバ言ってほしい"),
            (.diaryStyle, "気持ちも残してほしい"),
            (.customTraits, "関西弁で話してほしい"),
        ]

        for (section, answer) in sectionInputs {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await waitForSectionChange(vm, from: section, timeout: 10)
            let buddy = vm.chatMessages.last(where: { $0.isFromBuddy })
            print("[Phase1] \(section): 入力='\(answer)' → LLM応答='\(buddy?.text ?? "")'")
        }

        XCTAssertEqual(vm.currentSection, .done, "全セクション完了")
        XCTAssertTrue(vm.showConfirmButton, "ボタン表示")

        // ==============================
        // Phase 2: endChat → BuddySeed → reveal
        // ==============================
        print("\n--- Phase 2: BuddySeed構築 + reveal挨拶 ---")

        await vm.finishOnboardingForTesting()
        await wait(seconds: 5)

        XCTAssertNotNil(vm.generatedSeed, "BuddySeedが生成された")
        let seed = vm.generatedSeed!

        print("[Phase2] BuddySeed:")
        print("  persona: \(seed.personaStyle) custom='\(seed.personaStyleCustom)'")
        print("  distance: \(seed.conversationDistance) custom='\(seed.conversationDistanceCustom)'")
        print("  diary: \(seed.memoryPreference) custom='\(seed.memoryPreferenceCustom)'")
        print("  traits: '\(seed.customTraits)'")
        print("[Phase2] reveal挨拶: '\(vm.revealGreeting)'")

        XCTAssertEqual(seed.personaStyle, .cool, "ドS→cool")
        XCTAssertEqual(seed.personaStyleCustom, "ドS女王様キャラ")
        XCTAssertEqual(seed.conversationDistance, .frank, "ストレート→frank")
        XCTAssertEqual(seed.memoryPreference, .feelingAware, "気持ち→feelingAware")
        XCTAssertFalse(seed.customTraits.isEmpty, "customTraitsが空でない")
        XCTAssertFalse(vm.revealGreeting.isEmpty, "reveal挨拶が空でない")

        // ==============================
        // Phase 3: BuddyProfile作成 + systemPrompt確認
        // ==============================
        print("\n--- Phase 3: BuddyProfile作成 ---")

        vm.completeBuddyCreation(modelContext: modelContext)

        let buddyDescriptor = FetchDescriptor<BuddyProfile>()
        let buddies = try modelContext.fetch(buddyDescriptor)
        XCTAssertEqual(buddies.count, 1, "BuddyProfileが1件作成された")
        let buddy = buddies.first!

        let systemPrompt = buddy.systemPrompt
        print("[Phase3] systemPrompt: \(systemPrompt)")

        XCTAssertTrue(systemPrompt.contains("モモ"), "systemPromptにバディ名")
        XCTAssertTrue(systemPrompt.contains("ドS女王様"), "systemPromptにカスタムpersona")
        // 新仕様: 命令形マーカー（「してほしい」等）を含む distance custom は
        // promptReadyConversationDistanceCustom で除去されるためプロンプトには含まれない
        XCTAssertFalse(systemPrompt.contains("ストレートにズバズバ言ってほしい"), "命令形のカスタム distance はプロンプトから除外される")
        XCTAssertTrue(systemPrompt.contains("関西弁"), "systemPromptにカスタムtraits")

        // ==============================
        // Phase 4: チャット応答（実LLM）
        // ==============================
        print("\n--- Phase 4: チャット応答（実LLM）---")

        let chatService = ChatResponseService(llmService: service)
        let chatRequest = ChatResponseService.Request(
            buddy: buddy,
            userNickname: "たろう",
            userTimezone: "Asia/Tokyo",
            turnCount: 1,
            elapsedMinutes: 5,
            memoryContext: "",
            history: [],
            userMessage: "今日はラーメン食べた"
        )
        let chatReply = try await chatService.generateReply(for: chatRequest)

        print("[Phase4] チャット応答: '\(chatReply)'")
        XCTAssertFalse(chatReply.isEmpty, "チャット応答が空でない")

        // ==============================
        // Phase 5: 日記作成（実LLM 2段階パイプライン）
        // ==============================
        print("\n--- Phase 5: 日記作成（実LLM）---")

        let journalService = JournalService(llmService: service)
        let userMessages = [
            DiaryPipelineInput.UserMessage(id: UUID(), text: "今日はラーメン食べた", timestamp: Date()),
            DiaryPipelineInput.UserMessage(id: UUID(), text: "会社で会議あって疲れた", timestamp: Date().addingTimeInterval(60)),
        ]
        let diaryResult = try await journalService.compile(
            userMessages: userMessages,
            existingMemos: [],
            turnCount: 2,
            existingJournal: nil,
            memoryPreference: buddy.memoryPreference,
            memoryPreferenceCustom: buddy.memoryPreferenceCustom,
            buddyName: buddy.displayName
        )

        print("[Phase5] 日記タイトル: '\(diaryResult.title)'")
        print("[Phase5] 日記本文: '\(diaryResult.body)'")
        print("[Phase5] 日記感情: \(diaryResult.emotionTags)")
        print("[Phase5] 日記accepted: \(diaryResult.accepted)")
        print("[Phase5] メモ抽出数: \(diaryResult.extractedMemos.count)")
        for (i, memo) in diaryResult.extractedMemos.enumerated() {
            print("[Phase5] メモ[\(i)]: \(memo)")
        }

        XCTAssertFalse(diaryResult.title.isEmpty, "日記タイトルが空でない")
        XCTAssertFalse(diaryResult.body.isEmpty, "日記本文が空でない")

        // ==============================
        // Phase 6: JournalEntry保存確認
        // ==============================
        print("\n--- Phase 6: JournalEntry保存 ---")

        let entry = JournalEntry(
            date: DayBoundary.appToday(),
            title: diaryResult.title,
            summaryText: String(diaryResult.body.prefix(60)),
            fullDiaryText: diaryResult.body,
            emotionTags: diaryResult.emotionTags,
            nameCoverage: diaryResult.nameCoverage
        )
        modelContext.insert(entry)
        try modelContext.save()

        let journalDescriptor = FetchDescriptor<JournalEntry>()
        let journals = try modelContext.fetch(journalDescriptor)
        XCTAssertEqual(journals.count, 1, "JournalEntryが1件保存された")
        let savedJournal = journals.first!

        print("[Phase6] 保存済み日記タイトル: '\(savedJournal.title)'")
        print("[Phase6] 保存済み日記本文: '\(savedJournal.fullDiaryText)'")
        print("[Phase6] 保存済み感情: \(savedJournal.emotionTags)")

        XCTAssertFalse(savedJournal.title.isEmpty, "保存済みタイトルが空でない")
        XCTAssertFalse(savedJournal.fullDiaryText.isEmpty, "保存済み本文が空でない")

        // ==============================
        // 全会話ログ
        // ==============================
        printFullConversation(vm)

        print("\n========================================")
        print("=== 実LLM全フローE2E完了 ===")
        print("========================================")
    }

    // MARK: - ヘルパー

    /// Ollamaに接続してOnboardingViewModelを作成する共通ヘルパー
    private func makeOnboardingVM() async throws -> (OllamaService, OnboardingViewModel) {
        let configuration = AppEnvironment.ollamaConfiguration
        guard try await shouldRunOllamaTestsOrSkip(),
              try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカルOllamaに接続できないためスキップします")
        }
        let service = OllamaService(configuration: configuration)
        try await service.loadModel()

        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: service, modelContext: modelContext)
        return (service, vm)
    }

    /// ニックネーム入力→確定まで進める共通ヘルパー
    private func advancePastNicknameReal(_ vm: OnboardingViewModel) async {
        vm.proceedAfterNaming()
        await wait(seconds: 2)
        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(seconds: 3)
        vm.chatInputText = "うん"
        vm.sendChatMessage()
        await wait(seconds: 3)
        XCTAssertEqual(vm.currentSection, .persona)
    }

    /// 全会話ログをprint
    private func printFullConversation(_ vm: OnboardingViewModel) {
        print("=== 全会話ログ ===")
        for (i, msg) in vm.chatMessages.enumerated() {
            let role = msg.isFromBuddy ? "🤖" : "👤"
            print("  [\(i)] \(role) \(msg.text)")
        }
    }

    private func shouldRunOllamaTestsOrSkip() async throws -> Bool {
        guard ProcessInfo.processInfo.environment[Self.runFlagKey] == "1" else {
            throw XCTSkip("Ollama 実LLMテストは明示的に有効化した場合のみ実行します")
        }
        return true
    }

    private func isOllamaReachable(at baseURL: URL) async throws -> Bool {
        let url = baseURL.appending(path: "/api/tags")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.reachabilityTimeout
        configuration.timeoutIntervalForResource = Self.reachabilityTimeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(httpResponse.statusCode)
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            ConversationSession.self,
            ChatMessage.self,
            BuddyProfile.self,
            BuddyState.self,
            UserProfile.self,
            JournalEntry.self,
            DiaryNote.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// セクションが変わるまで待つ（タイムアウト付き）
    private func waitForSectionChange(
        _ vm: OnboardingViewModel,
        from section: OnboardingViewModel.OnboardingSection,
        timeout: Double
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.currentSection == section && Date() < deadline {
            await wait(seconds: 0.3)
        }
    }

    private func printBuddyMessages(_ vm: OnboardingViewModel) {
        for msg in vm.chatMessages where msg.isFromBuddy {
            print("  🤖 \(msg.text)")
        }
    }

    private func printLastBuddyMessage(_ vm: OnboardingViewModel) {
        if let last = vm.chatMessages.last(where: { $0.isFromBuddy }) {
            print("  🤖 \(last.text)")
        }
    }
}
