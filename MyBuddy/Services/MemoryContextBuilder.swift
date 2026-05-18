import Foundation
import SwiftData

/// 過去のJournalEntryから記憶コンテキストを構築し、
/// LLMのシステムプロンプトに注入するためのユーティリティ。
struct MemoryContextBuilder {

    /// 過去10日分のJournalEntryから短期記憶コンテキストを構築。
    /// 今日のエントリは除外（現在の会話そのものなので）。
    /// 各エントリを1行に圧縮。
    static func buildMemoryContext(modelContext: ModelContext) -> String {
        let entries = fetchRecentEntries(modelContext: modelContext, days: 10)
        guard !entries.isEmpty else { return "" }

        var lines: [String] = ["【最近の記憶（ユーザーとの過去の会話から）】"]
        for entry in entries {
            lines.append(formatEntry(entry))
        }
        return lines.joined(separator: "\n")
    }

    /// 直近のJournalEntryのtomorrowNoteを取得（今日のエントリは除外）。
    /// 新しいセッション開始時の挨拶で使用。
    static func getMostRecentTomorrowNote(modelContext: ModelContext) -> String? {
        // journal.dateはDayBoundary.appToday()（midnight）で保存されるため、同じ基準で比較
        let today = DayBoundary.appToday()

        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> {
                $0.date < today
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let entry = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        let note = entry.tomorrowNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
    }

    // MARK: - Private

    private static func fetchRecentEntries(
        modelContext: ModelContext,
        days: Int
    ) -> [JournalEntry] {
        let calendar = Calendar.current
        // journal.dateはDayBoundary.appToday()（midnight）で保存されるため、同じ基準で比較
        let today = DayBoundary.appToday()
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: today) else {
            return []
        }

        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> {
                $0.date >= cutoffDate && $0.date < today
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func formatEntry(_ entry: JournalEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        let dateStr = formatter.string(from: entry.date)

        let title = String(entry.title.prefix(20))
        let summary = String(entry.summaryText.prefix(40))
        let emotions = entry.normalizedEmotionTags.prefix(4).joined(separator: "・")

        var line = "\(dateStr): \(title)"
        if !summary.isEmpty {
            line += "(\(summary))"
        }
        if !emotions.isEmpty {
            line += " [\(emotions)]"
        }
        return line
    }
}
