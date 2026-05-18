import Foundation

/// `DiaryPipeline.run(input:)` の出力。
///
/// メモ抽出結果と日記本文 / メタ情報 / 品質ガードの採用可否を返す。
/// `accepted == false` の場合、呼び出し元 (ChatViewModel) は既存 `JournalEntry` を変更してはならない。
struct DiaryPipelineResult: Sendable {
    /// Stage 1 で抽出されたメモ（呼び出し元で DiaryNote として保存する）
    let extractedMemos: [MemoExtractionStage.MemoItem]

    /// Stage 2 で生成された本文
    let body: String
    /// Stage 2 で生成されたタイトル
    let title: String
    /// Stage 2 で生成された感情タグ
    let emotionTags: [String]
    /// Stage 2 で生成された明日メモ（現在未使用）
    let tomorrowNote: String
    /// 品質ガードで計算された固有名詞カバレッジ率 (0.0 〜 1.0)
    let nameCoverage: Double
    /// 品質ガードの採用可否。false の場合は既存日記を維持する。
    let accepted: Bool
    /// `accepted == false` の場合、拒否理由を人間可読で格納する (ログ / デバッグ用)。
    let rejectionReason: String?

    /// メモ抽出のみ完了し、日記生成は未実行の場合の結果を作る。
    static func memoOnly(_ memos: [MemoExtractionStage.MemoItem]) -> DiaryPipelineResult {
        DiaryPipelineResult(
            extractedMemos: memos,
            body: "",
            title: "",
            emotionTags: [],
            tomorrowNote: "",
            nameCoverage: 0,
            accepted: false,
            rejectionReason: "メモ抽出のみ（日記生成は時間切れ）"
        )
    }
}
