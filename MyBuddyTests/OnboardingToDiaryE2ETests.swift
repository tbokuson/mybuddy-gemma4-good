import XCTest
import SwiftData
@testable import MyBuddy

/// オンボーディング → リビール → 日記作成の一気通貫テスト。
///
/// 通常人格（デフォルト enum）とカスタム人格（ドS女王様+東北弁）の2パターンで
/// - オンボーディング完了時の BuddyProfile にカスタム人格が正しくセットされること
/// - システムプロンプトにカスタム人格が反映されること
/// - 日記作成会話（ChatResponseService）のプロンプトに人格が反映されること
/// - DiaryPipeline が正しく日記を生成すること
/// を検証する。
@MainActor
final class OnboardingToDiaryE2ETests: XCTestCase {

    // MARK: - Mock LLM（プロンプトキャプチャ機能付き）

    private final class MockLLMService: LLMServiceProtocol {
        var isLoaded = true
        var isGenerating = false
        var visionLoaded = false
        var backendDescription = "mock"
        var requiresLocalModelAssets = false

        var generateResponses: [String] = []
        var streamResponses: [String] = []
        /// generate() に渡されたプロンプトのログ
        var generatePromptLog: [String] = []
        /// generateStream() に渡されたプロンプトのログ
        var streamPromptLog: [String] = []

        func loadModel() async throws {}

        func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            generatePromptLog.append(prompt)
            if !generateResponses.isEmpty {
                return generateResponses.removeFirst()
            }
            return ""
        }

