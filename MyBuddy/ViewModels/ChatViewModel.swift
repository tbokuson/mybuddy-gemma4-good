import Foundation
import SwiftUI
import SwiftData
import Combine
import PhotosUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var inputText: String = ""
    @Published var isTyping: Bool = false
    @Published var journalResult: JournalGenerationResult?
    /// 日記コンパイル中
    @Published var isCompilingDiary: Bool = false
    @Published var hasJournal: Bool = false
    @Published var isShowingDiaryLoadingModal: Bool = false
    @Published var diaryPresentationTick: Int = 0
    /// 日記が更新された瞬間にトーストを表示するためのトリガー
    @Published var diaryUpdatedToastTick: Int = 0
    /// 締めの挨拶を検知したら true。日記作成サジェストのトーストを表示する。
    @Published var shouldSuggestDiary: Bool = false

    // 画像添付
    @Published var selectedImage: UIImage?
    @Published var selectedImageData: Data?
    @Published var isLoadingVision: Bool = false
    @Published var imageAttachCount: Int = 0
    static let maxImageAttachments = 8

    // 日記通知用
    @Published var isNewJournalCreation: Bool = false
    // ストリーミング中のスクロール用
    @Published var streamingUpdateCount: Int = 0
    var shouldShowDiaryPreparingIndicator: Bool {
        (!hasJournal && isCompilingDiary) || shouldShowDiaryUpdatingIndicator
    }

    var shouldShowDiaryUpdatingIndicator: Bool {
        hasJournal && isCompilingDiary
    }

    var shouldShowDiaryToolbarButton: Bool { turnCount > 0 }

    var diaryToolbarTitle: String { hasJournal ? AppText.current.updateDiary : AppText.current.writeDiary }

    var canTriggerDiaryCompilation: Bool {
        guard turnCount > 0, !isCompilingDiary else { return false }
        if hasJournal {
            return turnsSinceLastCompile > 0
        }
        return true
    }

    var canOpenExistingJournal: Bool { hasJournal && !isCompilingDiary }

    var diaryLoadingMessage: String {
        hasJournal ? AppText.current.diaryLoadingUpdate : AppText.current.diaryLoadingNew
    }

    private var session: ConversationSession?
    private var buddy: BuddyProfile?
    private var llmService: (any LLMServiceProtocol)?
    private var modelContext: ModelContext?
    private var turnCount: Int = 0
    /// ユーザーの連続した明確な終了意思カウンタ。相づちだけでは会話を閉じない。
    private var consecutiveShortReplies: Int = 0
    /// 「うん」「はい」など低情報の返答が続いた回数。プロンプト上の緩やかな締め寄せに使う。
    private var consecutiveLowSignalReplies: Int = 0
    /// バディの連続「非質問」応答カウンタ。末尾が「？」「?」でない応答が続いた回数。
    private var consecutiveNonQuestionBuddyReplies: Int = 0
    @Published var existingJournalEntry: JournalEntry?
    private var userInputCharCount: Int = 0
    private var userNickname: String = ""
    private var userTimezone: String = TimeZone.autoupdatingCurrent.identifier
    private var turnsSinceLastCompile: Int = 0
    /// 最後に画像を送信したターン番号。画像フォローアップ判定に使用。
    private var lastImageTurnCount: Int?
    /// 今セッション中で締めサジェストを一度でも出したか。二重表示を抑止する。
    private var hasSuggestedDiaryThisSession: Bool = false
    private var diaryCoordinator: DiaryCompilationCoordinator?
    private var pendingDiaryPresentationAfterCompile = false

    struct DisplayMessage: Identifiable {
        let id = UUID()
        var text: String
        let isFromBuddy: Bool
        let timestamp: Date
        let image: UIImage?

        init(text: String, isFromBuddy: Bool, timestamp: Date = Date(), image: UIImage? = nil) {
            self.text = text
            self.isFromBuddy = isFromBuddy
            self.timestamp = timestamp
            self.image = image
        }
    }

    // MARK: - Setup

    func setup(
        buddy: BuddyProfile,
        llmService: any LLMServiceProtocol,
        modelContext: ModelContext
    ) {
        self.buddy = buddy
        self.llmService = llmService
        self.modelContext = modelContext
        if diaryCoordinator == nil {
            diaryCoordinator = makeDiaryCompilationCoordinator()
        }

        // ユーザーのニックネームを取得
        var userDescriptor = FetchDescriptor<UserProfile>()
        userDescriptor.fetchLimit = 1
        if let user = try? modelContext.fetch(userDescriptor).first {
            self.userNickname = user.nickname
            self.userTimezone = user.timezone
        }

        // 今日の既存セッションを検索（朝4時区切り）
        // session.dateはDayBoundary.appToday()（midnight）で保存されるため、同じ基準で比較
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate<ConversationSession> {
                $0.date >= today && $0.date < tomorrow
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let todaySessions = (try? modelContext.fetch(descriptor)) ?? []
        let todaySession = todaySessions.first { $0.type == .daily }

        #if DEBUG
        print("[Session] 今日のセッション検索: \(todaySessions.count)件ヒット, daily=\(todaySession != nil)")
        #endif

        // セッションの有無に関わらず、当日の日記が既に存在するかを確認
        checkForExistingJournal()

        if let todaySession {
            // 既存セッションを再開
            self.session = todaySession
            self.turnCount = todaySession.messageCount / 2
            // ユーザーの入力文字数を復元
            self.userInputCharCount = todaySession.messages
                .filter { !$0.isFromBuddy }
                .reduce(0) { total, msg in
                    let textCount = (msg.text == "この画像について教えて" && msg.imageData != nil) ? 0 : msg.text.count
                    let imageCount = msg.imageData != nil ? 50 : 0
                    return total + textCount + imageCount
                }
            // 画像添付数を復元
            self.imageAttachCount = todaySession.messages
                .filter { !$0.isFromBuddy && $0.imageData != nil }
                .count
            reloadMessages(from: todaySession)
            #if DEBUG
            print("[Session] セッション再開: \(todaySession.messageCount)メッセージ, turnCount=\(turnCount), userInput=\(userInputCharCount)文字, 画像=\(imageAttachCount)枚")
            #endif

            // 最後のメッセージから30分以上経っていたら「おかえり」挨拶
            if let lastMessage = todaySession.messages.sorted(by: { $0.timestamp < $1.timestamp }).last,
               Date().timeIntervalSince(lastMessage.timestamp) > 30 * 60 {
                Task {
                    await sendResumeGreeting()
                }
            }
        } else {
            // 新しいセッションを作成
            let newSession = ConversationSession(type: .daily)
            modelContext.insert(newSession)
            try? modelContext.save()
            self.session = newSession
            #if DEBUG
            print("[Session] 新規セッション作成")
            #endif

            Task {
                await sendBuddyGreeting()
            }
        }

    }

    // MARK: - Actions

    func sendMessage() {
        let policy: UserInputSanitizer.Policy = selectedImage == nil ? .chatMessage : .imagePromptText
        let text = UserInputSanitizer.sanitize(inputText, policy: policy)
        guard !text.isEmpty || selectedImage != nil, !isTyping else { return }

        let messageText = text
        let attachedImage = selectedImage
        let attachedImageData = selectedImageData

        inputText = ""
        selectedImage = nil
        selectedImageData = nil
        isTyping = true // 即座にtrueにして二重送信を防ぐ
        diaryCoordinator?.notifyUserInput()

        let userMessageId = addMessage(text: messageText, isFromBuddy: false, image: attachedImage, imageData: attachedImageData)
        turnCount += 1
        turnsSinceLastCompile += 1

        // ユーザーの入力情報量をカウント（画像は50文字相当）
        if !messageText.isEmpty {
            userInputCharCount += messageText.count
        }
        if attachedImageData != nil {
            userInputCharCount += 50
            imageAttachCount += 1
            lastImageTurnCount = turnCount
        }

        Task {
            await diaryCoordinator?.preemptForUserInput()
            await generateBuddyResponse(userMessage: messageText, imageData: attachedImageData, userMessageId: userMessageId)
        }
    }

    /// PhotosPickerItemから画像をロード
    func attachImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            selectedImageData = nil
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        // 768x768にリサイズ（モデル入力サイズに合わせる）
        let resized = resizeImage(uiImage, maxSize: 768)
        let jpegData = resized.jpegData(compressionQuality: 0.85)

        self.selectedImage = resized
        self.selectedImageData = jpegData
    }

    /// 添付画像をクリア
    func clearAttachedImage() {
        selectedImage = nil
        selectedImageData = nil
    }

    // MARK: - 日記コンパイルトリガー

    /// トリガー1: 日記アイコンタップ時
    func triggerDiaryFromIconTap() {
        guard canTriggerDiaryCompilation else { return }
        pendingDiaryPresentationAfterCompile = true
        isShowingDiaryLoadingModal = true
        diaryCoordinator?.triggerFromDiaryIconTap()
    }

    /// アプリがバックグラウンドに移行した時
    func triggerDiaryFromBackground() {
        diaryCoordinator?.triggerFromBackground()
    }

    /// チャット画面離脱時
    func scheduleDiaryUpdateOnExit() {
        diaryCoordinator?.triggerFromChatDisappear()
    }

    /// チャット復帰時: 走行中のコンパイルをキャンセル
    func cancelDiaryForChatReturn() {
        diaryCoordinator?.cancelForChatReturn()
    }

    func presentDiaryLoadingIfNeeded() {
        guard isCompilingDiary else { return }
        isShowingDiaryLoadingModal = true
    }

    func cancelDiaryCompilationFromModal() {
        isShowingDiaryLoadingModal = false
        pendingDiaryPresentationAfterCompile = false
        diaryCoordinator?.cancelForChatReturn()
    }

    func consumeDiaryPresentationTick() {
        pendingDiaryPresentationAfterCompile = false
    }

    private func makeDiaryCompilationCoordinator() -> DiaryCompilationCoordinator {
        DiaryCompilationCoordinator(
            snapshotProvider: { [weak self] in
                self?.makeDiaryQueueSnapshot() ?? .empty
            },
            compileHandler: { [weak self] in
                guard let self else { return false }
                return try await self.compilePendingDiary()
            },
            eventHandler: { [weak self] event in
                self?.handleDiaryCompilationEvent(event)
            }
        )
    }

    private func makeDiaryQueueSnapshot() -> DiaryCompilationCoordinator.Snapshot {
        DiaryCompilationCoordinator.Snapshot(
            isTyping: isTyping,
            turnCount: turnCount,
            hasExistingJournal: existingJournalEntry != nil,
            turnsSinceLastCompile: turnsSinceLastCompile
        )
    }

    private func compilePendingDiary() async throws -> Bool {
        guard let buddy = buddy,
              let llmService = llmService,
              let modelContext = modelContext else { return false }

        isCompilingDiary = true
        defer {
            isCompilingDiary = false
        }

        if existingJournalEntry == nil {
            checkForExistingJournal()
        }

        let unprocessedMessages = fetchUnprocessedUserMessages(modelContext: modelContext)
        let conversationTurns = fetchUnprocessedConversationTurns(sourceMessages: unprocessedMessages)
        let existingMemos = fetchTodayMemos(modelContext: modelContext)
        let journalService = JournalService(llmService: llmService)

        var pipelineResult: DiaryPipelineResult
        do {
            pipelineResult = try await journalService.compile(
                userMessages: unprocessedMessages,
                conversationTurns: conversationTurns,
                existingMemos: existingMemos,
                turnCount: turnCount,
                existingJournal: existingJournalEntry,
                memoryPreference: buddy.memoryPreference,
                memoryPreferenceCustom: buddy.memoryPreferenceCustom,
                buddyName: buddy.displayName,
                buddySeed: buddy.seed,
                language: AppLanguageMode.currentResolved
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if existingJournalEntry != nil {
                #if DEBUG
                print("[Diary] コンパイル失敗: 既存日記を維持 \(error)")
                #endif
                throw error
            }
            #if DEBUG
            print("[Diary] コンパイル失敗: 初回のため最低限本文を作成 \(error)")
            #endif
            pipelineResult = JournalService.minimalNewJournal(userMessages: unprocessedMessages)
        }

        // 抽出されたメモを DiaryNote として保存（品質ガード結果に関わらず保存）
        saveDiaryNotes(
            pipelineResult.extractedMemos,
            sourceMessages: unprocessedMessages,
            modelContext: modelContext
        )

        // 品質ガードで採用拒否されたら、日記は変更せず早期 return
        guard pipelineResult.accepted else {
            #if DEBUG
            print("[Diary] 品質ガード拒否: \(pipelineResult.rejectionReason ?? "-") — 既存日記を維持")
            #endif
            try? modelContext.save()
            return false
        }

        // 日記本文が空の場合
        if pipelineResult.body.isEmpty {
            if existingJournalEntry != nil {
                // 既存日記がある → 次回に期待してスキップ
                #if DEBUG
                print("[Diary] メモ抽出のみ完了、日記生成は次回")
                #endif
                try? modelContext.save()
                return false
            }
            // 初回で中身なし → 固定文の最低限日記を作成（パイプライン結果を差し替えて続行）
            #if DEBUG
            print("[Diary] 中身不足だが初回のため最低限日記を作成")
            #endif
            let minimal = JournalService.minimalNewJournal(
                userMessages: []  // 中身がないので固定文を使用
            )
            pipelineResult = minimal
        }

        let conversationImages = session?.messages.compactMap { $0.imageData } ?? []
        let result = JournalGenerationResult(
            title: pipelineResult.title,
            body: pipelineResult.body,
            summary: String(pipelineResult.body.prefix(60)),
            emotionTags: pipelineResult.emotionTags,
            tomorrowNote: pipelineResult.tomorrowNote,
            imageDataList: conversationImages.isEmpty ? nil : conversationImages
        )
        journalResult = result

        let isNewJournal: Bool
        let unreadJournalID: UUID
        if let existing = existingJournalEntry {
            existing.title = result.title
            existing.summaryText = result.summary
            existing.fullDiaryText = result.body
            existing.emotionTags = result.emotionTags
            existing.tomorrowNote = result.tomorrowNote
            existing.imageDataList = conversationImages.isEmpty ? nil : conversationImages
            existing.nameCoverage = pipelineResult.nameCoverage
            unreadJournalID = existing.id
            isNewJournal = false
        } else {
            let entry = JournalEntry(
                date: DayBoundary.appToday(),
                title: result.title,
                summaryText: result.summary,
                fullDiaryText: result.body,
                emotionTags: result.emotionTags,
                tomorrowNote: result.tomorrowNote,
                imageDataList: conversationImages.isEmpty ? nil : conversationImages,
                nameCoverage: pipelineResult.nameCoverage
            )
            modelContext.insert(entry)
            existingJournalEntry = entry
            unreadJournalID = entry.id
            isNewJournal = true

            let fetchDescriptor = FetchDescriptor<BuddyState>()
            if let buddyState = try? modelContext.fetch(fetchDescriptor).first {
                buddyState.recordCheckIn()
            }
        }

        hasJournal = true
        isNewJournalCreation = isNewJournal
        diaryUpdatedToastTick &+= 1
        UserDefaults.standard.set(true, forKey: Self.todayJournalFlagKey())

        try? modelContext.save()
        JournalUnreadStore.markUnread(unreadJournalID)
        turnsSinceLastCompile = 0
        #if DEBUG
        print("[Diary] コンパイル完了: isNew=\(isNewJournal), coverage=\(String(format: "%.2f", pipelineResult.nameCoverage))")
        #endif
        return true
    }

    // MARK: - メモ関連

    /// 今日の未処理ユーザー発話を取得する（既にメモ抽出済みのメッセージを除外）
    private func fetchUnprocessedUserMessages(modelContext: ModelContext) -> [DiaryPipelineInput.UserMessage] {
        guard let session else { return [] }

        // 当日の DiaryNote から処理済み sourceMessageId を取得
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let noteDescriptor = FetchDescriptor<DiaryNote>(
            predicate: #Predicate<DiaryNote> {
                $0.date >= today && $0.date < tomorrow
            }
        )
        let processedIds = Set(
            (try? modelContext.fetch(noteDescriptor))?.compactMap(\.sourceMessageId) ?? []
        )

        return session.messages
            .filter { !$0.isFromBuddy && !processedIds.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
            .map { msg in
                DiaryPipelineInput.UserMessage(
                    id: msg.id,
                    text: UserInputSanitizer.sanitize(msg.text, policy: .diaryPipelineText),
                    timestamp: msg.timestamp
                )
            }
    }

    /// 未処理区間の会話ターンを取得する。最初の未処理 user 発話の直前 1 ターンだけ残し、
    /// 省略された主語や対象を日記抽出で補いやすくする。
    private func fetchUnprocessedConversationTurns(
        sourceMessages: [DiaryPipelineInput.UserMessage]
    ) -> [DiaryPipelineInput.ConversationTurn] {
        guard let session, let firstSource = sourceMessages.first else { return [] }

        let sorted = session.messages.sorted { $0.timestamp < $1.timestamp }
        guard let firstIndex = sorted.firstIndex(where: { $0.id == firstSource.id }) else { return [] }

        let startIndex = max(0, firstIndex - 1)
        return Array(sorted[startIndex...]).map { msg in
            DiaryPipelineInput.ConversationTurn(
                id: msg.id,
                role: msg.isFromBuddy ? .buddy : .user,
                text: UserInputSanitizer.sanitize(msg.text, policy: .diaryPipelineText),
                timestamp: msg.timestamp
            )
        }
    }

    /// 当日の全メモをスナップショットとして取得する
    private func fetchTodayMemos(modelContext: ModelContext) -> [DiaryPipelineInput.MemoSnapshot] {
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<DiaryNote>(
            predicate: #Predicate<DiaryNote> {
                $0.date >= today && $0.date < tomorrow
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        return notes.map {
            DiaryPipelineInput.MemoSnapshot(fact: $0.fact, emotion: $0.emotion, createdAt: $0.createdAt)
        }
    }

    /// 抽出されたメモを DiaryNote として SwiftData に保存する
    private func saveDiaryNotes(
        _ memos: [MemoExtractionStage.MemoItem],
        sourceMessages: [DiaryPipelineInput.UserMessage],
        modelContext: ModelContext
    ) {
        guard !memos.isEmpty else { return }
        let today = DayBoundary.appToday()

        for (index, memo) in memos.enumerated() {
            // sourceMessages とメモの対応は厳密ではないが、最も近いメッセージIDを割り当てる
            let sourceId = index < sourceMessages.count ? sourceMessages[index].id : sourceMessages.last?.id
            let note = DiaryNote(
                date: today,
                fact: memo.fact,
                emotion: memo.emotion,
                sourceMessageId: sourceId
            )
            modelContext.insert(note)
        }
        #if DEBUG
        print("[Diary] メモ保存: \(memos.count)件")
        #endif
    }

    // MARK: - Private

    private func reloadMessages(from session: ConversationSession) {
        let sorted = session.messages.sorted { $0.timestamp < $1.timestamp }
        self.messages = sorted.map { chatMsg in
            DisplayMessage(
                text: chatMsg.text,
                isFromBuddy: chatMsg.isFromBuddy,
                timestamp: chatMsg.timestamp,
                image: chatMsg.imageData.flatMap { UIImage(data: $0) }
            )
        }
    }

    private func checkForExistingJournal() {
        guard let modelContext = modelContext else { return }
        // journal.dateもDayBoundary.appToday()（midnight）で保存されるため、同じ基準で比較
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> {
                $0.date >= today && $0.date < tomorrow
            }
        )
        descriptor.fetchLimit = 1
        if let entry = try? modelContext.fetch(descriptor).first {
            self.existingJournalEntry = entry
            self.hasJournal = true
        }
    }

    private func sendBuddyGreeting() async {
        guard let buddy = buddy, let modelContext = modelContext else { return }
        isTyping = true

        // 初日判定: 過去にdailyセッションが存在しない = オンボーディング直後の初日
        let dailyType = SessionType.daily
        var dailyDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate<ConversationSession> {
                $0.type == dailyType
            }
        )
        dailyDescriptor.fetchLimit = 2
        let dailyCount = ((try? modelContext.fetch(dailyDescriptor)) ?? []).count
        let isFirstDay = dailyCount <= 1

        let tomorrowNote = isFirstDay ? nil : MemoryContextBuilder.getMostRecentTomorrowNote(modelContext: modelContext)
        let greeting = await generateLLMGreeting(
            buddy: buddy,
            isFirstDay: isFirstDay,
            isResume: false,
            tomorrowNote: tomorrowNote
        )

        addMessage(text: greeting, isFromBuddy: true)
        isTyping = false
    }

    private func sendResumeGreeting() async {
        guard let buddy = buddy else { return }
        isTyping = true

        let greeting = await generateLLMGreeting(
            buddy: buddy,
            isFirstDay: false,
            isResume: true,
            tomorrowNote: nil
        )

        addMessage(text: greeting, isFromBuddy: true)
        isTyping = false
    }

    /// 開始挨拶は固定テンプレートではなく、人格から決定的に組み立てる。
    private func generateLLMGreeting(
        buddy: BuddyProfile,
        isFirstDay: Bool,
        isResume: Bool,
        tomorrowNote: String?
    ) async -> String {
        if AppLanguageMode.currentResolved == .english {
            return isResume ? AppText.current.englishResumeGreeting : AppText.current.englishGreeting
        }

        let composer = PersonaLineComposer(displayName: buddy.displayName, seed: buddy.seed)

        if isFirstDay {
            let saved = buddy.firstDayGreeting.trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty {
                return saved
            }
            return composer.firstDayGreeting(nickname: userNickname)
        }
        if isResume {
            return composer.resumeGreeting(nickname: userNickname)
        }
        let timeContext = LocalTimeContext.make(timeZoneIdentifier: userTimezone)
        let greeting = composer.dailyGreeting(
            nickname: userNickname,
            timeSlot: timeContext.timeSlot,
            tomorrowNote: tomorrowNote
        )
        ProbeLogger.block(ProbeChannel.chat, title: "task=chat.greeting output.final", text: greeting)
        ProbeLogger.log(ProbeChannel.chat, "task=chat.greeting deterministic=true")
        return greeting
    }

    /// 3回連続の短応答で会話を終了するメッセージを生成する。
    private func generateClosingMessage(buddy: BuddyProfile) async -> String {
        if AppLanguageMode.currentResolved == .english {
            return AppText.current.englishClosing
        }
        let closing = PersonaLineComposer(displayName: buddy.displayName, seed: buddy.seed)
            .closingLine(nickname: userNickname)
        #if DEBUG
        print("[Chat] 会話終了メッセージ生成: \(closing)")
        #endif
        ProbeLogger.block(ProbeChannel.chat, title: "task=chat.closing output.final", text: closing)
        ProbeLogger.log(ProbeChannel.chat, "task=chat.closing deterministic=true")
        return closing
    }

    private func generateBuddyResponse(userMessage: String, imageData: Data? = nil, userMessageId: UUID? = nil) async {
        guard let buddy = buddy, let llmService = llmService, let modelContext = modelContext else { return }

        // 連続した終了意思・低情報返答の追跡（画像付きは除外）
        if imageData == nil {
            if Self.isDismissiveReply(userMessage) {
                consecutiveShortReplies += 1
            } else {
                consecutiveShortReplies = 0
            }
            if Self.isLowSignalReply(userMessage) {
                consecutiveLowSignalReplies += 1
            } else {
                consecutiveLowSignalReplies = 0
            }
        }

        // 2回連続で明確な終了意思 → 締めの一言 + 日記サジェスト Toast 強制表示
        // （旧実装はバディの疑問符状態も AND で要求していたが、フォールバック応答が常に「？」で
        //  終わるため閾値に到達しなかった。ユーザーが 2 回続けて明確な締めサインを出した時点で締める）
        if consecutiveShortReplies >= 2 {
            consecutiveShortReplies = 0
            consecutiveLowSignalReplies = 0
            consecutiveNonQuestionBuddyReplies = 0
            isTyping = true
            let closing = await generateClosingMessage(buddy: buddy)
            addMessage(text: closing, isFromBuddy: true)
            isTyping = false
            maybeSuggestDiaryOnClosing(userMessage: userMessage, buddyReply: closing, force: true)
            return
        }

        isTyping = true
        let memoryContext = MemoryContextBuilder.buildMemoryContext(modelContext: modelContext)
        // 画像フォローアップ判定: テキストのみのターンで、直前が画像ターンの場合
        let isImageFollowUp = imageData == nil && lastImageTurnCount == turnCount - 1
        let request = makeChatResponseRequest(
            buddy: buddy,
            userMessage: userMessage,
            memoryContext: memoryContext,
            isImageFollowUp: isImageFollowUp
        )
        let chatResponseService = ChatResponseService(llmService: llmService)
        ProbeLogger.log(
            ProbeChannel.chat,
            "task=\(imageData == nil ? "chat.reply" : "chat.imageReply") user=\(ProbeLogger.inline(userMessage)) history_count=\(request.history.count) memory_chars=\(memoryContext.count) image_follow_up=\(isImageFollowUp)"
        )

        do {
            if let imageData {
                if !llmService.visionLoaded {
                    isLoadingVision = true
                    do {
                        try await llmService.loadVision()
                    } catch {
                        isLoadingVision = false
                        #if DEBUG
                        print("[Chat] Visionロード失敗: \(error)")
                        #endif
                        handleImageAnalysisUnavailable()
                        return
                    }
                    isLoadingVision = false
                }

                let responseStart = Date()
                let cleanResponse: String
                do {
                    cleanResponse = try await chatResponseService.generateImageReply(
                        for: request,
                        imageData: imageData,
                        maxTokens: 192
                    )
                } catch {
                    #if DEBUG
                    print("[Chat] 画像推論失敗: \(error)")
                    #endif
                    handleImageAnalysisUnavailable()
                    return
                }
                let responseLatency = Date().timeIntervalSince(responseStart)
                let normalized = normalizeUnexpectedReplyStyle(cleanResponse, buddy: buddy)
                #if DEBUG
                print("[Chat] 応答時間(画像)=\(String(format: "%.2f", responseLatency))s")
                #endif
                let evaluation = normalized.hasUnexpectedDialect
                    ? (needs: true, reason: "unexpected-dialect")
                    : evaluateFallbackNeed(normalized.text, userMessage: userMessage)
                let closingModeImg = consecutiveShortReplies >= 2
                let fallbackReply = buildConversationFallbackReply(
                    for: userMessage,
                    buddy: buddy,
                    preferQuestion: Self.shouldPreferQuestionFallback(reason: evaluation.reason),
                    closingMode: closingModeImg
                )
                let finalReply = evaluation.needs ? fallbackReply : normalized.text
                #if DEBUG
                print("[Chat] 生LLM応答(画像,\(cleanResponse.count)文字): \(cleanResponse)")
                #endif
                if normalized.changed {
                    ProbeLogger.log(ProbeChannel.chat, "task=chat.imageReply postprocess=normalized_unexpected_style")
                }
                ProbeLogger.block(ProbeChannel.chat, title: "task=chat.imageReply output.cleaned", text: normalized.text)
                if evaluation.needs {
                    #if DEBUG
                    print("[Chat] フォールバック発火 reason=\(evaluation.reason ?? "unknown") → \(fallbackReply)")
                    #endif
                }
                ProbeLogger.block(ProbeChannel.chat, title: "task=chat.imageReply output.final", text: finalReply)
                ProbeLogger.log(
                    ProbeChannel.chat,
                    "task=chat.imageReply fallback_used=\(evaluation.needs) reason=\(evaluation.reason ?? "none")"
                )
                addMessage(text: finalReply, isFromBuddy: true)
                trackBuddyQuestionStatus(finalReply)
                maybeSuggestDiaryOnClosing(userMessage: userMessage, buddyReply: finalReply)
            } else {
                let responseStart = Date()
                let cleanResponse: String
                #if DEBUG
                if llmService is OllamaService {
                    // Ollamaは無応答ストリームが起きるため、1発生成を優先する
                    cleanResponse = try await chatResponseService.generateReply(for: request, maxTokens: 192)
                } else {
                    let placeholderIndex = messages.count
                    messages.append(DisplayMessage(text: "", isFromBuddy: true))

                    let stream = chatResponseService.streamReply(for: request, maxTokens: 192)
                    let streamTask = Task { () throws -> String in
                        var latestReply = ""
                        for try await piece in stream {
                            latestReply = piece
                            await MainActor.run {
                                self.messages[placeholderIndex].text = piece
                                self.streamingUpdateCount += 1
                            }
                        }
                        return latestReply
                    }
                    let timeoutTask = Task {
                        try? await Task.sleep(nanoseconds: 75 * 1_000_000_000)
                        streamTask.cancel()
                    }
                    do {
                        cleanResponse = try await streamTask.value
                    } catch is CancellationError {
                        timeoutTask.cancel()
                        throw NSError(domain: "Chat", code: -1, userInfo: [NSLocalizedDescriptionKey: "応答がタイムアウトしました"])
                    }
                    timeoutTask.cancel()
                    if messages.indices.contains(placeholderIndex) {
                        messages.remove(at: placeholderIndex)
                    }
                }
                #else
                let placeholderIndex = messages.count
                messages.append(DisplayMessage(text: "", isFromBuddy: true))

                let stream = chatResponseService.streamReply(for: request, maxTokens: 192)
                let streamTask = Task { () throws -> String in
                    var latestReply = ""
                    for try await piece in stream {
                        latestReply = piece
                        await MainActor.run {
                            self.messages[placeholderIndex].text = piece
                            self.streamingUpdateCount += 1
                        }
                    }
                    return latestReply
                }
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 75 * 1_000_000_000)
                    streamTask.cancel()
                }
                do {
                    cleanResponse = try await streamTask.value
                } catch is CancellationError {
                    timeoutTask.cancel()
                    throw NSError(domain: "Chat", code: -1, userInfo: [NSLocalizedDescriptionKey: "応答がタイムアウトしました"])
                }
                timeoutTask.cancel()
                if messages.indices.contains(placeholderIndex) {
                    messages.remove(at: placeholderIndex)
                }
                #endif

                let responseLatency = Date().timeIntervalSince(responseStart)
                let normalized = normalizeUnexpectedReplyStyle(cleanResponse, buddy: buddy)
                let evaluation = normalized.hasUnexpectedDialect
                    ? (needs: true, reason: "unexpected-dialect")
                    : evaluateFallbackNeed(normalized.text, userMessage: userMessage)
                // 締めモード中（明確な終了意思が連続）は疑問符付きフォールバックを避ける
                let closingMode = consecutiveShortReplies >= 2
                let fallbackReply = buildConversationFallbackReply(
                    for: userMessage,
                    buddy: buddy,
                    preferQuestion: Self.shouldPreferQuestionFallback(reason: evaluation.reason),
                    closingMode: closingMode
                )
                let duplicateDetected = isDuplicateResponse(normalized.text)
                let needsFallback = evaluation.needs || duplicateDetected
                let finalReply = needsFallback ? fallbackReply : normalized.text
                #if DEBUG
                print("[Chat] 生LLM応答(\(cleanResponse.count)文字): \(cleanResponse)")
                #endif
                if normalized.changed {
                    ProbeLogger.log(ProbeChannel.chat, "task=chat.reply postprocess=normalized_unexpected_style")
                }
                ProbeLogger.block(ProbeChannel.chat, title: "task=chat.reply output.cleaned", text: normalized.text)
                if evaluation.needs {
                    #if DEBUG
                    print("[Chat] フォールバック発火 reason=\(evaluation.reason ?? "unknown") → \(fallbackReply)")
                    #endif
                }
                if duplicateDetected {
                    #if DEBUG
                    print("[Chat] 重複検出 → フォールバック: \(fallbackReply)")
                    #endif
                }
                #if DEBUG
                print("[Chat] 応答時間(テキスト)=\(String(format: "%.2f", responseLatency))s")
                #endif
                ProbeLogger.block(ProbeChannel.chat, title: "task=chat.reply output.final", text: finalReply)
                ProbeLogger.log(
                    ProbeChannel.chat,
                    "task=chat.reply fallback_used=\(needsFallback) fallback_reason=\(evaluation.reason ?? (duplicateDetected ? "duplicate" : "none")) duplicate=\(duplicateDetected) latency_s=\(String(format: "%.2f", responseLatency))"
                )
                addMessage(text: finalReply, isFromBuddy: true)
                trackBuddyQuestionStatus(finalReply)
                maybeSuggestDiaryOnClosing(userMessage: userMessage, buddyReply: finalReply)
            }
        } catch {
            isLoadingVision = false
            #if DEBUG
            print("[Chat] エラー: \(error)")
            #endif
            let fallbackReply = buildConversationFallbackReply(for: userMessage, buddy: buddy)
            ProbeLogger.log(ProbeChannel.chat, "task=\(imageData == nil ? "chat.reply" : "chat.imageReply") error=\(error) fallback_used=true")
            ProbeLogger.block(
                ProbeChannel.chat,
                title: "task=\(imageData == nil ? "chat.reply" : "chat.imageReply") output.final",
                text: fallbackReply
            )
            addMessage(text: fallbackReply, isFromBuddy: true)
        }

        isTyping = false
    }

    private func makeChatResponseRequest(
        buddy: BuddyProfile,
        userMessage: String,
        memoryContext: String,
        isImageFollowUp: Bool = false
    ) -> ChatResponseService.Request {
        let firstUserMessage = messages.first { !$0.isFromBuddy }
        let elapsedMinutes = firstUserMessage.map { Int(Date().timeIntervalSince($0.timestamp) / 60) } ?? 0

        let history: [(role: String, content: String)] = Array(messages.dropLast().suffix(6)).map { msg in
            (role: msg.isFromBuddy ? "model" : "user", content: msg.text)
        }

        return ChatResponseService.Request(
            buddy: buddy,
            userNickname: userNickname,
            userTimezone: userTimezone,
            turnCount: turnCount,
            lowSignalReplyStreak: consecutiveLowSignalReplies,
            elapsedMinutes: elapsedMinutes,
            memoryContext: memoryContext,
            history: history,
            userMessage: userMessage,
            language: AppLanguageMode.currentResolved,
            isImageFollowUp: isImageFollowUp
        )
    }

    /// LLM 応答が「真に壊れている」ケースだけを検出するガード。
    /// 以前は sentenceCount < 2 や単語一致の謝罪もフォールバック対象にしていたが、
    /// (1) persona が要求する 1 文の尖った応答（「ふん、出かけるのね！」等）まで一律置換
    /// (2) buildConversationFallbackReply が enum ベース固定文で、
    ///     しかも .cool ブランチが「内容は把握できた」という禁止口調そのもの
    /// の 2 点が重なり、カスタム人格がチャット応答に一切反映されない事故が起きていた。
    /// 現在は「空」「極端に短い」「テンプレトークン漏洩」「完全に言語化拒否テンプレ」のみを拾う。
    /// 戻り値の tuple は診断ログ用に「trigger 理由」を同時に返す。
    private func evaluateFallbackNeed(_ text: String, userMessage: String) -> (needs: Bool, reason: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (true, "empty") }
        if trimmed.contains("<|") || trimmed.contains("<turn|>") { return (true, "template-token-leak") }
        if trimmed.count < 4 { return (true, "too-short(<4chars)") }

        // 「言語化できなかった」系の完全な拒否応答のみを弾く。
        // 「ごめん」単体は persona 応答の中に自然に現れ得るため対象外。
        let refusalPhrases = [
            "うまく言葉が出なかった",
            "うまく言葉がまとまらなかった"
        ]
        if refusalPhrases.contains(where: { trimmed.contains($0) }) {
            return (true, "refusal-template")
        }
        if looksLikeParrotedReply(trimmed, userMessage: userMessage) {
            return (true, "parroted-user-message")
        }
        if Self.isLowSignalReply(userMessage), turnCount <= 3, !Self.containsQuestion(trimmed), trimmed.count <= 12 {
            return (true, "weak-low-signal-early")
        }
        if Self.isCorrectionReply(userMessage), Self.looksLikeAdvisoryReply(trimmed) {
            return (true, "bad-correction-advice")
        }
        return (false, nil)
    }

    private func normalizeUnexpectedReplyStyle(_ text: String, buddy: BuddyProfile) -> (text: String, changed: Bool, hasUnexpectedDialect: Bool) {
        guard !buddy.seed.requestsExplicitDialect else {
            return (text, false, false)
        }

        var normalized = text
        let leadingFillers = ["そうか、", "そっか、", "なるほど、"]
        for filler in leadingFillers where normalized.hasPrefix(filler) {
            normalized = String(normalized.dropFirst(filler.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let replacements: [(from: String, to: String)] = [
            ("無理はせんといてな", "無理はしないでね"),
            ("無理はせんといて", "無理はしないで"),
            ("休もか", "休もうか"),
            ("聞いたる", "聞くよ"),
            ("話したる", "話すよ"),
            ("聞かせてや", "聞かせてよ"),
            ("ええよ", "いいよ"),
            ("ええね", "いいね"),
            ("ええやろ", "いいでしょ"),
            ("ちゃう", "違う"),
            ("どうやった？", "どうだった？"),
            ("どうやったん？", "どうだったの？"),
            ("何があったん？", "何があったの？"),
            ("やったん？", "だったの？"),
            ("やった？", "だった？"),
            ("やろ？", "だよね？"),
            ("やろ。", "だよね。"),
            ("やろ", "だよね"),
            ("やん", "じゃん"),
        ]
        for replacement in replacements {
            normalized = normalized.replacingOccurrences(of: replacement.from, with: replacement.to)
        }

        normalized = normalized
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            normalized,
            normalized != text,
            Self.containsUnexpectedDialect(normalized)
        )
    }

    private static func containsUnexpectedDialect(_ text: String) -> Bool {
        let strongMarkers = [
            "せんといて", "聞いたる", "話したる", "言うて", "休もか",
            "やったん", "どうやった", "何があったん？", "ええやろ"
        ]
        if strongMarkers.contains(where: { text.contains($0) }) {
            return true
        }
        let regexes = [
            #"やろ[。！？?]?$"#,
            #"やん[。！？?]?$"#,
            #"ちゃう[。！？?]?$"#
        ]
        for pattern in regexes {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// 会話終了シグナルとなる明確な応答を判定する。
    /// exact 一致、接頭辞一致（≤10字）、フラグメント包含の3段で日本語の変化形を広くカバーする。
    /// 二重否定（「ないわけじゃない」等）は dismissive としない。
    /// テスト可視性のため internal。
    static func isDismissiveReply(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 二重否定・留保表現は dismissive から除外（「ない」を含んでも意図は肯定）
        let doubleNegationMarkers = [
            "わけじゃない", "わけでもない", "ことはない", "こともない",
            "とは言えない", "とも言えない", "とは限らない",
            "ないわけ", "ないでもない",
        ]
        if doubleNegationMarkers.contains(where: { trimmed.contains($0) }) {
            return false
        }

        let lowered = trimmed.lowercased()

        // exact 一致（変化形を網羅）
        let exactDismissive = [
            // 否定
            "ない", "無い", "なし", "ねー", "ねぇ", "ねえ",
            "ないや", "ないって", "ないよ", "ないな", "ないね",
            "ないかな", "ないっす", "ないわ", "ないで", "なーい",
            "ないもん", "ないのよ", "ないぞ", "ないぜ",
            // 特に系
            "特にない", "特になし", "特になーい", "べつに", "別に",
            "何もない", "なにもない", "格別なし",
            // 諦め・終了
            "もういい", "もうええ", "もうよか", "もうないよ", "もう無い",
            "結構", "以上", "ここまで", "もう十分", "十分", "勘弁",
            // 疲労
            "疲れた", "つかれた", "しんどい", "眠い", "ねむい",
            "だるい", "寝る", "おしまい", "そろそろ",
            // 締め挨拶
            "また明日", "おやすみ", "ありがとう", "バイバイ",
            "じゃあね", "またね", "バイバーイ",
            // 思い出せない
            "思いつかない", "浮かばない", "忘れた", "思い出せない",
            "no", "nah",
        ]
        if exactDismissive.contains(where: { lowered == $0.lowercased() }) {
            return true
        }

        // 接頭辞一致 + 長さガード（≤10字で揺れ吸収。
        // 12字だと「ないから〜」の後に substantive な続きが来る可能性があり
        // false positive リスクが上がるため 10字で締める）
        if trimmed.count <= 10 {
            let prefixes = [
                "ない", "無い", "なし", "ねー", "ねぇ",
                "もういい", "もうない", "もう無い", "もう十分",
                "特に", "思いつか", "浮かば",
                "眠", "疲れ", "しんど",
            ]
            if prefixes.contains(where: { trimmed.hasPrefix($0) }) {
                return true
            }
        }

        // フラグメント包含
        // 「もういい」は「もういいじゃん、次行こう」のような話題転換でも誤検知するため fragment から除外。
        // exact / prefix でカバー済み。
        let dismissiveFragments = [
            "話したくない", "終わり",
            "眠いからやめる", "ここまで",
            "話すことない", "話すことが無い", "他にはない", "他には無い",
            "もう話すこと", "また明日",
        ]
        return dismissiveFragments.contains(where: { trimmed.contains($0) })
    }

    /// 会話の締めサジェストをユーザー側から消す（×ボタン／作成ボタン押下時）。
    func dismissDiarySuggestion() {
        shouldSuggestDiary = false
    }

    /// 締めサジェスト Toast から日記作成を起動する。
    func acceptDiarySuggestion() {
        shouldSuggestDiary = false
        if canTriggerDiaryCompilation {
            triggerDiaryFromIconTap()
        }
    }

    private static let userClosingSignals: [String] = [
        "また明日", "おやすみ", "もういい", "今日はここまで", "そろそろ寝る",
        "ありがとう", "バイバイ", "じゃあね", "もう寝る"
    ]

    private static let buddyClosingSignals: [String] = [
        "また明日", "おつかれ", "お疲れさま", "お疲れ様", "ゆっくり休んで",
        "おやすみ", "今日もお疲れさま"
    ]

    /// ユーザー／バディの発話から会話の締めを検知する。
    /// バディ側の発話が疑問符で終わる場合は、バディ側の締めシグナルだけを無効化する。
    /// ユーザー側の締めシグナル（ありがとう/おやすみ等）はバディの疑問符に関係なく通す。
    private static func detectClosing(userMessage: String, buddyReply: String) -> Bool {
        let userHit = userClosingSignals.contains { userMessage.contains($0) }
        if userHit { return true }
        let trimmedBuddy = buddyReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBuddy.hasSuffix("？") || trimmedBuddy.hasSuffix("?") {
            return false
        }
        return buddyClosingSignals.contains { buddyReply.contains($0) }
    }

    /// 会話量があり、まだサジェストしておらず、締めの合図が出ていれば Toast を予約する。
    /// `force = true` の場合は `detectClosing` チェックをバイパスして強制表示する
    /// （強制締め経路用: `closingLine` が closing signal を含まない archetype でも必ず表示したい）
    private func maybeSuggestDiaryOnClosing(userMessage: String, buddyReply: String, force: Bool = false) {
        guard !hasSuggestedDiaryThisSession else { return }
        guard !shouldSuggestDiary else { return }
        // 会話量の最低ライン。オンボ直後の 1〜2 ターンで締めが出てもサジェストしない。
        guard turnCount >= 3 else { return }
        // 日記作成ができない状態（作成中や 0 ターン）ではサジェストしない。
        guard canTriggerDiaryCompilation else { return }
        if !force {
            guard Self.detectClosing(userMessage: userMessage, buddyReply: buddyReply) else { return }
        }
        hasSuggestedDiaryThisSession = true
        shouldSuggestDiary = true
        ProbeLogger.log(
            ProbeChannel.chat,
            "task=chat.closingSuggest trigger=true turnCount=\(turnCount) force=\(force)"
        )
    }

    /// バディ応答が「？」で終わっているかを追跡する。
    /// 質問で終わらない応答が続いていれば、バディも会話を締めに向かっていると判定する。
    private func trackBuddyQuestionStatus(_ buddyReply: String) {
        let trimmed = buddyReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("？") || trimmed.hasSuffix("?") {
            consecutiveNonQuestionBuddyReplies = 0
        } else {
            consecutiveNonQuestionBuddyReplies += 1
        }
    }

    private func needsFallbackResponse(_ text: String) -> Bool {
        evaluateFallbackNeed(text, userMessage: "").needs
    }

    /// 直近のバディ応答と同一の応答（ループ）を検出する。
    /// 2Bモデルが完全に同じ文を繰り返した場合のみフォールバックへ切り替える。
    /// 句読点・末尾記号の違いは吸収するが、内容の差は尊重する（書き出しが似ているだけの別内容は通す）。
    private func isDuplicateResponse(_ text: String) -> Bool {
        let normalize: (String) -> String = { s in
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。！!？?、 　"))
        }
        let target = normalize(text)
        guard !target.isEmpty else { return false }
        // 直近2件のバディ発話のみチェック（ループは連続して発生する）
        let recentBuddyTexts = messages.filter(\.isFromBuddy).suffix(2)
        return recentBuddyTexts.contains { normalize($0.text) == target }
    }

    /// フォールバック返答は事前生成プール (`BuddyProfile.fallbackReplies`) から
    /// ランダムに 1 件選んで返す。これにより「ランタイムで抽出したテンプレ文」が
    /// 一瞬だけ人格とズレて表示される事故を防ぐ。
    /// プールが空（生成失敗時や旧データ）の場合のみ、汎用の短い事実質問を最終安全網として返す。
    private func buildConversationFallbackReply(
        for userMessage: String,
        buddy: BuddyProfile,
        preferQuestion: Bool = false,
        closingMode: Bool = false
    ) -> String {
        // 締めモード中は疑問符を含む通常フォールバックを使うと「他には？」ループが断ち切れない。
        // PersonaLineComposer.closingLine（archetype 別の決定的な締め文）を返す。
        if closingMode {
            if AppLanguageMode.currentResolved == .english {
                return AppText.current.englishClosingFallback
            }
            let composer = PersonaLineComposer(displayName: buddy.displayName, seed: buddy.seed)
            let closing = composer.closingLine(nickname: userNickname)
            // 保険: closing が疑問符で終わっていればねぎらい定型に差し替え
            if Self.containsQuestion(closing) {
                return "今日もおつかれさま。"
            }
            return closing
        }
        let savedReplies = buddy.fallbackReplies.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if preferQuestion {
            if let pick = savedReplies.first(where: Self.containsQuestion) {
                return pick
            }
        } else if let pick = savedReplies.randomElement() {
            return pick
        }
        let composer = PersonaLineComposer(displayName: buddy.displayName, seed: buddy.seed)
        let generated = composer.fallbackReplies()
        if preferQuestion {
            return generated.first(where: Self.containsQuestion)
                ?? generated.first
                ?? (AppLanguageMode.currentResolved == .english ? AppText.current.englishFallbackQuestion : "今日は何をしてたの？")
        }
        return generated.first ?? (AppLanguageMode.currentResolved == .english ? AppText.current.englishFallbackQuestion : "今日は何をしてたの？")
    }

    private func looksLikeParrotedReply(_ reply: String, userMessage: String) -> Bool {
        let normalizedReply = Self.normalizeComparisonText(reply)
        let normalizedUser = Self.normalizeComparisonText(userMessage)
        guard normalizedReply.count >= 5, normalizedUser.count >= 5 else { return false }
        guard !Self.containsQuestion(reply) else { return false }

        let overlap = Self.bigramOverlap(lhs: normalizedReply, rhs: normalizedUser)
        let commonSubstring = Self.longestCommonSubstringLength(lhs: normalizedReply, rhs: normalizedUser)
        let similarLength = normalizedReply.count <= normalizedUser.count + 8
        let reflectiveEnding = ["んだね", "だったね", "だね", "かな", "だったかな", "ですね"]
            .contains { normalizedReply.hasSuffix($0) }

        if commonSubstring >= 4 && overlap >= 0.48 && similarLength {
            return true
        }
        if reflectiveEnding && overlap >= 0.36 && similarLength {
            return true
        }
        return false
    }

    private static func normalizeComparisonText(_ text: String) -> String {
        var normalized = text
            .lowercased()
            .replacingOccurrences(of: "お仕事", with: "仕事")
            .replacingOccurrences(of: "そうか、", with: "")
            .replacingOccurrences(of: "そっか、", with: "")
            .replacingOccurrences(of: "なるほど、", with: "")
            .replacingOccurrences(of: "今日は", with: "")
            .replacingOccurrences(of: "だよ", with: "")
            .replacingOccurrences(of: "ね", with: "")
            .replacingOccurrences(of: "よ", with: "")
        normalized = normalized.replacingOccurrences(
            of: #"[\s、。！？!?,「」『』\[\]（）\(\)ー〜]"#,
            with: "",
            options: .regularExpression
        )
        return normalized
    }

    private static func bigramOverlap(lhs: String, rhs: String) -> Double {
        let left = bigrams(from: lhs)
        let right = bigrams(from: rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        return Double(intersection) / Double(min(left.count, right.count))
    }

    private static func bigrams(from text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        var result = Set<String>()
        for index in 0..<(chars.count - 1) {
            result.insert(String(chars[index...index + 1]))
        }
        return result
    }

    private static func longestCommonSubstringLength(lhs: String, rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        var table = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        var best = 0
        for i in 1...left.count {
            for j in 1...right.count where left[i - 1] == right[j - 1] {
                table[i][j] = table[i - 1][j - 1] + 1
                best = max(best, table[i][j])
            }
        }
        return best
    }

    private static func containsQuestion(_ text: String) -> Bool {
        text.contains("?") || text.contains("？")
    }

    /// 「うん」「はい」など、情報量は少ないが終了意思とは限らない返答。
    /// 1回だけで会話を閉じず、連続した場合のみプロンプトを少し控えめにする。
    static func isLowSignalReply(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let lowSignal = [
            "うん", "はい", "そう", "そうだよ", "そうだね", "そっか",
            "かな", "かも", "まあね", "たしかに", "そうそう",
            "うーん", "わかった", "了解", "大丈夫"
        ]
        if lowSignal.contains(where: { lowered == $0.lowercased() }) {
            return true
        }
        return trimmed.count <= 4 && !isDismissiveReply(trimmed)
    }

    private static func isCorrectionReply(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["いや", "違う", "ちがう", "そうじゃなく", "そんなことない", "そうでもない", "だって", "別に", "いやいや"]
        return markers.contains(where: { trimmed.contains($0) })
    }

    private static func looksLikeAdvisoryReply(_ text: String) -> Bool {
        let markers = ["方がいい", "したほうが", "すべき", "しないで", "ちゃんと", "したらいい", "するといい"]
        return markers.contains(where: { text.contains($0) })
    }

    private static func shouldPreferQuestionFallback(reason: String?) -> Bool {
        guard let reason else { return false }
        return reason == "parroted-user-message" || reason == "weak-low-signal-early"
    }

    @discardableResult
    private func addMessage(text: String, isFromBuddy: Bool, image: UIImage? = nil, imageData: Data? = nil) -> UUID {
        let displayMsg = DisplayMessage(
            text: text,
            isFromBuddy: isFromBuddy,
            timestamp: Date(),
            image: image
        )
        messages.append(displayMsg)

        // SwiftDataにも保存
        var savedId = displayMsg.id
        if let session = session, let modelContext = modelContext {
            let chatMsg = ChatMessage(text: text, isFromBuddy: isFromBuddy, imageData: imageData)
            chatMsg.session = session
            session.messages.append(chatMsg)
            session.messageCount += 1
            try? modelContext.save()
            savedId = chatMsg.id
        }
        return savedId
    }

    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxSize else { return image }

        let scale = maxSize / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func handleImageAnalysisUnavailable() {
        addMessage(
            text: AppText.current.imageUnavailableReply,
            isFromBuddy: true
        )
    }

    private func handleDiaryCompilationEvent(_ event: DiaryCompilationCoordinator.Event) {
        switch event {
        case .started:
            break
        case .succeeded(_):
            if pendingDiaryPresentationAfterCompile {
                isShowingDiaryLoadingModal = false
                if journalResult != nil || existingJournalEntry != nil {
                    diaryPresentationTick &+= 1
                }
                pendingDiaryPresentationAfterCompile = false
            } else {
                isShowingDiaryLoadingModal = false
            }
        case .failed(_), .cancelled:
            isShowingDiaryLoadingModal = false
            pendingDiaryPresentationAfterCompile = false
        }
    }
}

private extension ChatViewModel {
    static func todayJournalFlagKey(for date: Date = Date()) -> String {
        let startOfDay = DayBoundary.startOfAppDay(for: date).timeIntervalSince1970
        return "home.todayJournalCreated.\(Int(startOfDay))"
    }
}
