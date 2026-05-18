import Foundation

/// Stage 5: Verify (LLM 呼び出し不要)
///
/// Stage 1 で抽出された固有名詞リストと Stage 3 本文を照合して、
/// 固有名詞カバレッジ率を計算し、採用可否を判定する。
///
/// 採用可否のルール:
/// - 既存日記 (previousJournal) がない、または previousJournal.nameCoverage == nil: 無条件採用
/// - 新カバレッジ >= 既存カバレッジ × config.qualityGuardRatio: 採用
/// - 新カバレッジ < 既存カバレッジ × config.qualityGuardRatio: 拒否
///   ただし「新規メモ追加時の例外」として、`newNotesSinceLastCompile` のうち少なくとも 1 件の
///   固有名詞が新本文に含まれていれば採用する (メモ追加で再発火したのにそれが反映されないのは本末転倒)
struct VerifyStage {
    let config: DiaryPipelineConfig

    struct Output {
        let coverage: Double
        let accepted: Bool
        let rejectionReason: String?
    }

    func run(
        extractedNames: [String],
        body: String,
        previousJournal: DiaryPipelineInput.ExistingJournalSnapshot?,
        newNotesSinceLastCompile: [String]
    ) -> Output {
        let coverage = Self.calculateCoverage(names: extractedNames, body: body)

        guard let prev = previousJournal, let prevCoverage = prev.nameCoverage else {
            // 初回、または nameCoverage 未保存の既存日記: 無条件採用
            return Output(coverage: coverage, accepted: true, rejectionReason: nil)
        }

        let threshold = prevCoverage * config.qualityGuardRatio
        if coverage >= threshold {
            return Output(coverage: coverage, accepted: true, rejectionReason: nil)
        }

        // 品質ガード拒否ケース。ただし新規メモの例外判定を行う。
        if Self.anyNewNoteIncluded(in: body, newNotes: newNotesSinceLastCompile) {
            return Output(
                coverage: coverage,
                accepted: true,
                rejectionReason: nil
            )
        }

        let reason = String(
            format: "品質ガード拒否: 新 coverage=%.2f < 既存 coverage=%.2f × %.2f",
            coverage,
            prevCoverage,
            config.qualityGuardRatio
        )
        return Output(coverage: coverage, accepted: false, rejectionReason: reason)
    }

    // MARK: - Helpers

    /// 本文に含まれる固有名詞の比率を計算する。
    /// `names` が空の場合は 1.0 (カバレッジ判定を無効化) を返す。
    static func calculateCoverage(names: [String], body: String) -> Double {
        let normalizedNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedNames.isEmpty else { return 1.0 }

        let hit = normalizedNames.filter { body.contains($0) }.count
        return Double(hit) / Double(normalizedNames.count)
    }

    /// 新規メモのうち、固有名詞トークンが本文に少なくとも 1 つ含まれているかを判定する。
    /// 判定は素朴な部分文字列照合で行う (形態素解析は使わない)。
    private static func anyNewNoteIncluded(in body: String, newNotes: [String]) -> Bool {
        for note in newNotes {
            let tokens = ProperNounExtractor.extract(from: note)
            if tokens.isEmpty {
                // 固有名詞が取れない場合はメモ全体の substring 一部で判定
                if !note.isEmpty && body.contains(note) { return true }
                continue
            }
            for token in tokens where body.contains(token) {
                return true
            }
        }
        return false
    }
}
