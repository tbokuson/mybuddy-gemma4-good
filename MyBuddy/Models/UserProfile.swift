import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var nickname: String
    var createdAt: Date
    var timezone: String
    var onboardingCompleted: Bool
    var preferredReminderTime: Date?

    init(
        nickname: String = "",
        timezone: String = TimeZone.current.identifier,
        onboardingCompleted: Bool = false
    ) {
        self.id = UUID()
        self.nickname = nickname
        self.createdAt = Date()
        self.timezone = timezone
        self.onboardingCompleted = onboardingCompleted
    }
}
