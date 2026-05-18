import XCTest
@testable import MyBuddy

@MainActor
final class ChatViewModelTests: XCTestCase {

    func testDiaryLoadingModalCanBePresentedDuringBackgroundCompile() {
        let viewModel = ChatViewModel()
        viewModel.isCompilingDiary = true

        viewModel.presentDiaryLoadingIfNeeded()

        XCTAssertTrue(viewModel.isShowingDiaryLoadingModal)
    }
}
