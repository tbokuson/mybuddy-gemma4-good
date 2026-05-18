import Foundation

/// 日替わりタイミングを朝4時にする。
/// 深夜0〜3:59は「前日」扱い。
/// 理由: 0時を過ぎてもその日のことを書きたいため。
enum DayBoundary {

    /// 朝4時のオフセット（時間）
    static let boundaryHour = 4

    /// 指定日の「アプリ上の1日の開始時刻」を返す。
    /// 例: 2026-04-05 04:00:00
    /// 0:00〜3:59は前日として扱うため、その場合は前日の04:00を返す。
    static func startOfAppDay(for date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let baseDate = hour < boundaryHour
            ? calendar.date(byAdding: .day, value: -1, to: date)!
            : date
        let midnight = calendar.startOfDay(for: baseDate)
        return calendar.date(byAdding: .hour, value: boundaryHour, to: midnight)!
    }

    /// 指定日の「アプリ上の1日の終了時刻」（= 翌日の開始時刻）を返す。
    static func endOfAppDay(for date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: startOfAppDay(for: date))!
    }

    /// 2つの日付が同じ「アプリ上の日」かどうか。
    static func isSameAppDay(_ date1: Date, _ date2: Date) -> Bool {
        startOfAppDay(for: date1) == startOfAppDay(for: date2)
    }

    /// 指定日が「アプリ上の今日」かどうか。
    static func isAppToday(_ date: Date) -> Bool {
        isSameAppDay(date, Date())
    }

    /// 「アプリ上の今日」の日付を返す（0:00ベース、表示用）。
    /// 例: 1/1の午前2時 → 12/31の0:00を返す。
    /// 日記やセッションの日付スタンプに使う。
    static func appToday(for date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let baseDate = hour < boundaryHour
            ? calendar.date(byAdding: .day, value: -1, to: date)!
            : date
        return calendar.startOfDay(for: baseDate)
    }
}
