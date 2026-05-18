import Foundation
@testable import MyBuddy

/// 日記品質を数値で評価する純粋関数群。
///
/// `DiaryQualityTests` が各 fixture に対して `DiaryPipeline.run(input:)` を回し、
/// その結果 (`DiaryPipelineResult`) と fixture の期待値を突き合わせる際に使う。
///
/// 指標の定義:
/// - **nameCoverage**: `expectedProperNouns` のうち本文に含まれる割合
/// - **factCoverage**: `expectedFacts` のうち本文に含まれる割合
/// - **emotionMatchCount**: `expectedEmotionCategories` と `result.emotionTags` の (同義語も含む) 交差数
/// - **lengthOK**: 本文長が `lengthBounds` の範囲内か
///
/// 同義語マッピングは `emotionCategoryMatches` で緩めに判定する (例: 「嬉しい」カテゴリに
/// 「嬉しい」「楽しい」「ワクワク」「喜び」などを含める)。
enum DiaryQualityMetrics {

    struct Report {
        let nameCoverage: Double
        let factCoverage: Double
        let emotionMatchCount: Int
        let bodyLength: Int
        let lengthOK: Bool
        let missingProperNouns: [String]
        let missingFacts: [String]
        let matchedEmotionCategories: [String]

        /// fixture の thresholds を満たしているかの総合判定
        func passes(thresholds: DiaryQualityFixture.Thresholds) -> Bool {
            return nameCoverage >= thresholds.nameCoverage
                && factCoverage >= thresholds.factCoverage
                && emotionMatchCount >= thresholds.minEmotionMatches
                && lengthOK
        }
    }

    static func evaluate(
        result: DiaryPipelineResult,
        fixture: DiaryQualityFixture
    ) -> Report {
        let body = result.body

        // 1. 固有名詞カバレッジ
        let missingNouns = fixture.expectedProperNouns.filter { !body.contains($0) }
        let nameCoverage: Double
        if fixture.expectedProperNouns.isEmpty {
            nameCoverage = 1.0
        } else {
            let hit = fixture.expectedProperNouns.count - missingNouns.count
            nameCoverage = Double(hit) / Double(fixture.expectedProperNouns.count)
        }

        // 2. 事実カバレッジ (期待文字列の substring 一致)
        let missingFacts = fixture.expectedFacts.filter { !body.contains($0) }
        let factCoverage: Double
        if fixture.expectedFacts.isEmpty {
            factCoverage = 1.0
        } else {
            let hit = fixture.expectedFacts.count - missingFacts.count
            factCoverage = Double(hit) / Double(fixture.expectedFacts.count)
        }

        // 3. 感情カテゴリ一致
        let matchedCategories = fixture.expectedEmotionCategories.filter { category in
            result.emotionTags.contains { tag in
                emotionCategoryMatches(tag: tag, category: category)
            }
        }

        // 4. 本文長
        let len = body.count
        let lengthOK = len >= fixture.lengthBounds.minCharacters
            && len <= fixture.lengthBounds.maxCharacters

        return Report(
            nameCoverage: nameCoverage,
            factCoverage: factCoverage,
            emotionMatchCount: matchedCategories.count,
            bodyLength: len,
            lengthOK: lengthOK,
            missingProperNouns: missingNouns,
            missingFacts: missingFacts,
            matchedEmotionCategories: matchedCategories
        )
    }

    /// 感情タグが指定のカテゴリに属するかを緩めに判定する。
    ///
    /// 完全一致だけではなく、よく出てくる同義語も許容する。
    /// 厳密な感情分類は目的ではなく、LLM がとんちんかんなタグ (例: 「楽しかった」会話に「不安」)
    /// を付けていないかを弾くのが目的。
    static func emotionCategoryMatches(tag: String, category: String) -> Bool {
        if tag == category { return true }
        guard let synonyms = emotionSynonyms[category] else { return false }
        return synonyms.contains(tag)
    }

    /// カテゴリごとの同義語辞書。
    /// 左辺が「期待カテゴリ」、右辺がその代表と近い感情タグ群。
    ///
    /// 同じタグが複数カテゴリに属することを許容する (例: 「満足」は 「嬉しい」にも「幸せ」にも
    /// 属する)。これにより LLM が 1 つのタグしか出さなかった場合でも、fixture 側で期待する
    /// 複数カテゴリを正しく拾える。
    static let emotionSynonyms: [String: Set<String>] = [
        "嬉しい": [
            "嬉しい", "嬉しかった", "うれしい", "うれしかった",
            "喜び", "よろこび", "ハッピー", "幸せ", "ほっこり",
            "満足", "達成感"
        ],
        "楽しい": [
            "楽しい", "楽しかった", "たのしい", "たのしかった",
            "わくわく", "ワクワク", "満喫", "はしゃぐ", "はしゃいだ",
            "好奇心", "ワクワク感", "夢中"
        ],
        "穏やか": [
            "穏やか", "おだやか", "リラックス", "のんびり", "癒し",
            "落ち着き", "ほっとした", "満足", "ゆったり"
        ],
        "感動": [
            "感動", "じーん", "感激", "胸熱", "心を動かされた", "じーんとした"
        ],
        "幸せ": [
            "幸せ", "しあわせ", "満たされた", "充実", "充実感", "満足",
            "達成感", "満ち足りた"
        ],
        "疲れ": [
            "疲れ", "疲労", "疲れた", "くたくた", "へとへと", "ぐったり",
            "ヘロヘロ", "しんどい"
        ],
        "安心": [
            "安心", "安心した", "ほっとした", "ほっと", "一安心", "安堵", "ほっ"
        ],
        "集中": [
            "集中", "真剣", "没頭", "意欲", "やる気", "前向き",
            "達成感", "やりきった", "完遂"
        ],
        "反省": [
            "反省", "後悔", "もやもや", "悔しい"
        ],
        "清々しい": [
            "清々しい", "すがすがしい", "さわやか", "爽やか",
            "スッキリ", "すっきり", "スッキリした", "すっきりした",
            "爽快", "爽快感", "リフレッシュ"
        ]
    ]
}
