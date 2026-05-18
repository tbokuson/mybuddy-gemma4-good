import Foundation

/// `DiaryPipeline.run(input:)` の入力。
///
/// 日記コンパイルに必要な素材を純粋な値型で集約する。
/// SwiftData の `@Model` (DiaryNote, JournalEntry) は `Sendable` でないため、
/// 呼び出し元 (ChatViewModel など) が必要フィールドだけを抽出してこの struct に詰める。
struct DiaryPipelineInput: Sendable {
    /// 未処理の会話原文 (user 発話のみ、時系列順)。メモ抽出の入力。
    let userMessages: [UserMessage]

    /// 未処理区間の会話ターン。assistant 側の質問は文脈理解にだけ使い、
    /// 日記本文の事実・感情の根拠にはしない。
    let conversationTurns: [ConversationTurn]

    /// 既存のメモ (当日分全件、時系列順)。日記生成の入力。
    let existingMemos: [MemoSnapshot]

    /// 既存の日記スナップショット (VerifyStage の品質ガード用)。新規生成時は nil。
    let existingJournal: ExistingJournalSnapshot?

    /// ユーザーの日記スタイル設定 (enum ベース)
    let memoryPreference: MemoryPreference

    /// ユーザーのカスタム日記スタイル (自由記述)。空文字の場合は enum のみを使用する。
    let memoryPreferenceCustom: String

    /// バディの表示名 (本文 sanitizer でバディ言及を除去する際に使用)
    let buddyName: String

    /// バディの seed (日記コメント生成に使用)
    let buddySeed: BuddySeed

    /// 当日のチャットターン数 (user 発話数)。
    let turnCount: Int

    /// 日記パイプラインの出力言語。
    let language: ResolvedAppLanguage

    init(
        userMessages: [UserMessage],
        conversationTurns: [ConversationTurn],
        existingMemos: [MemoSnapshot],
        existingJournal: ExistingJournalSnapshot?,
        memoryPreference: MemoryPreference,
        memoryPreferenceCustom: String,
        buddyName: String,
        buddySeed: BuddySeed,
        turnCount: Int,
        language: ResolvedAppLanguage = .japanese
    ) {
        self.userMessages = userMessages
        self.conversationTurns = conversationTurns
        self.existingMemos = existingMemos
        self.existingJournal = existingJournal
        self.memoryPreference = memoryPreference
        self.memoryPreferenceCustom = memoryPreferenceCustom
        self.buddyName = buddyName
        self.buddySeed = buddySeed
        self.turnCount = turnCount
        self.language = language
    }

    /// 会話原文の 1 発話分
    struct UserMessage: Sendable {
        let id: UUID
        let text: String
        let timestamp: Date
    }

    struct ConversationTurn: Sendable {
        enum Role: String, Sendable {
            case user
            case buddy
        }

        let id: UUID
        let role: Role
        let text: String
        let timestamp: Date
    }

    /// DiaryNote のスナップショット（メモ抽出済みの事実）
    struct MemoSnapshot: Sendable {
        let fact: String
        let emotion: String
        let createdAt: Date
    }

    /// 既存 JournalEntry のスナップショット
    struct ExistingJournalSnapshot: Sendable {
        let title: String
        let body: String
        let emotionTags: [String]
        let tomorrowNote: String
        let nameCoverage: Double?
    }
}
