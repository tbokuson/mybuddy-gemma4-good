import XCTest
@testable import MyBuddy

/// DiaryPipeline の統合テスト。
///
/// モック LLM を注入し、MemoExtractionStage → ThinkingDiaryStage → VerifyStage の
/// 2段階パイプラインが正しく動作することを検証する。
@MainActor
final class DiaryPipelineTests: XCTestCase {

    // MARK: - Mock LLM

    private final class MockLLMService: LLMServiceProtocol {
        var isLoaded = true
        var isGenerating = false
        var visionLoaded = false
        var backendDescription = "mock"
        var requiresLocalModelAssets = false

        /// generate() の呼出ごとに返すテキストのキュー。空になったら最後の値を繰り返す。
        var generateResults: [String] = [""]
        /// generate() の呼出回数
        var generateCallCount = 0
        /// generate() に渡された prompt 一覧
        var prompts: [String] = []

        func loadModel() async throws {}
        func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            generateCallCount += 1
            prompts.append(prompt)
            if generateResults.count > 1 {
                return generateResults.removeFirst()
            }
            return generateResults.first ?? ""
        }
        func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func loadVision() async throws {}
        func unloadVision() {}
        func generateWithImage(prompt: String, imageData: Data, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            ""
        }
    }

    // MARK: - Helpers

    private let baseDate = Date(timeIntervalSince1970: 1000)

    private func makeInput(
        userTexts: [String],
        existingMemos: [DiaryPipelineInput.MemoSnapshot] = [],
        buddyName: String = "バディ"
    ) -> DiaryPipelineInput {
        var userMsgs: [DiaryPipelineInput.UserMessage] = []
        for (i, text) in userTexts.enumerated() {
            userMsgs.append(DiaryPipelineInput.UserMessage(
                id: UUID(), text: text, timestamp: baseDate.addingTimeInterval(Double(i) * 20)
            ))
        }
        return DiaryPipelineInput(
            userMessages: userMsgs,
            conversationTurns: userMsgs.map {
                DiaryPipelineInput.ConversationTurn(id: $0.id, role: .user, text: $0.text, timestamp: $0.timestamp)
            },
            existingMemos: existingMemos,
            existingJournal: nil,
            memoryPreference: .balanced,
            memoryPreferenceCustom: "",
            buddyName: buddyName,
            buddySeed: .appDefault,
            turnCount: userTexts.count
        )
    }

    // MARK: - 正常系

    func testPipelineReturnsAcceptedResultOnValidOutput() async throws {
        let mock = MockLLMService()
        // 1回目: メモ抽出、2回目: 日記生成
        mock.generateResults = [
            """
            - 横浜に行った
            - 中華街で食事した
            """,
            """
            タイトル: 横浜散歩の一日
            感情: 楽しい, リラックス
            本文: 今日は横浜に行って中華街で食事をした。天気がよくて気持ちよかった。
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(
            userTexts: ["今日は横浜に行ったよ", "中華街で食事した"]
        )

        let result = try await pipeline.run(input: input)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.title, "横浜散歩の一日")
        XCTAssertFalse(result.body.isEmpty)
        XCTAssertTrue(result.body.contains("横浜"))
        XCTAssertEqual(result.emotionTags.count, 2)
        XCTAssertFalse(result.extractedMemos.isEmpty)
        XCTAssertEqual(mock.generateCallCount, 2, "LLM呼出はメモ抽出+日記生成の2回")
    }

    func testPipelinePassesConversationReferenceToThinkingStagePrompt() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- 朝に渋谷でコーヒーを飲んだ",
            """
            タイトル: 朝の渋谷時間
            感情: 落ち着く
            本文: 朝に渋谷でコーヒーを飲んでから、落ち着いた気分で一日を始めた。
            """
        ]

        let userMessage = DiaryPipelineInput.UserMessage(
            id: UUID(),
            text: "朝に渋谷でコーヒーを飲んだ",
            timestamp: baseDate
        )
        let input = DiaryPipelineInput(
            userMessages: [userMessage],
            conversationTurns: [
                .init(id: UUID(), role: .buddy, text: "今日はどんな始まりだった？", timestamp: baseDate),
                .init(id: userMessage.id, role: .user, text: userMessage.text, timestamp: userMessage.timestamp),
            ],
            existingMemos: [],
            existingJournal: nil,
            memoryPreference: .balanced,
            memoryPreferenceCustom: "",
            buddyName: "バディ",
            buddySeed: .appDefault,
            turnCount: 1
        )

        _ = try await DiaryPipeline(llmService: mock, config: .default).run(input: input)

        let thinkingPrompt = try XCTUnwrap(mock.prompts.last)
        XCTAssertTrue(thinkingPrompt.contains("【会話の断片】"))
        XCTAssertTrue(thinkingPrompt.contains("バディ発話（本文に書かない）: 今日はどんな始まりだった？"))
        XCTAssertTrue(thinkingPrompt.contains("ユーザー発話: 朝に渋谷でコーヒーを飲んだ"))
    }

    func testPipelineWithExistingMemosSkipsMemoExtraction() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            """
            タイトル: テスト日記
            感情: 普通
            本文: テスト本文です。
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(
            userTexts: [],  // 未処理メッセージなし
            existingMemos: [
                DiaryPipelineInput.MemoSnapshot(fact: "テスト事実", emotion: "", createdAt: baseDate)
            ]
        )

        let result = try await pipeline.run(input: input)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(mock.generateCallCount, 1, "メモ抽出スキップで日記生成のみ1回")
        XCTAssertTrue(result.extractedMemos.isEmpty, "新規メモ抽出なし")
    }

    // MARK: - thinking ブロック除去

    func testPipelineStripsThinkingBlock() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- 横浜を散歩した",
            """
            <think>
            ユーザーは横浜について話している。
            </think>
            タイトル: 横浜の散歩
            感情: 穏やか
            本文: 今日は横浜を散歩した。
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["横浜を散歩した"])

        let result = try await pipeline.run(input: input)

        XCTAssertFalse(result.body.contains("<think>"))
        XCTAssertFalse(result.body.contains("</think>"))
        XCTAssertTrue(result.body.contains("横浜"))
    }

    // MARK: - フォールバック

    func testPipelineFallsBackWhenLabelsAreMissing() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- 何もなかった",
            "今日は何もなかった。普通の一日だった。"
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["何もなかったな"])

        let result = try await pipeline.run(input: input)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.title, "今日の日記")
        XCTAssertTrue(result.emotionTags.isEmpty)
        XCTAssertFalse(result.body.isEmpty)
    }

    func testPipelineRecoversFromBracketedMemoAndMetaDiaryLeak() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- <朝から仕事だった> | なし",
            """
            <|channel>thought
            ユーザーは提供されたメモに基づき、特定のルールに従って日記を作成するように求めている。

            【今日のメモ】
            - 朝から仕事だった
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["朝から仕事だった"])

        let result = try await pipeline.run(input: input)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.extractedMemos.first?.fact, "朝から仕事だった")
        XCTAssertFalse(result.body.contains("【今日のメモ】"))
        XCTAssertFalse(result.body.contains("ユーザーは提供されたメモ"))
        XCTAssertEqual(result.body, "朝から仕事だった。")
    }

    func testMinimalNewJournalFormatsFallbackAsDiaryProse() {
        let result = JournalService.minimalNewJournal(
            userMessages: [
                DiaryPipelineInput.UserMessage(id: UUID(), text: "横浜に行った", timestamp: baseDate),
                DiaryPipelineInput.UserMessage(id: UUID(), text: "ジョイポリスで遊んだ", timestamp: baseDate.addingTimeInterval(10)),
                DiaryPipelineInput.UserMessage(id: UUID(), text: "小籠包を食べた", timestamp: baseDate.addingTimeInterval(20))
            ]
        )

        XCTAssertTrue(result.body.hasPrefix("今日は横浜に行った。"))
        XCTAssertTrue(result.body.contains("そのあと、ジョイポリスで遊んだ。"))
        XCTAssertTrue(result.body.contains("また、小籠包を食べた。"))
        XCTAssertFalse(result.body.contains("\n"))
    }

    // MARK: - VerifyStage 品質ガード

    func testPipelineRejectsWhenCoverageDrops() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- 横浜でジョイポリスに行った",
            """
            タイトル: ぼんやりとした一日
            感情: 退屈
            本文: 今日はぼんやりと過ごした。
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = DiaryPipelineInput(
            userMessages: [
                DiaryPipelineInput.UserMessage(id: UUID(), text: "横浜でジョイポリスに行った", timestamp: Date())
            ],
            conversationTurns: [],
            existingMemos: [],
            existingJournal: DiaryPipelineInput.ExistingJournalSnapshot(
                title: "前の日記",
                body: "横浜のジョイポリスに行った",
                emotionTags: [],
                tomorrowNote: "",
                nameCoverage: 1.0
            ),
            memoryPreference: .balanced,
            memoryPreferenceCustom: "",
            buddyName: "バディ",
            buddySeed: .appDefault,
            turnCount: 1
        )

        let result = try await pipeline.run(input: input)

        XCTAssertFalse(result.accepted)
        XCTAssertNotNil(result.rejectionReason)
    }

    // MARK: - バディからの一言

    func testPipelineFillsBuddyCommentWhenLLMOutputOmitsIt() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            "- テスト",
            """
            タイトル: テスト
            感情: 普通
            本文: テスト。
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["テスト"])

        let result = try await pipeline.run(input: input)

        XCTAssertFalse(result.tomorrowNote.isEmpty)
    }

    // MARK: - キャンセル

    func testPipelineThrowsCancellationWhenTaskIsCancelled() async throws {
        let mock = MockLLMService()
        mock.generateResults = [""]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["テスト"])

        let task = Task {
            try await pipeline.run(input: input)
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // 期待動作
        }
    }

    // MARK: - メモ抽出

    func testExtractMemosReturnsExtractedItems() async throws {
        let mock = MockLLMService()
        mock.generateResults = [
            """
            - カレーを食べた
            - 京都に旅行中
            - 上司の中村に怒られた（悔しい）
            """
        ]

        let pipeline = DiaryPipeline(llmService: mock, config: .default)
        let input = makeInput(userTexts: ["カレー食べた", "京都にいる", "中村に怒られた"])

        let memos = try await pipeline.extractMemos(input: input)

        XCTAssertEqual(memos.count, 3)
        XCTAssertEqual(memos[0].fact, "カレーを食べた")
        XCTAssertEqual(memos[2].fact, "上司の中村に怒られた")
        XCTAssertEqual(memos[2].emotion, "悔しい")
    }
}
