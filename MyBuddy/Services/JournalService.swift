import Foundation

/// 日記コンパイルの公開 API。
///
/// 実装の中身は全て `DiaryPipeline` に委譲する。`JournalService` 自身は
/// 呼び出し元 (ChatViewModel) から受け取ったデータを
/// 純粋な値型 `DiaryPipelineInput` に詰め替える役割だけを持つ。
struct JournalService {
    let llmService: any LLMServiceProtocol
    let config: DiaryPipelineConfig

    init(
        llmService: any LLMServiceProtocol,
        config: DiaryPipelineConfig = .default
    ) {
        self.llmService = llmService
        self.config = config
    }

    /// メモ抽出のみ実行する。時間予算が限られる場合に使用。
    @MainActor
    func extractMemos(
        userMessages: [DiaryPipelineInput.UserMessage],
        conversationTurns: [DiaryPipelineInput.ConversationTurn] = []
    ) async throws -> [MemoExtractionStage.MemoItem] {
        let input = DiaryPipelineInput(
            userMessages: userMessages,
            conversationTurns: conversationTurns,
            existingMemos: [],
            existingJournal: nil,
            memoryPreference: .balanced,
            memoryPreferenceCustom: "",
            buddyName: "",
            buddySeed: .appDefault,
            turnCount: userMessages.count,
            language: AppLanguageMode.currentResolved
        )
        let pipeline = DiaryPipeline(llmService: llmService, config: config)
        return try await pipeline.extractMemos(input: input)
    }

    /// フル実行: メモ抽出 + 日記生成。
    @MainActor
    func compile(
        userMessages: [DiaryPipelineInput.UserMessage],
        conversationTurns: [DiaryPipelineInput.ConversationTurn] = [],
        existingMemos: [DiaryPipelineInput.MemoSnapshot],
        turnCount: Int,
        existingJournal: JournalEntry?,
        memoryPreference: MemoryPreference,
        memoryPreferenceCustom: String = "",
        buddyName: String = "",
        buddySeed: BuddySeed = .appDefault,
        language: ResolvedAppLanguage = .japanese
    ) async throws -> DiaryPipelineResult {
        let input = DiaryPipelineInput(
            userMessages: userMessages,
            conversationTurns: conversationTurns,
            existingMemos: existingMemos,
            existingJournal: existingJournal.map { entry in
                DiaryPipelineInput.ExistingJournalSnapshot(
                    title: entry.title,
                    body: entry.fullDiaryText,
                    emotionTags: entry.emotionTags,
                    tomorrowNote: entry.tomorrowNote,
                    nameCoverage: entry.nameCoverage
                )
            },
            memoryPreference: memoryPreference,
            memoryPreferenceCustom: memoryPreferenceCustom,
            buddyName: buddyName,
            buddySeed: buddySeed,
            turnCount: turnCount,
            language: language
        )

        let pipeline = DiaryPipeline(llmService: llmService, config: config)
        return try await pipeline.run(input: input)
    }

    /// 既存日記がない状態で compile に失敗したときの最低限フォールバック。
    static func minimalNewJournal(
        userMessages: [DiaryPipelineInput.UserMessage]
    ) -> DiaryPipelineResult {
        let body: String
        if !userMessages.isEmpty {
            let fragments = userMessages
                .prefix(4)
                .map { UserInputSanitizer.sanitize($0.text, policy: .diaryPipelineText) }
                .filter { !$0.isEmpty }
            body = fallbackDiaryBody(from: fragments)
        } else {
            body = "今日は出来事を少しずつ思い返しながら、一日を振り返った。だけど、今日は特に日記に書き残すようなことはなかった。"
        }

        return DiaryPipelineResult(
            extractedMemos: [],
            body: body,
            title: "今日の日記",
            emotionTags: [],
            tomorrowNote: "",
            nameCoverage: 0.0,
            accepted: true,
            rejectionReason: nil
        )
    }

    private static func fallbackDiaryBody(from fragments: [String]) -> String {
        guard !fragments.isEmpty else {
            return "今日は出来事を少しずつ思い返しながら、一日を振り返った。だけど、今日は特に日記に書き残すようなことはなかった。"
        }

        let connectors = ["そのあと、", "また、", "それから、"]

        let sentences = fragments.enumerated().map { index, fragment in
            var sentence = fragment
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            if sentence.isEmpty {
                return ""
            }

            sentence = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "。．！？"))

            if index == 0 {
                if !(sentence.hasPrefix("今日は") || sentence.hasPrefix("朝") || sentence.hasPrefix("昼") || sentence.hasPrefix("夜") || sentence.hasPrefix("深夜")) {
                    sentence = "今日は\(sentence)"
                }
            } else if !(sentence.hasPrefix("朝") || sentence.hasPrefix("昼") || sentence.hasPrefix("夜") || sentence.hasPrefix("そのあと、") || sentence.hasPrefix("また、") || sentence.hasPrefix("それから、")) {
                sentence = connectors[(index - 1) % connectors.count] + sentence
            }

            return sentence + "。"
        }
        .filter { !$0.isEmpty }

        return sentences.joined()
    }
}

/// UI プレビュー用の互換型。
struct JournalGenerationResult {
    let title: String
    let body: String
    let summary: String
    let emotionTags: [String]
    let tomorrowNote: String
    let imageDataList: [Data]?
}
