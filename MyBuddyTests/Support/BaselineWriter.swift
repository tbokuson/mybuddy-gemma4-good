import Foundation
@testable import MyBuddy

/// ベースライン計測 (`MYBUDDY_WRITE_BASELINE=1`) 時に、`DiaryQualityTests` の各 fixture 実行結果を
/// `MyBuddyTests/Fixtures/baselines/new-pipeline.json` に追記するライター。
///
/// 通常の CI / 手元テストでは起動しない (環境変数でガードする側の責務)。
/// 書き出し先は `#file` を基点にソースツリーの絶対パスを解決する。
final class BaselineWriter: @unchecked Sendable {
    static let shared = BaselineWriter()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "mybuddy.baseline-writer")
    private var entries: [String: Entry] = [:]

    struct Entry: Codable {
        let fixtureId: String
        let title: String
        let body: String
        let emotionTags: [String]
        let tomorrowNote: String
        let accepted: Bool
        let nameCoverage: Double
        let metrics: Metrics
        let recordedAt: String
    }

    struct Metrics: Codable {
        let nameCoverage: Double
        let factCoverage: Double
        let emotionMatchCount: Int
        let bodyLength: Int
        let lengthOK: Bool
        let missingProperNouns: [String]
        let missingFacts: [String]
        let matchedEmotionCategories: [String]
    }

    private init() {
        // #file 経由でソースツリー上のパスを解決する。
        // 例: .../MyBuddyTests/Support/BaselineWriter.swift → .../MyBuddyTests/Fixtures/baselines/
        let thisFile = URL(fileURLWithPath: #file)
        let supportDir = thisFile.deletingLastPathComponent()        // MyBuddyTests/Support
        let testsRoot = supportDir.deletingLastPathComponent()       // MyBuddyTests
        let baselineDir = testsRoot
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("baselines", isDirectory: true)
        try? FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        self.fileURL = baselineDir.appendingPathComponent("new-pipeline.json", isDirectory: false)
    }

    func record(
        fixtureId: String,
        result: DiaryPipelineResult,
        report: DiaryQualityMetrics.Report
    ) {
        print("[BaselineWriter] fixture=\(fixtureId) path=\(fileURL.path)")
        queue.sync {
            let formatter = ISO8601DateFormatter()
            let entry = Entry(
                fixtureId: fixtureId,
                title: result.title,
                body: result.body,
                emotionTags: result.emotionTags,
                tomorrowNote: result.tomorrowNote,
                accepted: result.accepted,
                nameCoverage: result.nameCoverage,
                metrics: Metrics(
                    nameCoverage: report.nameCoverage,
                    factCoverage: report.factCoverage,
                    emotionMatchCount: report.emotionMatchCount,
                    bodyLength: report.bodyLength,
                    lengthOK: report.lengthOK,
                    missingProperNouns: report.missingProperNouns,
                    missingFacts: report.missingFacts,
                    matchedEmotionCategories: report.matchedEmotionCategories
                ),
                recordedAt: formatter.string(from: Date())
            )
            entries[fixtureId] = entry
            persist()
        }
    }

    private func persist() {
        // エントリをマージするため、既存ファイルを読み込んでから上書きする。
        var merged: [String: Entry] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONDecoder().decode([String: Entry].self, from: data) {
            merged = existing
        }
        for (k, v) in entries {
            merged[k] = v
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(merged) {
            try? data.write(to: fileURL)
        }
    }
}
