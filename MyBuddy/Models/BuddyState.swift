import Foundation
import SwiftData

@Model
final class BuddyState {
    var id: UUID
    var buddyId: UUID
    var streakDays: Int
    var lastCheckInDate: Date?
    var intimacyLevel: Int

    /// 長期記憶: ユーザーの恒常的な特徴（好み、仕事、家族など）
    /// キー=カテゴリ（"仕事", "好きな食べ物"等）、値=内容
    var longTermMemories: [String: String] = [:]

    /// 長期記憶の上限
    static let maxLongTermMemories = 20

    init(buddyId: UUID) {
        self.id = UUID()
        self.buddyId = buddyId
        self.streakDays = 0
        self.lastCheckInDate = nil
        self.intimacyLevel = 0
        self.longTermMemories = [:]
    }

    /// 今日チェックイン済みかどうか
    var hasCheckedInToday: Bool {
        guard let last = lastCheckInDate else { return false }
        return DayBoundary.isAppToday(last)
    }

    /// ストリーク更新
    func recordCheckIn(at now: Date = Date()) {
        if let last = lastCheckInDate {
            let lastAppDay = DayBoundary.startOfAppDay(for: last)
            let currentAppDay = DayBoundary.startOfAppDay(for: now)
            if lastAppDay == currentAppDay {
                lastCheckInDate = now
                return
            }
            let nextAppDay = Calendar.current.date(byAdding: .day, value: 1, to: lastAppDay)
            if nextAppDay == currentAppDay {
                streakDays += 1
            } else {
                streakDays = 1
            }
        } else {
            streakDays = 1
        }
        lastCheckInDate = now
        intimacyLevel = min(intimacyLevel + 1, 100)
    }
}
