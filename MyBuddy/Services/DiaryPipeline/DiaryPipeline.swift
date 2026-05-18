import Foundation

/// 2段階パイプラインによる日記コンパイルの公開エントリポイント。
///
/// Stage 1: MemoExtractionStage — 未処理の会話からメモ（事実の箇条書き）を抽出
/// Stage 2: ThinkingDiaryStage — 蓄積メモから日記を生成（thinking モード）
/// 品質ガード: VerifyStage — 固有名詞カバレッジの判定（LLM不使用）
///
/// 時間予算が限られる場合は `extractMemos(input:)` でメモ抽出のみ実行できる。
struct DiaryPipeline {
    let llmService: any LLMServiceProtocol
    let config: DiaryPipelineConfig

    init(
        llmService: any LLMServiceProtocol,
        config: DiaryPipelineConfig = .default
    ) {
        self.llmService = llmService
        self.config = config
    }

    /// メモ抽出のみ実行する（時間予算が限られる場合用）。
    @MainActor
    func extractMemos(input: DiaryPipelineInput) async throws -> [MemoExtractionStage.MemoItem] {
        guard !input.userMessages.isEmpty else { return [] }

        let stage = MemoExtractionStage(
            llmService: llmService,
            maxTokens: config.memoExtraction.maxTokens,
            samplingProfile: config.memoExtraction.samplingProfile,
            chunkSize: config.memoChunkSize
        )
        return try await stage.run(
            userMessages: input.userMessages,
            conversationTurns: input.conversationTurns,
            language: input.language
        )
    }

    /// フル実行: メモ抽出 + 日記生成 + 品質ガード。
    @MainActor
    func run(input: DiaryPipelineInput) async throws -> DiaryPipelineResult {
        #if DEBUG
        print("[DiaryPipeline] 開始 turnCount=\(input.turnCount)")
        #endif

        // Stage 1: メモ抽出（未処理メッセージがある場合のみ）
        try Task.checkCancellation()
        let newMemos: [MemoExtractionStage.MemoItem]
        if !input.userMessages.isEmpty {
            newMemos = try await extractMemos(input: input)
            #if DEBUG
            print("[DiaryPipeline] メモ抽出完了: \(newMemos.count)件")
            #endif
        } else {
            newMemos = []
        }

        // 全メモ = 既存メモ + 新規抽出メモ
        let allMemoItems: [MemoExtractionStage.MemoItem] = input.existingMemos.map {
            MemoExtractionStage.MemoItem(fact: $0.fact, emotion: $0.emotion)
        } + newMemos

        guard !allMemoItems.isEmpty else {
            #if DEBUG
            print("[DiaryPipeline] メモなし — スキップ")
            #endif
            return DiaryPipelineResult(
                extractedMemos: newMemos,
                body: "",
                title: "今日の日記",
                emotionTags: [],
                tomorrowNote: "",
                nameCoverage: 1.0,
                accepted: true,
                rejectionReason: nil
            )
        }

        // Stage 2: メモ → 日記生成
        try Task.checkCancellation()
        let thinkingStage = ThinkingDiaryStage(
            llmService: llmService,
            maxTokens: config.thinkingStage.maxTokens,
            samplingProfile: config.thinkingStage.samplingProfile
        )
        let stageOutput = try await thinkingStage.run(
            memos: allMemoItems,
            conversationTurns: input.conversationTurns,
            memoryPreference: input.memoryPreference,
            memoryPreferenceCustom: input.memoryPreferenceCustom,
            buddyName: input.buddyName,
            buddySeed: input.buddySeed,
            language: input.language
        )

        // 品質ガード: メモの固有名詞が日記本文にカバーされているか
        try Task.checkCancellation()
        let allMemoTexts = allMemoItems.map(\.fact)
        let extractedNames = ProperNounExtractor.extract(from: allMemoTexts)

        let newMemoFacts = newMemos.map(\.fact)

        let verify = VerifyStage(config: config).run(
            extractedNames: extractedNames,
            body: stageOutput.body,
            previousJournal: input.existingJournal,
            newNotesSinceLastCompile: newMemoFacts
        )

        #if DEBUG
        print("[DiaryPipeline] 終了 accepted=\(verify.accepted) coverage=\(String(format: "%.2f", verify.coverage)) reason=\(verify.rejectionReason ?? "-")")
        #endif

        return DiaryPipelineResult(
            extractedMemos: newMemos,
            body: stageOutput.body,
            title: stageOutput.title,
            emotionTags: stageOutput.emotionTags,
            tomorrowNote: stageOutput.buddyComment,
            nameCoverage: verify.coverage,
            accepted: verify.accepted,
            rejectionReason: verify.rejectionReason
        )
    }
}
