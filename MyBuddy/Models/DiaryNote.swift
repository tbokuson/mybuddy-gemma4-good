import Foundation
import SwiftData

/// 日記の素材となるメモエントリ
/// チャット応答生成と同じLLM推論で抽出され、3件以上たまったタイミングで日記本体（JournalEntry）にコンパイルされる
@Model
final class DiaryNote {
    var id: UUID
    /// 日記の日付（DayBoundary.appToday()基準）
    var date: Date
    /// 事実: ユーザーが語った具体的な出来事を1文
    var fact: String
    /// 感情: ユーザーがそれをどう感じたか。読み取れない場合は「不明」
    var emotion: String
    var createdAt: Date
    /// 元のChatMessage.id（重複防止用）
    var sourceMessageId: UUID?
    /// 日記本体にコンパイル済みかどうか
    var consumedInJournal: Bool

    init(
        date: Date,
        fact: String,
        emotion: String,
        sourceMessageId: UUID? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.fact = fact
        self.emotion = emotion
        self.createdAt = Date()
        self.sourceMessageId = sourceMessageId
        self.consumedInJournal = false
    }
}
