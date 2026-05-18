import XCTest
@testable import MyBuddy

/// ThinkingDiaryStage の純粋関数（パーサー / sanitizer / thinking ブロック除去）のユニットテスト。
///
/// LLM 呼び出しを含まないため高速に走る。
@MainActor
final class ThinkingDiaryStageTests: XCTestCase {

    // MARK: - thinking ブロック除去

    func testRemoveThinkingBlockRemovesClosedBlock() {
        let input = "<think>ここは思考過程です。\n色々考えました。</think>本文がここから始まる。"
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, "本文がここから始まる。")
    }

    func testRemoveThinkingBlockRemovesUnclosedBlock() {
        let input = "先頭テキスト<think>途中で切れた思考"
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, "先頭テキスト")
    }

    func testRemoveThinkingBlockPreservesTextWithoutThinkTag() {
        let input = "普通のテキスト。thinkingなし。"
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, input)
    }

    func testRemoveThinkingBlockHandlesMultipleBlocks() {
        let input = "<think>思考1</think>本文A<think>思考2</think>本文B"
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, "本文A本文B")
    }

    func testRemoveThinkingBlockTrimsWhitespace() {
        let input = "  <think>思考</think>  \n  結果テキスト  \n  "
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, "結果テキスト")
    }

    func testRemoveThinkingBlockRemovesChannelThoughtLeak() {
        let input = "<|channel>thought\n途中の思考が漏れた\n本文に行く前に切れた"
        let result = ThinkingDiaryStage.removeThinkingBlock(input)
        XCTAssertEqual(result, "")
    }

    // MARK: - メモテキスト構築

    func testBuildMemoTextFormatsMemosAsBulletList() {
        let memos = [
            MemoExtractionStage.MemoItem(fact: "カレーを食べた", emotion: ""),
            MemoExtractionStage.MemoItem(fact: "京都に旅行中", emotion: ""),
            MemoExtractionStage.MemoItem(fact: "上司に怒られた", emotion: "悔しい"),
        ]
        let text = ThinkingDiaryStage.buildMemoText(memos: memos)
        XCTAssertEqual(text, "- カレーを食べた\n- 京都に旅行中\n- 上司に怒られた（悔しい）")
    }

    func testBuildMemoTextSkipsEmptyFacts() {
        let memos = [
            MemoExtractionStage.MemoItem(fact: "", emotion: ""),
            MemoExtractionStage.MemoItem(fact: "テスト", emotion: ""),
        ]
        let text = ThinkingDiaryStage.buildMemoText(memos: memos)
        XCTAssertEqual(text, "- テスト")
    }

    func testBuildConversationReferenceFormatsRolesInOrder() {
        let turns: [DiaryPipelineInput.ConversationTurn] = [
            .init(id: UUID(), role: .buddy, text: "今日はどんな日だった？", timestamp: Date()),
            .init(id: UUID(), role: .user, text: "朝に渋谷でコーヒーを飲んだ", timestamp: Date()),
            .init(id: UUID(), role: .buddy, text: "それから？", timestamp: Date()),
        ]

        let text = ThinkingDiaryStage.buildConversationReference(conversationTurns: turns)

        XCTAssertEqual(
            text,
            """
            バディ発話（本文に書かない）: 今日はどんな日だった？
            ユーザー発話: 朝に渋谷でコーヒーを飲んだ
            バディ発話（本文に書かない）: それから？
            """
        )
    }

    func testBuildConversationReferenceSkipsEmptyTurns() {
        let turns: [DiaryPipelineInput.ConversationTurn] = [
            .init(id: UUID(), role: .user, text: "  ", timestamp: Date()),
            .init(id: UUID(), role: .buddy, text: "  また聞かせて  ", timestamp: Date()),
        ]

        let text = ThinkingDiaryStage.buildConversationReference(conversationTurns: turns)

        XCTAssertEqual(text, "バディ発話（本文に書かない）: また聞かせて")
    }

    // MARK: - 出力パース（正常系）

    func testParseExtractsTitleEmotionBody() {
        let raw = """
        タイトル: 横浜散歩の一日
        感情: 楽しい, わくわく
        本文: 今日は横浜に行った。海沿いを歩いて、とても気持ちよかった。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "ポチ")
        XCTAssertEqual(output.title, "横浜散歩の一日")
        XCTAssertTrue(output.emotionTags.contains("楽しい"))
        XCTAssertTrue(output.emotionTags.contains("わくわく"))
        XCTAssertTrue(output.body.contains("今日は横浜に行った"))
    }

    func testParseHandlesMultilineBody() {
        let raw = """
        タイトル: 充実した週末
        感情: 満足
        本文: 朝早く起きて散歩した。
        昼は友達とランチ。
        夜は映画を観た。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertTrue(output.body.contains("朝早く起きて散歩した"))
        XCTAssertTrue(output.body.contains("昼は友達とランチ"))
        XCTAssertTrue(output.body.contains("夜は映画を観た"))
    }

    func testParseHandlesFullWidthColon() {
        let raw = """
        タイトル：休日のカフェ
        感情：リラックス、穏やか
        本文：今日はカフェでゆっくり過ごした。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertEqual(output.title, "休日のカフェ")
        XCTAssertTrue(output.emotionTags.contains("リラックス"))
        XCTAssertTrue(output.body.contains("カフェでゆっくり過ごした"))
    }

    // MARK: - 出力パース（フォールバック）

    func testParseFallsBackWhenNoLabelsFound() {
        let raw = "今日はなんとなく過ごした。特に何もない一日だった。"
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertEqual(output.title, "今日の日記")
        XCTAssertEqual(output.emotionTags, [])
        XCTAssertTrue(output.body.contains("今日はなんとなく過ごした"))
    }

    func testParseFallsBackOnEmptyInput() {
        let output = ThinkingDiaryStage.parse(rawOutput: "", buddyName: "")
        XCTAssertEqual(output.title, "今日の日記")
        XCTAssertEqual(output.emotionTags, [])
        XCTAssertTrue(output.body.isEmpty)
    }

    func testParseFallsBackOnWhitespaceOnlyInput() {
        let output = ThinkingDiaryStage.parse(rawOutput: "   \n\n   ", buddyName: "")
        XCTAssertEqual(output.title, "今日の日記")
        XCTAssertTrue(output.body.isEmpty)
    }

    func testParseUsesDefaultTitleWhenTitleMissing() {
        let raw = """
        感情: 楽しい
        本文: 今日は楽しかった。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertEqual(output.title, "今日の日記")
        XCTAssertTrue(output.body.contains("今日は楽しかった"))
    }

    func testParseHandlesMissingBodyLabel() {
        let raw = """
        タイトル: テスト日記
        感情: 穏やか
        今日は穏やかに過ごした。読書をした。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertEqual(output.title, "テスト日記")
        XCTAssertTrue(output.body.contains("今日は穏やかに過ごした"))
    }

    // MARK: - 感情タグ正規化

    func testParseFiltersInvalidEmotionTags() {
        let raw = """
        タイトル: テスト
        感情: 不明, なし, 楽しい, none
        本文: テスト本文。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertTrue(output.emotionTags.contains("楽しい"))
        XCTAssertFalse(output.emotionTags.contains("不明"))
        XCTAssertFalse(output.emotionTags.contains("なし"))
        XCTAssertFalse(output.emotionTags.contains("none"))
    }

    func testParseStripsHashFromEmotionTags() {
        let raw = """
        タイトル: テスト
        感情: #楽しい, #嬉しい
        本文: テスト本文。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "")
        XCTAssertTrue(output.emotionTags.contains("楽しい"))
        XCTAssertTrue(output.emotionTags.contains("嬉しい"))
    }

    // MARK: - stripLabelEcho

    func testStripLabelEchoRemovesAllLabelLines() {
        let raw = """
        タイトル: 今日の日記
        感情: 楽しい
        明日: 早起きしたい
        固有名詞: 横浜, ジョイポリス
        今日は横浜に行った。
        楽しかった。
        """
        let stripped = ThinkingDiaryStage.stripLabelEcho(raw)
        XCTAssertFalse(stripped.contains("タイトル"))
        XCTAssertFalse(stripped.contains("感情:"))
        XCTAssertFalse(stripped.contains("明日:"))
        XCTAssertFalse(stripped.contains("固有名詞:"))
        XCTAssertTrue(stripped.contains("今日は横浜に行った"))
    }

    func testStripLabelEchoExtractsBodyAfterLabel() {
        let raw = "本文: ここからが本文です。"
        let stripped = ThinkingDiaryStage.stripLabelEcho(raw)
        XCTAssertEqual(stripped, "ここからが本文です。")
    }

    // MARK: - sanitizeBody

    func testSanitizeBodyDropsBuddyMentions() {
        let input = "今日は横浜に行った。ポチに話してみた。楽しかった。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "ポチ", originalFallback: input)
        XCTAssertTrue(sanitized.contains("今日は横浜に行った"))
        XCTAssertFalse(sanitized.contains("ポチ"))
        XCTAssertTrue(sanitized.contains("楽しかった"))
    }

    func testSanitizeBodyDropsMetaSentences() {
        let input = "今日は横浜に行った。日記に書こうと思う。楽しかった。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertTrue(sanitized.contains("今日は横浜に行った"))
        XCTAssertFalse(sanitized.contains("日記に書こう"))
        XCTAssertTrue(sanitized.contains("楽しかった"))
    }

    func testSanitizeBodyDropsEmotionIsNoneLines() {
        let input = "今日は会議があった。\n感情はない。\n会議は長かった。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertFalse(sanitized.contains("感情はない"))
        XCTAssertTrue(sanitized.contains("今日は会議があった"))
        XCTAssertTrue(sanitized.contains("会議は長かった"))
    }

    func testSanitizeBodyKeepsOriginalWhenOverTrimmed() {
        let input = "日記に書いた。日記を残した。日記をつけた。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertEqual(sanitized, input)
    }

    func testSanitizeBodyDropsGenericBuddyMentions() {
        let input = "今日は横浜に行った。バディに相談した。楽しかった。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertFalse(sanitized.contains("バディ"))
        XCTAssertTrue(sanitized.contains("今日は横浜に行った"))
    }

    func testSanitizeBodyDropsConversationMetaFromShortDiary() {
        let input = "今日は朝から出かけた。相手から、今日はどんな一日だったかという話があった。どこへ行ったのかと尋ねられた。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertTrue(sanitized.contains("今日は朝から出かけた"))
        XCTAssertFalse(sanitized.contains("相手から"))
        XCTAssertFalse(sanitized.contains("話があった"))
        XCTAssertFalse(sanitized.contains("尋ねられた"))
    }

    func testSanitizeBodyStripsInlineBulletMarkers() {
        let input = "横浜に行った。- 中華街で小籠包を食べた。\n・山下公園を散歩した。"
        let sanitized = ThinkingDiaryStage.sanitizeBody(input, buddyName: "", originalFallback: input)
        XCTAssertFalse(sanitized.contains("。- "))
        XCTAssertFalse(sanitized.contains("・山下公園"))
        XCTAssertTrue(sanitized.contains("横浜に行った。中華街で小籠包を食べた"))
        XCTAssertTrue(sanitized.contains("山下公園を散歩した"))
    }

    func testStripListMarkersStripsNumberedMarkers() {
        let input = "今日は買い物をした。\n1. 新宿で服を買った。\n２、渋谷で本を見た。"
        let stripped = ThinkingDiaryStage.stripListMarkers(input)
        XCTAssertFalse(stripped.contains("1. "))
        XCTAssertFalse(stripped.contains("２、"))
        XCTAssertTrue(stripped.contains("新宿で服を買った"))
        XCTAssertTrue(stripped.contains("渋谷で本を見た"))
    }

    // MARK: - ProperNounExtractor

    func testProperNounExtractorExtractsKanjiKatakanaAlnum() {
        let tokens = ProperNounExtractor.extract(from: "今日は横浜のJOYPOLISでナイショ話した")
        XCTAssertTrue(tokens.contains("今日"))
        XCTAssertTrue(tokens.contains("横浜"))
        XCTAssertTrue(tokens.contains("JOYPOLIS"))
        XCTAssertTrue(tokens.contains("ナイショ"))
    }

    func testProperNounExtractorDeduplicates() {
        let tokens = ProperNounExtractor.extract(from: "横浜に行った。横浜は楽しい。")
        XCTAssertEqual(tokens.filter { $0 == "横浜" }.count, 1)
    }

    func testProperNounExtractorMultipleTexts() {
        let tokens = ProperNounExtractor.extract(from: ["横浜に行った", "ジョイポリスで遊んだ", "横浜は楽しい"])
        XCTAssertTrue(tokens.contains("横浜"))
        XCTAssertTrue(tokens.contains("ジョイポリス"))
        XCTAssertEqual(tokens.filter { $0 == "横浜" }.count, 1)
    }

    func testProperNounExtractorIgnoresSingleChar() {
        let tokens = ProperNounExtractor.extract(from: "私はAを見た")
        XCTAssertFalse(tokens.contains("A"))
    }

    // MARK: - パース + sanitizer 統合

    func testParseRemovesBuddyNameFromBody() {
        let raw = """
        タイトル: テスト日記
        感情: 楽しい
        本文: 今日は横浜に行った。ポチに話してみた。楽しかった。
        """
        let output = ThinkingDiaryStage.parse(rawOutput: raw, buddyName: "ポチ")
        XCTAssertFalse(output.body.contains("ポチ"))
        XCTAssertTrue(output.body.contains("今日は横浜に行った"))
    }

    func testParseWithThinkingBlockProducesCleanOutput() {
        let raw = """
        <think>
        会話を分析すると、横浜に行ったことが主要な出来事。
        </think>
        タイトル: 横浜散歩
        感情: 楽しい
        本文: 今日は横浜を散歩した。天気がよくて気持ちよかった。
        """
        let withoutThinking = ThinkingDiaryStage.removeThinkingBlock(raw)
        let output = ThinkingDiaryStage.parse(rawOutput: withoutThinking, buddyName: "")
        XCTAssertEqual(output.title, "横浜散歩")
        XCTAssertTrue(output.emotionTags.contains("楽しい"))
        XCTAssertTrue(output.body.contains("今日は横浜を散歩した"))
        XCTAssertFalse(output.body.contains("think"))
    }

    // MARK: - バディからの一言

    func testBuddyCommentInstructionIncludesCustomTraits() {
        var seed = BuddySeed.appDefault
        seed.customTraits = "関西弁で話す"
        seed.personaStyleCustom = "ちょっとツンデレ"

        let instruction = ThinkingDiaryStage.buildBuddyCommentInstruction(
            buddyName: "モモ",
            buddySeed: seed
        )

        XCTAssertTrue(instruction.contains("最終行の「一言:」だけ"))
        XCTAssertTrue(instruction.contains("関西弁で話す"))
        XCTAssertTrue(instruction.contains("ちょっとツンデレ"))
        XCTAssertTrue(instruction.contains("本文・タイトル・感情タグ"))
    }

    func testOutputWithPersonaAlignedBuddyCommentReplacesStandardCommentWhenKansaiRequested() {
        var seed = BuddySeed.appDefault
        seed.customTraits = "関西弁で話す"

        let output = ThinkingDiaryStage.Output(
            body: "今日は京都へ行った。",
            title: "京都の一日",
            emotionTags: ["楽しかった"],
            buddyComment: "楽しい一日だったね。"
        )

        let adjusted = ThinkingDiaryStage.outputWithPersonaAlignedBuddyComment(
            output,
            buddyName: "モモ",
            buddySeed: seed
        )

        XCTAssertNotEqual(adjusted.buddyComment, output.buddyComment)
        XCTAssertTrue(ThinkingDiaryStage.looksLikeKansaiComment(adjusted.buddyComment))
    }

    func testOutputWithPersonaAlignedBuddyCommentKeepsDialectComment() {
        var seed = BuddySeed.appDefault
        seed.customTraits = "関西弁で話す"

        let output = ThinkingDiaryStage.Output(
            body: "今日は京都へ行った。",
            title: "京都の一日",
            emotionTags: ["楽しかった"],
            buddyComment: "ええ一日やったな。"
        )

        let adjusted = ThinkingDiaryStage.outputWithPersonaAlignedBuddyComment(
            output,
            buddyName: "モモ",
            buddySeed: seed
        )

        XCTAssertEqual(adjusted.buddyComment, "ええ一日やったな。")
    }
}
