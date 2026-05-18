import Foundation

/// 日記パイプラインで使用する全定数を一元管理する設定コンテナ。
///
/// 2段階パイプライン（MemoExtractionStage + ThinkingDiaryStage + VerifyStage）で使用する。
struct DiaryPipelineConfig: Sendable {
    // MARK: - 発火条件

    /// コンパイル発火: 最低ターン数ガード。この値未満ではコンパイルしない。
    let minTurnsToCompile: Int

    // MARK: - 品質ガード

    /// 既存日記の nameCoverage に対して、新本文が許容される最低比率。
    let qualityGuardRatio: Double
    /// fixture テストで許容される固有名詞カバレッジの下限 (参考値)
    let nameCoverageThreshold: Double
    /// fixture テストで許容される事実カバレッジの下限
    let factCoverageThreshold: Double

    // MARK: - リトライ

    /// コンパイル失敗時の自動リトライ上限回数
    let maxRetries: Int

    // MARK: - Stage 設定

    struct StageSettings: Sendable {
        let maxTokens: Int
        let samplingProfile: LLMSamplingProfile
    }

    /// Stage 1: メモ抽出
    let memoExtraction: StageSettings
    /// メモ抽出時のチャンクサイズ（この件数ごとにLLMを呼ぶ）
    let memoChunkSize: Int

    /// Stage 2: メモ→日記生成（thinking モード）
    let thinkingStage: StageSettings

    // MARK: - デフォルト値

    nonisolated static let `default` = DiaryPipelineConfig(
        minTurnsToCompile: 1,
        qualityGuardRatio: 0.9,
        nameCoverageThreshold: 0.8,
        factCoverageThreshold: 0.6,
        maxRetries: 1,
        memoExtraction: StageSettings(maxTokens: 192, samplingProfile: .extraction),
        memoChunkSize: 5,
        // 12 メモ超の長い会話でも最後まで書き切れるマージン。
        thinkingStage: StageSettings(maxTokens: 640, samplingProfile: .journal)
    )
}

// MARK: - ターン数ガード

extension DiaryPipelineConfig {
    /// 指定ターン数がコンパイル可能な最低ターン数を満たしているかを判定する。
    func canCompile(turnCount: Int) -> Bool {
        turnCount >= minTurnsToCompile
    }
}
