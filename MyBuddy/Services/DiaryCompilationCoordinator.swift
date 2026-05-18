import Foundation

/// 日記コンパイルの発火制御を担当するコーディネータ。
///
/// thinking モード1段パイプラインでは毎回フル再生成して VerifyStage の品質ガードで
/// 採用可否を決める。発火は (1) ユーザーの明示操作、(2) バックグラウンド遷移、
/// (3) チャット画面離脱の3経路を持つ。チャットに戻ったら即座にキャンセル
/// (`cancelForChatReturn`) して LLM を解放する。
@MainActor
final class DiaryCompilationCoordinator {
    enum Event {
        case started
        case succeeded(Bool)
        case failed(Error)
        case cancelled
    }

    struct Snapshot {
        let isTyping: Bool
        let turnCount: Int
        let hasExistingJournal: Bool
        let turnsSinceLastCompile: Int

        static let empty = Snapshot(
            isTyping: false,
            turnCount: 0,
            hasExistingJournal: false,
            turnsSinceLastCompile: 0
        )
    }

    private let snapshotProvider: @MainActor () -> Snapshot
    private let compileHandler: @MainActor () async throws -> Bool
    private let eventHandler: @MainActor (Event) -> Void
    private let config: DiaryPipelineConfig

    private var compileFailureStreak = 0
    private var compileGeneration: UInt64 = 0
    private(set) var diaryCompileTask: Task<Bool, Error>?

    /// 日記コンパイル中かどうかを外部から監視するためのフラグ
    var isCompiling: Bool { diaryCompileTask != nil }

    init(
        snapshotProvider: @escaping @MainActor () -> Snapshot,
        compileHandler: @escaping @MainActor () async throws -> Bool,
        eventHandler: @escaping @MainActor (Event) -> Void = { _ in },
        config: DiaryPipelineConfig = .default
    ) {
        self.snapshotProvider = snapshotProvider
        self.compileHandler = compileHandler
        self.eventHandler = eventHandler
        self.config = config
    }

    // MARK: - Trigger

    /// ユーザーが明示的に右上ボタンを押したときだけ呼ばれる。
    func triggerFromDiaryIconTap() {
        let snapshot = snapshotProvider()
        guard canCompile(snapshot: snapshot) else { return }
        startCompile()
    }

    /// アプリがバックグラウンドに移行した時に呼ばれる。
    func triggerFromBackground() {
        let snapshot = snapshotProvider()
        guard canCompile(snapshot: snapshot) else { return }
        startCompile()
    }

    /// チャット画面から離脱した時に呼ばれる。
    func triggerFromChatDisappear() {
        let snapshot = snapshotProvider()
        guard !snapshot.isTyping else { return }
        guard canCompile(snapshot: snapshot) else { return }
        startCompile()
    }

    // MARK: - Cancel-and-restart

    /// チャットに戻った時に呼ばれる。走行中のコンパイルを即座にキャンセルして LLM を解放する。
    func cancelForChatReturn() {
        guard let task = diaryCompileTask else { return }
        #if DEBUG
        print("[DiaryQueue] チャット復帰でコンパイルをキャンセル")
        #endif
        compileGeneration &+= 1
        task.cancel()
        diaryCompileTask = nil
        eventHandler(.cancelled)
    }

    /// 全タスクをキャンセルする。
    func cancelAll() {
        compileGeneration &+= 1
        diaryCompileTask?.cancel()
        diaryCompileTask = nil
        eventHandler(.cancelled)
    }

    /// ユーザー入力時の通知。チャット中の入力追跡用。
    func notifyUserInput() {
        // thinking モードでは idle デバウンスを使わないため、ここでは何もしない。
        // チャット中の日記コンパイルは cancelForChatReturn で既にキャンセルされている。
    }

    /// 後方互換: 旧 scheduleIdleCompile の呼出先。新方式では何もしない。
    func scheduleIdleCompile() {
        // idle デバウンスは廃止。3トリガー方式に移行済み。
    }

    /// 後方互換: 旧 scheduleUpdateOnExit の呼出先。triggerFromChatDisappear に委譲。
    func scheduleUpdateOnExit() {
        triggerFromChatDisappear()
    }

    /// 後方互換: 旧 preemptForUserInput の呼出先。
    /// キャンセル後、走行中タスクの完了を待ってから返る。
    /// これにより呼出元は LLM が解放されたことを保証できる。
    func preemptForUserInput() async {
        let task = diaryCompileTask
        cancelForChatReturn()
        if let task {
            _ = try? await task.value
        }
    }

    // MARK: - Private

    private func canCompile(snapshot: Snapshot) -> Bool {
        // 既にコンパイル中ならスキップ
        guard diaryCompileTask == nil else { return false }
        // 最低ターン数ガード
        guard config.canCompile(turnCount: snapshot.turnCount) else { return false }
        // 既存日記がありかつ新規ターンがない場合はスキップ（同じ入力で再生成しない）
        if snapshot.hasExistingJournal && snapshot.turnsSinceLastCompile == 0 {
            return false
        }
        return true
    }

    private func startCompile() {
        guard diaryCompileTask == nil else { return }

        compileGeneration &+= 1
        let generation = compileGeneration
        eventHandler(.started)

        let task = Task { [compileHandler] in
            try await compileHandler()
        }
        diaryCompileTask = task

        Task { [weak self] in
            do {
                let didCompile = try await task.value
                guard let self, self.compileGeneration == generation else { return }
                self.diaryCompileTask = nil
                self.eventHandler(.succeeded(didCompile))
                if didCompile {
                    self.compileFailureStreak = 0
                }
            } catch is CancellationError {
                // cancelForChatReturn/cancelAll が既に diaryCompileTask = nil と
                // generation を進めているため、ここでは何もしない
                #if DEBUG
                print("[Diary] コンパイル中断")
                #endif
            } catch {
                guard let self, self.compileGeneration == generation else { return }
                self.diaryCompileTask = nil
                let streak = self.compileFailureStreak + 1
                self.compileFailureStreak = streak
                #if DEBUG
                print("[Diary] コンパイルエラー: \(error) (失敗連続\(streak)回目)")
                #endif
                if streak <= self.config.maxRetries {
                    try? await Task.sleep(for: .seconds(3))
                    // sleep 中にキャンセルされていないか再確認
                    if self.compileGeneration == generation {
                        self.startCompile()
                    }
                } else {
                    #if DEBUG
                    print("[Diary] 自動リトライ上限到達、諦めます")
                    #endif
                    self.eventHandler(.failed(error))
                }
            }
        }
    }
}
