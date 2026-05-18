import Foundation

extension Notification.Name {
    static let journalUnreadStateDidChange = Notification.Name("journalUnreadStateDidChange")
}

enum JournalUnreadStore {
    private static let keyPrefix = "journal.unread."

    static func markUnread(_ id: UUID, defaults: UserDefaults = .standard) {
        guard !isUnread(id, defaults: defaults) else { return }
        defaults.set(true, forKey: key(for: id))
        NotificationCenter.default.post(name: .journalUnreadStateDidChange, object: nil)
    }

    static func markRead(_ id: UUID, defaults: UserDefaults = .standard) {
        guard isUnread(id, defaults: defaults) else { return }
        defaults.removeObject(forKey: key(for: id))
        NotificationCenter.default.post(name: .journalUnreadStateDidChange, object: nil)
    }

    static func isUnread(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(for: id))
    }

    static func hasUnread(entries: [JournalEntry], defaults: UserDefaults = .standard) -> Bool {
        entries.contains { isUnread($0.id, defaults: defaults) }
    }

    static func key(for id: UUID) -> String {
        "\(keyPrefix)\(id.uuidString)"
    }
}
