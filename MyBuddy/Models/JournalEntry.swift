import Foundation
import SwiftData

@Model
final class JournalEntry {
    var id: UUID
    var date: Date
    var title: String
    var summaryText: String
    var fullDiaryText: String
    var emotionTags: [String]
    var tomorrowNote: String
    var createdAt: Date
    @Attribute(.externalStorage) var imageDataList: [Data]?
    /// Stage 5 (Verify) が計算した、採用された本文の固有名詞カバレッジ率 (0.0 〜 1.0)
    /// 既存日記のないレコード、または旧パイプラインで生成されたレコードでは `nil` のまま
    /// 次回コンパイルで nil の場合は無条件採用、値があれば 0.9 倍以上を維持する品質ガードが発動する
    var nameCoverage: Double?

    init(
        date: Date = Date(),
        title: String,
        summaryText: String,
        fullDiaryText: String,
        emotionTags: [String] = [],
        tomorrowNote: String = "",
        imageDataList: [Data]? = nil,
        nameCoverage: Double? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.title = title
        self.summaryText = summaryText
        self.fullDiaryText = fullDiaryText
        self.emotionTags = emotionTags
        self.tomorrowNote = tomorrowNote
        self.createdAt = Date()
        self.imageDataList = imageDataList
        self.nameCoverage = nameCoverage
    }

    var normalizedEmotionTags: [String] {
        Self.normalizeEmotionTags(emotionTags)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        if AppLanguageMode.currentResolved == .english {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMM d (E)"
        } else {
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日（E）"
        }
        return formatter.string(from: date)
    }

    static func normalizeEmotionTags(_ tags: [String], maxCount: Int = 4) -> [String] {
        var normalized: [String] = []

        for tag in tags {
            let trimmed = tag
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()

            guard !trimmed.isEmpty else { continue }
            guard trimmed != "不明" else { continue }
            guard !trimmed.contains("不明") else { continue }
            guard trimmed != "なし" && trimmed != "無し" else { continue }
            guard lowered != "none" && lowered != "n/a" && lowered != "na" else { continue }
            guard !normalized.contains(trimmed) else { continue }
            normalized.append(trimmed)
        }

        return Array(normalized.prefix(maxCount))
    }
}
