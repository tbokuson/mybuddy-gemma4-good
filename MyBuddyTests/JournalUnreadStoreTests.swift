import XCTest
@testable import MyBuddy

final class JournalUnreadStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "JournalUnreadStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMarkUnreadAndRead() {
        let id = UUID()

        XCTAssertFalse(JournalUnreadStore.isUnread(id, defaults: defaults))
        JournalUnreadStore.markUnread(id, defaults: defaults)
        XCTAssertTrue(JournalUnreadStore.isUnread(id, defaults: defaults))
        JournalUnreadStore.markRead(id, defaults: defaults)
        XCTAssertFalse(JournalUnreadStore.isUnread(id, defaults: defaults))
    }
}
