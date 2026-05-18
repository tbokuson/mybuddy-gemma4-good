import Foundation
@testable import MyBuddy

/// E2E 品質テスト用のフィクスチャ形式。
///
/// `MyBuddyTests/Fixtures/conversations/*.json` から読み込み、
/// `DiaryPipeline.run(input:)` を呼び出した結果を `DiaryQualityMetrics` で評価する。
///
/// フィクスチャは「会話」と「期待される品質ライン」のセットで構成される:
/// - `messages`: user 発話 (時系列、role は常に user を想定)
/// - `notes`: 補助的なノート情報 (fact + emotion)。thinking モードでは未使用
/// - `expectedProperNouns`: 本文に含まれていてほしい固有名詞 (coverage >= fixture.thresholds.nameCoverage)
/// - `expectedFacts`: 本文に含まれていてほしい事実の部分文字列リスト (coverage >= fixture.thresholds.factCoverage)
/// - `expectedEmotionCategories`: 感情タグが属すべき感情カテゴリ (少なくとも 1 つは当てはまる)
/// - `lengthBounds`: 本文長の下限・上限 (文字数)
/// - `thresholds`: 指標の合格ライン
struct DiaryQualityFixture: Codable {
    let id: String
    let description: String
    let memoryPreference: String
    let buddyName: String
    let messages: [FixtureMessage]
    let notes: [FixtureNote]
    let expectedProperNouns: [String]
    let expectedFacts: [String]
    let expectedEmotionCategories: [String]
    let lengthBounds: LengthBounds
    let thresholds: Thresholds

    struct FixtureMessage: Codable {
        let text: String
        /// 会話開始からの経過秒数 (timestamp を組み立てるため)
        let offsetSeconds: TimeInterval
    }

    struct FixtureNote: Codable {
        let fact: String
        let emotion: String
        /// 会話開始からの経過秒数
        let offsetSeconds: TimeInterval
    }

    struct LengthBounds: Codable {
        let minCharacters: Int
        let maxCharacters: Int
    }

    struct Thresholds: Codable {
        let nameCoverage: Double
        let factCoverage: Double
        /// 感情カテゴリ一致数 (少なくとも何個の期待カテゴリと一致すればよいか)
        let minEmotionMatches: Int
    }
}

extension DiaryQualityFixture {
    /// フィクスチャから `DiaryPipelineInput` を組み立てる。
    /// `baseDate` は会話開始時刻 (各メッセージ・ノートの offsetSeconds の基準)。
    func makePipelineInput(baseDate: Date = Date()) -> DiaryPipelineInput {
        let userMessages = messages.map { msg in
            DiaryPipelineInput.UserMessage(
                id: UUID(),
                text: msg.text,
                timestamp: baseDate.addingTimeInterval(msg.offsetSeconds)
            )
        }
        let memoSnapshots = notes.map { note in
            DiaryPipelineInput.MemoSnapshot(
                fact: note.fact,
                emotion: note.emotion,
                createdAt: baseDate.addingTimeInterval(note.offsetSeconds)
            )
        }
        let memoryPref = MemoryPreference(rawValue: memoryPreference) ?? .balanced
        return DiaryPipelineInput(
            userMessages: userMessages,
            conversationTurns: userMessages.map {
                DiaryPipelineInput.ConversationTurn(id: $0.id, role: .user, text: $0.text, timestamp: $0.timestamp)
            },
            existingMemos: memoSnapshots,
            existingJournal: nil,
            memoryPreference: memoryPref,
            memoryPreferenceCustom: "",
            buddyName: buddyName,
            buddySeed: .appDefault,
            turnCount: userMessages.count
        )
    }

    /// テストバンドルの `Fixtures/conversations/<name>.json` を読み込む。
    static func load(named name: String) throws -> DiaryQualityFixture {
        let bundle = Bundle(for: DiaryQualityFixtureLoader.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/conversations")
            ?? bundle.url(forResource: name, withExtension: "json")
        else {
            throw NSError(
                domain: "DiaryQualityFixture",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "fixture '\(name).json' がテストバンドルに含まれていません"]
            )
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(DiaryQualityFixture.self, from: data)
    }
}

/// `Bundle(for:)` に渡すためのダミークラス (fixture を tests バンドルから解決する)
final class DiaryQualityFixtureLoader {}
