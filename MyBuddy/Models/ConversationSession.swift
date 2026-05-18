import Foundation
import SwiftData

@Model
final class ConversationSession {
    var id: UUID
    var date: Date
    var type: SessionType
    var startedAt: Date
    var endedAt: Date?
    var messageCount: Int
    var completionStatus: CompletionStatus

    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessage] = []

    init(type: SessionType = .daily) {
        self.id = UUID()
        self.date = DayBoundary.appToday()  // 深夜0-4時は前日扱い
        self.type = type
        self.startedAt = Date()
        self.messageCount = 0
        self.completionStatus = .inProgress
    }

    /// 会話履歴をプロンプト用のテキストに変換
    var messagesAsPromptText: String {
        messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { msg in
                let role = msg.isFromBuddy ? "バディ" : "ユーザー"
                return "\(role): \(msg.text)"
            }
            .joined(separator: "\n")
    }
}

enum SessionType: String, Codable {
    case onboarding
    case daily
    case consultation
}

enum CompletionStatus: String, Codable {
    case inProgress
    case completed
    case cancelled
}

@Model
final class ChatMessage {
    var id: UUID
    var text: String
    var isFromBuddy: Bool
    var timestamp: Date
    @Attribute(.externalStorage) var imageData: Data?

    var session: ConversationSession?

    var hasImage: Bool { imageData != nil }

    init(text: String, isFromBuddy: Bool, imageData: Data? = nil) {
        self.id = UUID()
        self.text = text
        self.isFromBuddy = isFromBuddy
        self.timestamp = Date()
        self.imageData = imageData
    }
}