        func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error> {
            streamPromptLog.append(prompt)
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

    // MARK: - ヘルパー

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

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    /// オンボーディングVMのニックネーム確定まで進めるヘルパー
    private func advancePastNickname(_ vm: OnboardingViewModel, llm: MockLLMService) async {
        llm.generateResponses.append("たろう")  // ニックネーム抽出
        llm.generateResponses.append("")         // LLMウォームアップ

        vm.proceedAfterNaming()
        await wait(milliseconds: 50)

        vm.chatInputText = "たろう"
        vm.sendChatMessage()
        await wait(milliseconds: 100)

        vm.chatInputText = "はい"
        vm.sendChatMessage()
        await wait(milliseconds: 200)
    }

    // MARK: - テスト1: 通常人格（デフォルト enum）E2E

    func testDefaultPersonaOnboardingToDiary() async throws {
        let llm = MockLLMService()
        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: llm, modelContext: modelContext)

        // --- Phase 1: オンボーディング（全おまかせ → デフォルト人格）---

        print("=== Phase 1: オンボーディング（通常人格）===")

        llm.streamResponses = [
            "おまかせだね！",
            "おまかせだね！",
            "おまかせだね！",
            "了解！",
        ]

        await advancePastNickname(vm, llm: llm)

        for answer in ["おまかせ", "おまかせ", "おまかせ", "なし"] {
            vm.chatInputText = answer
            vm.sendChatMessage()
            await wait(milliseconds: 200)
        }

        XCTAssertEqual(vm.currentSection, .done)
        XCTAssertTrue(vm.showConfirmButton)

        // reveal用応答
        llm.generateResponses.append("これからよろしくね。")
        llm.generateResponses.append(contentsOf: ["今日どうだった？", "なんかあった？", "元気？"])

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        XCTAssertNotNil(vm.generatedSeed)
        let seed = vm.generatedSeed!

        print("[E2E] BuddySeed: persona=\(seed.personaStyle) custom='\(seed.personaStyleCustom)' distance=\(seed.conversationDistance) customDist='\(seed.conversationDistanceCustom)' diary=\(seed.memoryPreference) customDiary='\(seed.memoryPreferenceCustom)' traits='\(seed.customTraits)'")

        // デフォルト値の確認
        XCTAssertEqual(seed.personaStyle, .gentle)
        XCTAssertEqual(seed.personaStyleCustom, "")
        XCTAssertEqual(seed.conversationDistance, .casual)
        XCTAssertEqual(seed.conversationDistanceCustom, "")
        XCTAssertEqual(seed.memoryPreference, .balanced)
        XCTAssertEqual(seed.memoryPreferenceCustom, "")
        XCTAssertEqual(seed.customTraits, "")

        // --- Phase 2: BuddyProfile 作成 + systemPrompt 確認 ---

        print("\n=== Phase 2: BuddyProfile 作成（通常人格）===")

        vm.completeBuddyCreation(modelContext: modelContext)

        let buddyDescriptor = FetchDescriptor<BuddyProfile>()
        let buddies = try modelContext.fetch(buddyDescriptor)
        XCTAssertEqual(buddies.count, 1)
        let buddy = buddies.first!

        let systemPrompt = buddy.systemPrompt
        print("[E2E] systemPrompt: \(systemPrompt)")

        // デフォルト enum の説明が含まれること
        XCTAssertTrue(systemPrompt.contains("モモ"), "バディ名が含まれる")
        XCTAssertTrue(systemPrompt.contains("安心感"), "gentle の personalityDescription が含まれる")
        XCTAssertTrue(systemPrompt.contains("穏やか") || systemPrompt.contains("やさしい"), "gentle の voiceDescription が含まれる")
        // カスタム値が空なので「最優先の希望」は含まれない
        XCTAssertFalse(systemPrompt.contains("最優先の希望"), "カスタム未設定時は「最優先の希望」が含まれない")

        // --- Phase 3: チャット会話（ChatResponseService）でプロンプト確認 ---

        print("\n=== Phase 3: チャット会話プロンプト確認（通常人格）===")

        let chatLLM = MockLLMService()
        let chatService = ChatResponseService(llmService: chatLLM)
        chatLLM.generateResponses.append("ラーメンいいね！何ラーメン？")

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

        print("[E2E] チャットプロンプト: \(chatLLM.generatePromptLog.last ?? "none")")
        print("[E2E] チャット応答: \(chatReply)")

        let chatPrompt = chatLLM.generatePromptLog.last!
        XCTAssertTrue(chatPrompt.contains("モモ"), "チャットプロンプトにバディ名")
        XCTAssertTrue(chatPrompt.contains("安心感") || chatPrompt.contains("穏やか"), "チャットプロンプトにgentle人格")
        XCTAssertFalse(chatPrompt.contains("最優先の希望"), "カスタム未設定時は「最優先の希望」なし")

        // --- Phase 4: 日記作成 ---

        print("\n=== Phase 4: 日記作成（通常人格）===")

        let diaryLLM = MockLLMService()
        // Stage 1: メモ抽出応答
        diaryLLM.generateResponses.append("- ラーメンを食べた（満足）")
        // Stage 2: 日記生成応答
        diaryLLM.generateResponses.append("""
        タイトル: ラーメンの一日
        感情: 満足
        本文: 今日はラーメンを食べた。
        """)

        let journalService = JournalService(llmService: diaryLLM)
        let userMessages = [
            DiaryPipelineInput.UserMessage(id: UUID(), text: "今日はラーメン食べた", timestamp: Date()),
        ]
        let diaryResult = try await journalService.compile(
            userMessages: userMessages,
            existingMemos: [],
            turnCount: 1,
            existingJournal: nil,
            memoryPreference: buddy.memoryPreference,
            memoryPreferenceCustom: buddy.memoryPreferenceCustom,
            buddyName: buddy.displayName
        )

        print("[E2E] 日記タイトル: \(diaryResult.title)")
        print("[E2E] 日記本文: \(diaryResult.body)")
        print("[E2E] 日記感情: \(diaryResult.emotionTags)")
        print("[E2E] 日記accepted: \(diaryResult.accepted)")
        print("[E2E] メモ抽出数: \(diaryResult.extractedMemos.count)")

        // Stage 2（日記生成）のプロンプトに日記スタイルが反映されていること
        let diaryPrompt = diaryLLM.generatePromptLog.last!
        print("[E2E] 日記生成プロンプト: \(diaryPrompt)")
        XCTAssertTrue(diaryPrompt.contains("出来事"), "balanced の journalInstruction が含まれる")

        XCTAssertTrue(diaryResult.accepted, "品質ガード通過")
        XCTAssertFalse(diaryResult.body.isEmpty, "日記本文が空でない")
        XCTAssertEqual(diaryResult.title, "ラーメンの一日")
        XCTAssertTrue(diaryResult.extractedMemos.count > 0, "メモが抽出されている")

        print("\n=== 通常人格 E2E 完了 ===")
    }

    // MARK: - テスト2: カスタム人格（ドS女王様+東北弁）E2E

