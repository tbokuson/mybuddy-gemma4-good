import XCTest
@testable import MyBuddy

/// DiaryCompilationCoordinator のユニットテスト。
///
/// 3トリガー（アイコンタップ・バックグラウンド・画面離脱）の発火条件と
/// cancel-and-restart のキャンセル動作を検証する。
@MainActor
final class DiaryCompilationCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeCoordinator(
        snapshot: DiaryCompilationCoordinator.Snapshot? = nil,
        config: DiaryPipelineConfig = .default,
        compileHandler: @MainActor @Sendable @escaping () async throws -> Bool = { true }
    ) -> DiaryCompilationCoordinator {
        let snap = snapshot ?? DiaryCompilationCoordinator.Snapshot.empty
        return DiaryCompilationCoordinator(
            snapshotProvider: { snap },
            compileHandler: compileHandler,
            config: config
        )
    }

    private func snapshotWith(
        isTyping: Bool = false,
        turnCount: Int = 5,
        hasExistingJournal: Bool = false,
        turnsSinceLastCompile: Int = 5
    ) -> DiaryCompilationCoordinator.Snapshot {
        DiaryCompilationCoordinator.Snapshot(
            isTyping: isTyping,
            turnCount: turnCount,
            hasExistingJournal: hasExistingJournal,
            turnsSinceLastCompile: turnsSinceLastCompile
        )
    }

    // MARK: - triggerFromDiaryIconTap

    func testDiaryIconTapStartsCompileWhenConditionsMet() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromDiaryIconTap()

        XCTAssertTrue(coordinator.isCompiling)
    }

    func testDiaryIconTapSkipsWhenBelowMinTurns() {
        let snapshot = snapshotWith(turnCount: 0)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromDiaryIconTap()

        XCTAssertFalse(coordinator.isCompiling)
    }

    func testDiaryIconTapSkipsWhenAlreadyCompiling() {
        let snapshot = snapshotWith(turnCount: 5)
        var startCount = 0
        let coordinator = makeCoordinator(snapshot: snapshot) {
            startCount += 1
            // 長時間 sleep して compileHandler が走り続ける状態を維持
            try await Task.sleep(for: .seconds(10))
            return true
        }

        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling, "1回目でコンパイル開始")

        // MainActor の Task で startCompile -> diaryCompileTask 設定は同期的
        // 2回目は canCompile で diaryCompileTask != nil → false → スキップ
        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling, "まだコンパイル中（2回目はスキップされた）")
    }

    // MARK: - triggerFromBackground

    func testBackgroundTriggerStartsCompileWhenConditionsMet() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromBackground()

        XCTAssertTrue(coordinator.isCompiling)
    }

    func testBackgroundTriggerSkipsWhenBelowMinTurns() {
        let snapshot = snapshotWith(turnCount: 0)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromBackground()

        XCTAssertFalse(coordinator.isCompiling)
    }

    // MARK: - triggerFromChatDisappear

    func testChatDisappearStartsCompileWhenConditionsMet() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromChatDisappear()

        XCTAssertTrue(coordinator.isCompiling)
    }

    func testChatDisappearSkipsWhenUserIsTyping() {
        let snapshot = snapshotWith(isTyping: true, turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromChatDisappear()

        XCTAssertFalse(coordinator.isCompiling)
    }

    func testChatDisappearSkipsWhenBelowMinTurns() {
        let snapshot = snapshotWith(turnCount: 0)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromChatDisappear()

        XCTAssertFalse(coordinator.isCompiling)
    }

    // MARK: - cancelForChatReturn

    func testCancelForChatReturnCancelsRunningTask() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot) {
            try await Task.sleep(for: .seconds(10))
            return true
        }

        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling)

        coordinator.cancelForChatReturn()
        XCTAssertFalse(coordinator.isCompiling)
    }

    func testCancelForChatReturnIsNoOpWhenNotCompiling() {
        let coordinator = makeCoordinator()

        // クラッシュしないことを確認
        coordinator.cancelForChatReturn()
        XCTAssertFalse(coordinator.isCompiling)
    }

    // MARK: - cancelAll

    func testCancelAllCancelsRunningTask() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot) {
            try await Task.sleep(for: .seconds(10))
            return true
        }

        coordinator.triggerFromBackground()
        XCTAssertTrue(coordinator.isCompiling)

        coordinator.cancelAll()
        XCTAssertFalse(coordinator.isCompiling)
    }

    // MARK: - 後方互換スタブ

    func testNotifyUserInputIsNoOp() {
        let coordinator = makeCoordinator()
        // クラッシュしないことを確認
        coordinator.notifyUserInput()
    }

    func testScheduleIdleCompileIsNoOp() {
        let coordinator = makeCoordinator()
        coordinator.scheduleIdleCompile()
        XCTAssertFalse(coordinator.isCompiling, "idle コンパイルは廃止済み")
    }

    func testScheduleUpdateOnExitDelegatesToChatDisappear() {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.scheduleUpdateOnExit()
        XCTAssertTrue(coordinator.isCompiling)
    }

    func testPreemptForUserInputWaitsForQuiescence() async {
        let snapshot = snapshotWith(turnCount: 5)
        var handlerFinished = false
        let coordinator = makeCoordinator(snapshot: snapshot) {
            defer { handlerFinished = true }
            try await Task.sleep(for: .seconds(10))
            return true
        }

        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling)

        // preemptForUserInput はタスク完了を待ってから返る
        await coordinator.preemptForUserInput()
        XCTAssertFalse(coordinator.isCompiling)
        XCTAssertTrue(handlerFinished, "compileHandler の実行が完了してから返る")
    }

    // MARK: - 最低ターン数ガード境界値

    func testMinTurnsGuardBoundary() {
        let config = DiaryPipelineConfig.default
        let minTurns = config.minTurnsToCompile

        // ちょうど minTurns → 発火する
        let atMin = snapshotWith(turnCount: minTurns)
        let coord1 = makeCoordinator(snapshot: atMin, config: config)
        coord1.triggerFromDiaryIconTap()
        XCTAssertTrue(coord1.isCompiling)

        // minTurns - 1 → 発火しない
        let belowMin = snapshotWith(turnCount: minTurns - 1)
        let coord2 = makeCoordinator(snapshot: belowMin, config: config)
        coord2.triggerFromDiaryIconTap()
        XCTAssertFalse(coord2.isCompiling)
    }

    // MARK: - stale journal 再生成ガード

    func testSkipsWhenExistingJournalAndNoNewTurns() {
        let snapshot = snapshotWith(
            turnCount: 5,
            hasExistingJournal: true,
            turnsSinceLastCompile: 0
        )
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromDiaryIconTap()
        XCTAssertFalse(coordinator.isCompiling, "新規ターンがないため再生成しない")
    }

    func testCompilesWhenExistingJournalAndNewTurns() {
        let snapshot = snapshotWith(
            turnCount: 5,
            hasExistingJournal: true,
            turnsSinceLastCompile: 2
        )
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling, "新規ターンがあるため再生成する")
    }

    func testCompilesWhenNoExistingJournal() {
        let snapshot = snapshotWith(
            turnCount: 5,
            hasExistingJournal: false,
            turnsSinceLastCompile: 0
        )
        let coordinator = makeCoordinator(snapshot: snapshot)

        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling, "日記がまだないので初回コンパイルする")
    }

    // MARK: - cancel-and-restart でタスク参照を失わない

    func testCancelAndRestartKeepsTrackOfNewTask() async {
        let snapshot = snapshotWith(turnCount: 5)
        let coordinator = makeCoordinator(snapshot: snapshot) {
            try await Task.sleep(for: .seconds(10))
            return true
        }

        // 1. 最初のコンパイルを開始
        coordinator.triggerFromDiaryIconTap()
        XCTAssertTrue(coordinator.isCompiling, "1回目のコンパイル開始")

        // 2. キャンセル
        coordinator.cancelForChatReturn()
        XCTAssertFalse(coordinator.isCompiling, "キャンセル後は非コンパイル状態")

        // 3. すぐに新しいコンパイルを開始
        coordinator.triggerFromBackground()
        XCTAssertTrue(coordinator.isCompiling, "2回目のコンパイル開始")

        // 4. yield して旧監視 Task のクリーンアップが走る余地を与える
        await Task.yield()
        await Task.yield()

        // 5. 新しいコンパイルの参照が生きていることを確認
        XCTAssertTrue(coordinator.isCompiling, "旧タスクのクリーンアップで新タスク参照が消えない")
    }
}
