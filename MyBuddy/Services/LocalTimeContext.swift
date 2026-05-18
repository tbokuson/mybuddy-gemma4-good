import Foundation

struct LocalTimeContext: Sendable {
    let timeZone: TimeZone
    let now: Date
    let dateString: String
    let timeString: String
    let weekdayName: String
    let dayTypeString: String
    let timeSlot: String
    let chatTimeHint: String
    /// 時間帯に応じた短い挨拶語（おはよう/こんにちは/こんばんは/夜遅いね）
    let greetingWord: String

    static func make(
        now: Date = Date(),
        timeZoneIdentifier: String?
    ) -> LocalTimeContext {
        let timeZone = resolveTimeZone(identifier: timeZoneIdentifier)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let weekdayNames = ["", "日", "月", "火", "水", "木", "金", "土"]
        let isWeekend = weekday == 1 || weekday == 7

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateTime = formatter.string(from: now)
        let dateParts = dateTime.split(separator: " ", maxSplits: 1).map(String.init)
        let dateString = dateParts.first ?? ""
        let timeString = dateParts.count > 1 ? dateParts[1] : ""

        let timeSlot: String
        let timeHint: String
        let greeting: String
        switch hour {
        case 0..<5:
            timeSlot = "深夜"
            timeHint = "深夜なので、今日一日ここまでで実際に何があったかを聞く。現在の行動だけでなく、その日の出来事全体を優先する"
            greeting = "遅くまでお疲れさま"
        case 5..<11:
            timeSlot = "朝"
            timeHint = "朝なので、起きてから今までや昨夜〜今朝に何があったかを聞く。予定よりも、ここまでの出来事を優先する"
            greeting = "おはよう"
        case 11..<17:
            timeSlot = "昼〜午後"
            timeHint = "昼〜午後なので、午前中から今までに何があったかを聞く。現在の行動だけでなく、今日ここまでの出来事を優先する"
            greeting = "こんにちは"
        default:
            timeSlot = "夜"
            timeHint = "夜なので、今日一日ここまでで実際に何があったかを時系列で聞く。現在の行動だけを聞く形は避ける"
            greeting = "こんばんは"
        }

        return LocalTimeContext(
            timeZone: timeZone,
            now: now,
            dateString: dateString,
            timeString: timeString,
            weekdayName: weekdayNames[weekday],
            dayTypeString: isWeekend ? "休日" : "平日",
            timeSlot: timeSlot,
            chatTimeHint: timeHint,
            greetingWord: greeting
        )
    }

    static func resolveTimeZone(identifier: String?) -> TimeZone {
        if let identifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        return .autoupdatingCurrent
    }
}