    func testCustomPersonaOnboardingToDiary() async throws {
        let llm = MockLLMService()
        let modelContext = try makeModelContext()
        let vm = OnboardingViewModel()
        vm.buddyName = "モモ"
        vm.typingDelayMilliseconds = 10
        vm.configure(llmService: llm, modelContext: modelContext)

        // --- Phase 1: オンボーディング（カスタム人格）---

        print("\n=== Phase 1: オンボーディング（カスタム人格）===")

        llm.streamResponses = [
            "つまり、ドS女王様って感じだね！",      // persona
            "ストレートに言ってほしいんだね！",      // distance
            "気持ちも大事に残すんだね！",           // diaryStyle
            "東北弁で話すってことだね！",           // customTraits
        ]

        await advancePastNickname(vm, llm: llm)

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
        XCTAssertTrue(vm.showConfirmButton)

        // reveal用応答
        llm.generateResponses.append("ふん、これからよろしくだべ。")
        llm.generateResponses.append(contentsOf: ["今日はなんかあったべか？", "元気だべか？", "どうだったべ？"])

        await vm.finishOnboardingForTesting()
        await wait(milliseconds: 500)

        XCTAssertNotNil(vm.generatedSeed)
        let seed = vm.generatedSeed!

        print("[E2E] BuddySeed: persona=\(seed.personaStyle) custom='\(seed.personaStyleCustom)' distance=\(seed.conversationDistance) customDist='\(seed.conversationDistanceCustom)' diary=\(seed.memoryPreference) customDiary='\(seed.memoryPreferenceCustom)' traits='\(seed.customTraits)'")

        // カスタム値の確認（ユーザー入力がそのまま保存される）
        XCTAssertEqual(seed.personaStyle, .cool, "ドS → cool")
        XCTAssertEqual(seed.personaStyleCustom, "ドS女王様")
        XCTAssertEqual(seed.conversationDistance, .frank, "ストレート → frank")
        XCTAssertEqual(seed.conversationDistanceCustom, "ストレートに言ってほしい")
        XCTAssertEqual(seed.memoryPreference, .feelingAware, "気持ち → feelingAware")
        // 新仕様: diaryStyle の汎用キーワード短文（「気持ち」等）は normalizedStoredCustomText で "" になる
        XCTAssertEqual(seed.memoryPreferenceCustom, "")
        XCTAssertEqual(seed.customTraits, "東北弁で話して")

        // --- Phase 2: BuddyProfile 作成 + systemPrompt 確認 ---

        print("\n=== Phase 2: BuddyProfile 作成（カスタム人格）===")

        vm.completeBuddyCreation(modelContext: modelContext)

        let buddyDescriptor = FetchDescriptor<BuddyProfile>()
        let buddies = try modelContext.fetch(buddyDescriptor)
        XCTAssertEqual(buddies.count, 1)
        let buddy = buddies.first!

        // BuddyProfile のフィールド確認（ユーザー入力がそのまま保存される）
        XCTAssertEqual(buddy.personaStyle, .cool)
        XCTAssertEqual(buddy.personaStyleCustom, "ドS女王様")
        XCTAssertEqual(buddy.conversationDistance, .frank)
        XCTAssertEqual(buddy.conversationDistanceCustom, "ストレートに言ってほしい")
        XCTAssertEqual(buddy.memoryPreference, .feelingAware)
        // 新仕様: diaryStyle の汎用キーワード短文は normalizedStoredCustomText で "" になる
        XCTAssertEqual(buddy.memoryPreferenceCustom, "")
        XCTAssertEqual(buddy.customTraits, "東北弁で話して")

        let systemPrompt = buddy.systemPrompt
        print("[E2E] systemPrompt: \(systemPrompt)")

        // カスタム値がシステムプロンプトに反映されること
        XCTAssertTrue(systemPrompt.contains("モモ"), "バディ名が含まれる")
        XCTAssertTrue(systemPrompt.contains("ドS女王様"), "カスタム persona が含まれる")
        // 新仕様 (BuddyProfile.promptReadyConversationDistanceCustom): 命令形マーカー（「してほしい」等）を
        // 含む distance custom はプロンプト構築時に除去される。よってシステムプロンプトには含まれない。
        XCTAssertFalse(systemPrompt.contains("ストレートに言ってほしい"), "命令形のカスタム distance はプロンプトから除外される")
        XCTAssertTrue(systemPrompt.contains("東北弁で話して"), "カスタム traits が含まれる")
        // カスタム値がある場合、enum の冗長な例文は含まれないこと
        XCTAssertFalse(systemPrompt.contains("相手のペースに合わせる"), "enum gentle の説明は含まれない（cool カスタムで上書き）")

        // --- Phase 3: チャット会話（ChatResponseService）でプロンプト確認 ---

        print("\n=== Phase 3: チャット会話プロンプト確認（カスタム人格）===")

        let chatLLM = MockLLMService()
        let chatService = ChatResponseService(llmService: chatLLM)
        chatLLM.generateResponses.append("ふん、ラーメンだべか。何ラーメンだべ？")

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

        let chatPrompt = chatLLM.generatePromptLog.last!
        print("[E2E] チャットプロンプト: \(chatPrompt)")
        print("[E2E] チャット応答: \(chatReply)")

        // カスタム人格がチャットプロンプトに反映
        XCTAssertTrue(chatPrompt.contains("ドS女王様"), "チャットプロンプトにカスタムpersona")
        // 新仕様: 命令形マーカーを含む distance custom はプロンプトから除外される
        XCTAssertFalse(chatPrompt.contains("ストレートに言ってほしい"), "命令形のカスタム distance はチャットプロンプトから除外される")
        XCTAssertTrue(chatPrompt.contains("東北弁で話して"), "チャットプロンプトにカスタムtraits")
        XCTAssertTrue(chatPrompt.contains("たろう"), "チャットプロンプトにユーザーニックネーム")

        // --- Phase 4: 日記作成（カスタム日記スタイル反映確認）---

        print("\n=== Phase 4: 日記作成（カスタム人格）===")

        let diaryLLM = MockLLMService()
        // Stage 1: メモ抽出応答
        diaryLLM.generateResponses.append("- ラーメンを食べた（満足）\n- 会社で会議があった（疲れた）")
        // Stage 2: 日記生成応答
        diaryLLM.generateResponses.append("""
        タイトル: ラーメンと会議の一日
        感情: 満足, 疲れた
        本文: 今日はラーメンを食べた。会社で会議があって疲れた。ラーメンで少し元気が出た気がする。
        """)

        let journalService = JournalService(llmService: diaryLLM)
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

        print("[E2E] 日記タイトル: \(diaryResult.title)")
        print("[E2E] 日記本文: \(diaryResult.body)")
        print("[E2E] 日記感情: \(diaryResult.emotionTags)")
        print("[E2E] 日記accepted: \(diaryResult.accepted)")
        print("[E2E] メモ抽出数: \(diaryResult.extractedMemos.count)")

        // Stage 1（メモ抽出）のプロンプト
        let memoPrompt = diaryLLM.generatePromptLog.first!
        print("[E2E] メモ抽出プロンプト: \(memoPrompt)")

        // Stage 2（日記生成）のプロンプトにカスタム日記スタイルが反映されていること
        let diaryPrompt = diaryLLM.generatePromptLog.last!
        print("[E2E] 日記生成プロンプト: \(diaryPrompt)")

        // feelingAware + カスタム「気持ちも残したい」
        XCTAssertTrue(
            diaryPrompt.contains("気持ちも残したい") || diaryPrompt.contains("感情") || diaryPrompt.contains("気持ち"),
            "カスタム日記スタイルまたはfeelingAwareの指示が日記生成プロンプトに含まれる"
        )

        XCTAssertTrue(diaryResult.accepted, "品質ガード通過")
        XCTAssertFalse(diaryResult.body.isEmpty, "日記本文が空でない")
        XCTAssertEqual(diaryResult.title, "ラーメンと会議の一日")
        XCTAssertTrue(diaryResult.emotionTags.contains("満足"), "感情タグに「満足」")
        XCTAssertTrue(diaryResult.emotionTags.contains("疲れた"), "感情タグに「疲れた」")
        XCTAssertTrue(diaryResult.extractedMemos.count >= 1, "メモが抽出されている")
        XCTAssertTrue(diaryResult.body.contains("ラーメン"), "日記本文にラーメンが含まれる")

        // --- Phase 5: JournalEntry を SwiftData に保存して確認 ---

        print("\n=== Phase 5: JournalEntry 保存確認 ===")

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
        XCTAssertEqual(journals.count, 1)
        let savedJournal = journals.first!

        print("[E2E] 保存済み日記タイトル: \(savedJournal.title)")
        print("[E2E] 保存済み日記本文: \(savedJournal.fullDiaryText)")
        print("[E2E] 保存済み感情タグ: \(savedJournal.emotionTags)")

        XCTAssertEqual(savedJournal.title, "ラーメンと会議の一日")
        XCTAssertTrue(savedJournal.fullDiaryText.contains("ラーメン"))
        XCTAssertTrue(savedJournal.emotionTags.contains("満足"))

        print("\n=== カスタム人格 E2E 完了 ===")
    }

    // MARK: - テスト3: カスタム人格 vs デフォルト人格のシステムプロンプト比較

    func testCustomVsDefaultSystemPromptDifferences() throws {
        print("\n=== システムプロンプト比較テスト ===")

        // デフォルト人格
        let defaultSeed = BuddySeed(
            bodyId: "round", eyeId: "sparkle", earId: "round", mouthId: "smile",
            paletteId: "pastel",
            accentIds: ["emotion_warm", "interest_daily"],
            personaStyle: .gentle,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "",
            personaStyleCustom: "",
            conversationDistanceCustom: "",
            memoryPreferenceCustom: "",
            roomThemeId: "room_default"
        )

        // カスタム人格
        let customSeed = BuddySeed(
            bodyId: "round", eyeId: "sparkle", earId: "round", mouthId: "smile",
            paletteId: "pastel",
            accentIds: ["emotion_cool", "interest_goals"],
            personaStyle: .cool,
            conversationDistance: .frank,
            memoryPreference: .feelingAware,
            personalityNotes: "",
            customTraits: "東北弁で話して",
            personaStyleCustom: "ドS女王様",
            conversationDistanceCustom: "ストレートに言ってほしい",
            memoryPreferenceCustom: "気持ちも残したい",
            roomThemeId: "room_default"
        )

        let defaultPrompt = BuddyProfile.buildSystemPrompt(displayName: "モモ", seed: defaultSeed, userNickname: "たろう")
        let customPrompt = BuddyProfile.buildSystemPrompt(displayName: "モモ", seed: customSeed, userNickname: "たろう")

        print("[比較] デフォルト: \(defaultPrompt)")
        print("[比較] カスタム:   \(customPrompt)")

        // デフォルト: enum 説明が含まれる
        XCTAssertTrue(defaultPrompt.contains("安心感"), "デフォルトには gentle の説明")
        XCTAssertTrue(defaultPrompt.contains("穏やか") || defaultPrompt.contains("やさしい"), "デフォルトには gentle の口調")
        XCTAssertTrue(defaultPrompt.contains("友達"), "デフォルトには casual の説明")

        // カスタム: カスタム値で上書き
        XCTAssertTrue(customPrompt.contains("ドS女王様"), "カスタムにはカスタム persona")
        // 新仕様 (BuddyProfile.promptReadyConversationDistanceCustom): 命令形マーカー（「してほしい」等）を
        // 含む distance custom はプロンプト構築時に除去される
        XCTAssertFalse(customPrompt.contains("ストレートに言ってほしい"), "命令形のカスタム distance はプロンプトから除外される")
        XCTAssertTrue(customPrompt.contains("東北弁で話して"), "カスタムにはカスタム traits")
        XCTAssertTrue(customPrompt.contains("たろう"), "カスタムにはニックネーム")

        // カスタム設定時は enum の長い例文が含まれない（Gemma 4 が例文をコピーする問題の対策）
        XCTAssertFalse(customPrompt.contains("〜だね"), "カスタム設定時は enum 語尾例が含まれない")
        XCTAssertFalse(customPrompt.contains("〜だよ"), "カスタム設定時は enum 語尾例が含まれない")

        // 日記スタイル: カスタムが使われること
        let defaultInstruction = defaultSeed.memoryPreference.customFirstJournalInstruction(custom: defaultSeed.memoryPreferenceCustom)
        let customInstruction = customSeed.memoryPreference.customFirstJournalInstruction(custom: customSeed.memoryPreferenceCustom)

        print("[比較] デフォルト日記指示: \(defaultInstruction)")
        print("[比較] カスタム日記指示:   \(customInstruction)")

        XCTAssertTrue(defaultInstruction.contains("出来事"), "デフォルトはbalancedの指示")
        XCTAssertFalse(defaultInstruction.contains("最優先"), "デフォルトは最優先なし")
        XCTAssertTrue(customInstruction.contains("最優先の希望"), "カスタムは最優先あり")
        XCTAssertTrue(customInstruction.contains("気持ちも残したい"), "カスタムの日記スタイル指示")

        print("\n=== システムプロンプト比較テスト完了 ===")
    }
}
