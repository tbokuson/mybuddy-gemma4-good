import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var buddyName: String = ""
    @Published var userNickname: String = ""
    @Published var isProcessing = false

    // オンボーディング会話
    @Published var chatMessages: [ChatDisplayMessage] = []
    @Published var chatInputText: String = ""
    @Published var isTyping = false
    @Published var turnCount: Int = 0
    @Published var isOnboardingComplete = false
    @Published var streamingUpdateCount: Int = 0
    @Published var isExtracting = false

    // セクション制御
    @Published var currentSection: OnboardingSection = .nickname
    private var isNicknameConfirmed = false
    private var nicknameConfirmedAtTurn = 0
    private var sectionStartIndex: Int = 0
    private var sectionTurnCount: Int = 0
    /// セクション内で最後に「内容のある」ユーザー発言（純粋な確認「うん」「そう」等ではないもの）。
    /// 確定時に userMessage が純粋な確認だった場合、この値を custom として採用する。
    private var sectionLastSubstantiveInput: String = ""
    private let maxSectionTurns = 8
    /// 固定文言表示前のタイピング遅延（ミリ秒）。テスト時は短く設定可能。
    var typingDelayMilliseconds: UInt64 = 500
    /// 1 文字あたりのストリーミング表示遅延（ミリ秒）。LLM のストリーミング速度（約30〜50文字/秒）に合わせ既定 30ms。
    /// テスト時は `typingDelayMilliseconds` を低く設定すると、こちらも比例して短縮される。
    var perCharTypingDelayMilliseconds: UInt64 {
        // 既定 (500) → 30ms、テスト (10) → 1ms 程度になるよう線形スケーリング
        max(1, min(30, typingDelayMilliseconds / 16))
    }

    // 各軸の確定値
    private var confirmedPersonaEnum: PersonaStyle?
    private var confirmedPersonaCustom: String = ""
    private var confirmedDistanceEnum: ConversationDistance?
    private var confirmedDistanceCustom: String = ""
    private var confirmedDiaryEnum: MemoryPreference?
    private var confirmedDiaryCustom: String = ""
    private var confirmedCustomTraits: String = ""

    /// 「姿を見る」ボタン表示条件:
    /// オンボーディング未完了、ニックネーム確定済み、全セクション完了
    var showConfirmButton: Bool {
        !isOnboardingComplete && isNicknameConfirmed && currentSection == .done
    }

    // 見た目タイプ選択
    @Published var monsterSeed: BuddySeed?
    @Published var ojisanSeed: BuddySeed?
    @Published var monsterCandidates: [BuddySeed] = []
    @Published var ojisanCandidates: [BuddySeed] = []
    @Published var appearanceRevealed = false

    // お披露目
    @Published var generatedSeed: BuddySeed?
    @Published var revealAnimationDone = false
    @Published var revealGreeting: String = ""
    @Published var generatedFallbackReplies: [String] = []
    @Published var generatedHeroSubtitleFresh: String = ""
    @Published var generatedHeroSubtitleResume: String = ""
    @Published var generatedFirstDayGreeting: String = ""

    private var session: ConversationSession?
    private var llmService: (any LLMServiceProtocol)?
    private var modelContext: ModelContext?

    /// 意図分類器（キーワードマッチ方式、将来 LLM ベースに差し替え可能）
    var intentClassifier: OnboardingIntentClassifier = KeywordIntentClassifier()

    struct ChatDisplayMessage: Identifiable {
        let id = UUID()
        var text: String
        let isFromBuddy: Bool
    }

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case privacy
        case naming
        case waitingForLLM
        case chat
        case choosingAppearance
        case extracting
        case reveal
        case complete
    }

    enum OnboardingSection: Int, CaseIterable {
        case nickname
        case persona
        case distance
        case diaryStyle
        case customTraits
        case done

        var next: OnboardingSection? {
            OnboardingSection(rawValue: rawValue + 1)
        }

        var defaultEnumLabel: String {
            if OnboardingViewModel.usesEnglish {
                switch self {
                case .persona: return "gentle and reassuring"
                case .distance: return "casual, like a friend"
                case .diaryStyle: return "natural and event-focused"
                default: return ""
                }
            }
            switch self {
            case .persona: return "やさしい雰囲気"
            case .distance: return "友達みたいに気軽な感じ"
            case .diaryStyle: return "できごと中心に自然に残す形"
            default: return ""
            }
        }
    }

    var canEndChat: Bool { !isTyping && showConfirmButton }

    // MARK: - 固定メッセージ定数

    private static var usesEnglish: Bool {
        AppLanguageMode.currentResolved == .english
    }

    private static func personaQuestion(buddyName: String) -> String {
        if usesEnglish {
            return "What kind of buddy should \(buddyName) be? Gentle, cool, bright, relaxed, or anything you like."
        }
        return "\(buddyName)はどんなキャラがいいかな？やさしい、クール、元気とか、なんでもいいよ！"
    }
    private static var distanceQuestion: String {
        if usesEnglish {
            return "How close should the conversation feel? Casual like a friend, quietly supportive, direct, or playful. No preference is fine too."
        }
        return "会話の距離感はどうする？友達みたいに気楽に接するとか、そっと寄り添うとか、率直に物申すとか！特に指定をしなくてもいいよ！"
    }

    private static var diaryStyleQuestion: String {
        if usesEnglish {
            return "How should your diary be written? Short and simple, event-focused, or with a little attention to feelings. No preference is fine."
        }
        return "日記はどう残したい？できごと中心、シンプルにとか、気持ちも少し残す感じ、などなど。これも特に指定がなくても大丈夫！"
    }

    private static func customTraitsQuestion(buddyName: String) -> String {
        if usesEnglish {
            return "Anything else you want \(buddyName) to do? Tone, catchphrases, habits, or dialect. If not, just say \"none.\""
        }
        return "最後に、他に\(buddyName)にお願いある？語尾、方言、話し方のクセとか！なければ「なし」で大丈夫！"
    }

    /// おまかせ/なんでもいい時に、デフォルトの選択を明示する固定メッセージ
    private static func nullishConfirmMessage(for section: OnboardingSection) -> String {
        if usesEnglish {
            switch section {
            case .persona:
                return "Then I'll keep it gentle."
            case .distance:
                return "Okay, casual like a friend."
            case .diaryStyle:
                return "Got it, natural and event-focused."
            case .customTraits:
                return "Got it, no special rules."
            default:
                return "Got it."
            }
        }
        switch section {
        case .persona:
            return "そしたら、やさしい感じにするね！"
        case .distance:
            return "じゃあ、友達みたいに気軽な感じでいくね！"
        case .diaryStyle:
            return "オッケー、できごと中心に自然に残していくね！"
        case .customTraits:
            return "了解、特になしで進めるね！"
        default:
            return "了解！"
        }
    }

    private static var postDoneReplies: [String] {
        if usesEnglish {
            return [
                "Thanks. I'll remember that.",
                "Got it.",
                "Nice. I'm looking forward to it.",
                "Okay.",
            ]
        }
        return [
            "ありがとう！覚えておくね",
            "了解！",
            "いいね！楽しみだな〜",
            "わかった！",
        ]
    }

    private enum SectionResponsePlan {
        case nullish(display: String)
        case `continue`(display: String)
        case confirm(display: String, sourceInput: String)
    }

    private func safetyValveMessage(for section: OnboardingSection) -> String {
        if Self.usesEnglish {
            switch section {
            case .persona:
                return "This seems tricky, so I'll keep it gentle for now."
            case .distance:
                return "Then I'll keep it casual, like a friend."
            case .diaryStyle:
                return "I'll keep your diary natural and event-focused."
            case .customTraits:
                return "I'll continue without special rules."
            default:
                return "Let's keep going."
            }
        }
        switch section {
        case .persona:
            return "ごめんね、ちょっと難しそうだから、今回はやさしい雰囲気で進めるね！"
        case .distance:
            return "うん、じゃあ友達みたいに気軽な感じにしておくね！"
        case .diaryStyle:
            return "じゃあ、できごと中心に自然に残す形にしておくね！"
        case .customTraits:
            return "特になしで進めるね！"
        default:
            return "じゃあこのまま進めるね！"
        }
    }

    // MARK: - Actions

    func configure(llmService: any LLMServiceProtocol, modelContext: ModelContext) {
        self.llmService = llmService
        self.modelContext = modelContext
    }

    func nextStep() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nextIndex
        }
    }

    func proceedAfterNaming() {
        let trimmedName = UserInputSanitizer.sanitize(buddyName, policy: .buddyName)
        guard !trimmedName.isEmpty else { return }
        buddyName = trimmedName

        guard let llmService = llmService else { return }

        if llmService.isLoaded {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = .chat
            }
            startOnboardingChat()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = .waitingForLLM
            }
        }
    }

    func onLLMReady() {
        guard currentStep == .waitingForLLM else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .chat
        }
        startOnboardingChat()
    }

    // MARK: - Onboarding Chat

    private func startOnboardingChat() {
        guard let modelContext = modelContext else { return }

        let newSession = ConversationSession(type: .onboarding)
        modelContext.insert(newSession)
        try? modelContext.save()
        self.session = newSession
        currentSection = .nickname

        #if DEBUG
        print("[Onboarding] 会話開始: buddyName=\(buddyName)")
        #endif

        Task {
            let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
            let greeting: String
            if Self.usesEnglish {
                greeting = "Nice to meet you. I'm \(name).\nLet's make your diary together.\nFirst, what should I call you? A nickname or your real name is fine."
            } else {
                greeting = "はじめまして！\(name)だよ。よろしくね！\nこれから一緒に日記を作っていこう！\nまず教えてほしいんだけど、君のこと、なんて呼んだらいい？ニックネームでも本名でも、好きな呼び方で大丈夫だよ"
            }
            await showMessageWithTypingDelay(greeting)
        }
    }

    // MARK: - メッセージ送信ルーター

    func sendChatMessage() {
        let text = UserInputSanitizer.sanitize(chatInputText, policy: .onboardingMessage)
        guard !text.isEmpty, !isTyping else { return }

        chatInputText = ""
        addChatMessage(text: text, isFromBuddy: false)
        turnCount += 1
        isTyping = true

        #if DEBUG
        print("[Onboarding] ユーザー入力(\(currentSection), turn=\(turnCount)): \(text)")
        #endif

        switch currentSection {
        case .nickname:
            handleNicknameInput(text)
        case .persona, .distance, .diaryStyle, .customTraits:
            Task { await handleSectionInput(text) }
        case .done:
            Task { await handlePostDoneInput(text) }
        }
    }

    // MARK: - ニックネーム処理

    private func handleNicknameInput(_ text: String) {
        if !isNicknameConfirmed && nicknameConfirmedAtTurn == 0 && turnCount == 1 {
            // 最初の返答 → LLMでニックネーム抽出し、確認を聞く
            Task {
                let extracted = await extractNicknameWithLLM(from: text)
                userNickname = extracted
                #if DEBUG
                print("[Onboarding] LLMニックネーム抽出: 入力「\(text)」→「\(extracted)」")
                #endif

                let nick = UserInputSanitizer.sanitize(extracted.isEmpty ? text : extracted, policy: .nickname)
                let message = Self.usesEnglish ? "Can I call you \(nick)?" : "\(nick)って呼んでいい？"
                await showMessageWithTypingDelay(message)
            }
        } else if !isNicknameConfirmed {
            // 確認への返答
            if isPositiveResponse(text) {
                isNicknameConfirmed = true
                nicknameConfirmedAtTurn = turnCount
                #if DEBUG
                print("[Onboarding] ニックネーム確定: \(userNickname)")
                #endif
                transitionToPersona()
            } else {
                // 否定/別の名前 → LLMで再抽出して再確認
                Task {
                    let extracted = await extractNicknameWithLLM(from: text)
                    userNickname = extracted
                    let nick = UserInputSanitizer.sanitize(extracted.isEmpty ? text : extracted, policy: .nickname)
                    let message = Self.usesEnglish ? "So, \(nick). Can I call you \(nick)?" : "\(nick)だね！\(nick)って呼んでいい？"
                    await showMessageWithTypingDelay(message)
                }
            }
        }
    }

    private func transitionToPersona() {
        currentSection = .persona
        sectionTurnCount = 0
        sectionLastSubstantiveInput = ""
        #if DEBUG
        print("[Onboarding] セクション遷移: nickname → persona")
        #endif

        Task {
            let nick = userNickname.isEmpty ? (Self.usesEnglish ? "you" : "きみ") : userNickname
            let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
            let message = Self.usesEnglish
                ? "Great, I'll call you \(nick).\n\(Self.personaQuestion(buddyName: name))"
                : "じゃあ\(nick)って呼ぶね！\n\(Self.personaQuestion(buddyName: name))"
            await showMessageWithTypingDelay(message)
            sectionStartIndex = chatMessages.count
            // 固定メッセージ表示中にLLMウォームアップ
            await warmupLLM()
        }
    }

    // MARK: - セクション入力処理（persona/distance/diaryStyle/customTraits 共通）

    private func handleSectionInput(_ text: String) async {
        // 不同意チェック: セクション遷移直後に「ちがう」等 → 前セクションに戻る
        if sectionTurnCount == 0 && Self.isDisagreement(text) {
            if let prevSection = revertToPreviousSection() {
                #if DEBUG
                print("[Onboarding] 不同意検出: \(currentSection) → \(prevSection) に戻る")
                #endif
                let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
                let question = sectionQuestionText(for: prevSection, buddyName: name)
                let message = Self.usesEnglish ? "Sorry, tell me again.\n\(question)" : "ごめんね！もう一回教えて！\n\(question)"
                await showMessageWithTypingDelay(message)
                sectionStartIndex = chatMessages.count
                return
            }
        }

        sectionTurnCount += 1

        // 「うん」「そう」等の純粋な確認以外の入力を substantive として記憶。
        // LLMの聞き返しに「うん」で答えた後の確定で、「うん」が custom に入るのを防ぐ。
        if !Self.isPureConfirmation(text) {
            sectionLastSubstantiveInput = text
        }

        // 安全弁: セクション内ターン上限
        if sectionTurnCount >= maxSectionTurns {
            #if DEBUG
            print("[Onboarding] 安全弁発動: \(currentSection) ターン数=\(sectionTurnCount)")
            #endif
            await applySafetyValve(for: currentSection)
            return
        }

        await generateSectionResponse(userMessage: text)
    }

    /// 「うん」「そう」「はい」等、内容のない純粋な確認（相槌）かどうか判定する。
    /// 8文字以内で確認フレーズと完全一致した場合のみ true。
    /// 「うん、ツンデレで」のような substantive を含む確認は false（末尾の句読点は除去して判定）。
    static func isPureConfirmation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！!？?、.,〜~ー"))
        guard trimmed.count <= 8, !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let patterns: [String] = [
            "うん", "うんうん", "ああ", "はい", "そう", "そうそう", "そうだね", "そだね",
            "そうです", "だね", "それで", "おk", "ok", "オッケー", "オーケー",
            "yes", "yeah", "yep", "yup",
            "いいよ", "いい", "わかった", "分かった", "了解",
        ]
        return patterns.contains { lowered == $0.lowercased() }
    }

    /// 不同意ワードかどうか判定する
    static func isDisagreement(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered == "no" || lowered == "nope" {
            return true
        }
        let patterns = ["ちがう", "違う", "そうじゃない", "それは違", "ちがくて", "ちゃう", "not that", "that's not", "different"]
        return patterns.contains { lowered.hasPrefix($0.lowercased()) || lowered.contains($0.lowercased()) }
    }

    /// 前セクションに戻し、確定値をクリアする。戻ったセクションを返す。
    private func revertToPreviousSection() -> OnboardingSection? {
        switch currentSection {
        case .distance:
            confirmedPersonaCustom = ""
            confirmedPersonaEnum = .gentle
            currentSection = .persona
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""
            return .persona
        case .diaryStyle:
            confirmedDistanceCustom = ""
            confirmedDistanceEnum = .casual
            currentSection = .distance
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""
            return .distance
        case .customTraits:
            confirmedDiaryCustom = ""
            confirmedDiaryEnum = .balanced
            currentSection = .diaryStyle
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""
            return .diaryStyle
        case .done:
            confirmedCustomTraits = ""
            currentSection = .customTraits
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""
            return .customTraits
        default:
            return nil
        }
    }

    /// セクションの質問テキストを返す
    private func sectionQuestionText(for section: OnboardingSection, buddyName: String) -> String {
        switch section {
        case .persona: return Self.personaQuestion(buddyName: buddyName)
        case .distance: return Self.distanceQuestion
        case .diaryStyle: return Self.diaryStyleQuestion
        case .customTraits: return Self.customTraitsQuestion(buddyName: buddyName)
        default: return ""
        }
    }

    /// ハイブリッド方式: 判定は拡張キーワードマッチ（裏）、応答は LLM ストリーミング（表）。
    /// customTraits のみ LLM 自由応答 + 「わからない」判定で落選扱い。
    /// LLM が失敗したら固定テンプレートにフォールバック。
    private func generateSectionResponse(userMessage: String) async {
        let section = currentSection
        let probeTag = "onboarding.\(String(describing: section))"
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName

        ProbeLogger.log(
            ProbeChannel.onboarding,
            "task=\(probeTag) turn=\(turnCount) section_turn=\(sectionTurnCount) user=\(ProbeLogger.inline(userMessage))"
        )

        let placeholderIndex = chatMessages.count
        chatMessages.append(ChatDisplayMessage(text: "", isFromBuddy: true))

        // customTraits は別ロジック（LLM 自由応答）
        if section == .customTraits {
            await handleCustomTraitsInput(userMessage: userMessage, placeholderIndex: placeholderIndex, probeTag: probeTag)
            isTyping = false
            return
        }

        // 3セクション共通: まず決定的なキーワード判定、unknown のときだけ LLM 補助分類を使う。
        let keywordIntent = intentClassifier.classify(userMessage, section: section)
        let intent: OnboardingIntent
        if keywordIntent == .unknown {
            intent = await classifySectionWithLLM(
                userMessage: userMessage,
                section: section,
                probeTag: "\(probeTag).classify"
            )
        } else {
            intent = keywordIntent
        }

        #if DEBUG
        print("[Onboarding] 判定(\(section)): \(intent)")
        #endif

        switch intent {
        case .enumMatched(let enumValue):
            let customText = Self.cleanUserInput(userMessage)
            let storedCustomText = Self.normalizedStoredCustomText(
                for: section,
                text: customText,
                enumValue: enumValue
            )
            // LLM で受け止め文を生成（失敗時は固定テンプレート）
            let buddyReply = await generateLLMReply(
                prompt: OnboardingPromptBuilder.matchedConfirmationPrompt(
                    buddyName: name,
                    section: section,
                    userInput: userMessage
                ),
                placeholderIndex: placeholderIndex,
                fallback: Self.sectionEnumConfirmationMessage(for: section, enumValue: enumValue),
                probeTag: probeTag
            )
            let prevSection = section
            let nextQuestion = saveSectionConfirmedValues((
                enumValue: enumValue,
                customText: storedCustomText,
                isNullish: false
            ))
            saveOnboardingBuddyMessage(buddyReply)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=hybrid decision=matched enum=\(enumValue) custom=\(ProbeLogger.inline(storedCustomText)) next_section=\(String(describing: currentSection))"
            )
            #if DEBUG
            print("[Onboarding] マッチ確定: \(prevSection) → \(currentSection) enum=\(enumValue)")
            #endif
            advanceSectionUI(cleaned: buddyReply, nextQuestion: nextQuestion, placeholderIndex: placeholderIndex)

        case .nullish:
            let buddyReply = await generateLLMReply(
                prompt: OnboardingPromptBuilder.nullishPrompt(buddyName: name, section: section),
                placeholderIndex: placeholderIndex,
                fallback: Self.nullishConfirmMessage(for: section),
                probeTag: probeTag
            )
            let prevSection = section
            let nextQuestion = saveSectionConfirmedValues((enumValue: nil, customText: "", isNullish: true))
            saveOnboardingBuddyMessage(buddyReply)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=hybrid decision=nullish next_section=\(String(describing: currentSection))"
            )
            #if DEBUG
            print("[Onboarding] おまかせ確定: \(prevSection) → \(currentSection)")
            #endif
            advanceSectionUI(cleaned: buddyReply, nextQuestion: nextQuestion, placeholderIndex: placeholderIndex)

        case .unknown:
            // LLM で聞き返し文を生成（同セクション継続）
            let buddyReply = await generateLLMReply(
                prompt: OnboardingPromptBuilder.unknownClarifyPrompt(
                    buddyName: name,
                    section: section,
                    userInput: userMessage
                ),
                placeholderIndex: placeholderIndex,
                fallback: Self.sectionFollowUpMessage(for: section, buddyName: name),
                probeTag: probeTag
            )
            saveOnboardingBuddyMessage(buddyReply)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=hybrid decision=unknown section_turn=\(sectionTurnCount)"
            )
            #if DEBUG
            print("[Onboarding] 会話継続(unknown): \(buddyReply)")
            #endif
        }

        isTyping = false
    }

    private func classifySectionWithLLM(
        userMessage: String,
        section: OnboardingSection,
        probeTag: String
    ) async -> OnboardingIntent {
        guard let llmService = llmService, llmService.isLoaded else {
            return .unknown
        }

        let prompts = OnboardingPromptBuilder.sectionClassificationPrompt(section: section, userInput: userMessage)
        let builtPrompt = Gemma4PromptBuilder.buildSingleTurn(
            system: prompts.system,
            user: prompts.user
        )

        do {
            let response = try await llmService.generate(
                prompt: builtPrompt,
                maxTokens: 8,
                samplingProfile: .extraction,
                probeTag: probeTag
            )
            let parsed = OnboardingPromptBuilder.parseSectionClassification(response, section: section)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=llm raw=\(ProbeLogger.inline(response)) parsed=\(String(describing: parsed))"
            )
            guard let enumValue = parsed else { return .unknown }
            return .enumMatched(enumValue)
        } catch {
            #if DEBUG
            print("[Onboarding] セクション分類エラー: \(error)")
            #endif
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=llm error=\(error) parsed=unknown"
            )
            return .unknown
        }
    }

    /// customTraits セクションの処理: nullish チェック → Y/N 分類 → 応答生成
    ///
    /// 判定は3層:
    ///   層1: 入力に trait-indicator キーワードを含めば LLM 呼ばずに Y 確定（速くて堅牢）
    ///   層2: LLM 分類器（Y/N 1トークン, extraction プロファイル）で判定
    ///   層3: Y 通過後の応答が誤って「わからない」系なら落選扱いに上書き（保険）
    private func handleCustomTraitsInput(userMessage: String, placeholderIndex: Int, probeTag: String) async {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName

        // nullish チェック（「ない」「特にない」「おまかせ」等）
        if OnboardingKeywords.containsAny(userMessage, keywords: OnboardingKeywords.nullish) {
            let buddyReply = await generateLLMReply(
                prompt: OnboardingPromptBuilder.nullishPrompt(buddyName: name, section: .customTraits),
                placeholderIndex: placeholderIndex,
                fallback: Self.nullishConfirmMessage(for: .customTraits),
                probeTag: probeTag
            )
            let nextQuestion = saveSectionConfirmedValues((enumValue: nil, customText: "", isNullish: true))
            saveOnboardingBuddyMessage(buddyReply)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=hybrid decision=nullish(customTraits)"
            )
            advanceSectionUI(cleaned: buddyReply, nextQuestion: nextQuestion, placeholderIndex: placeholderIndex)
            return
        }

        // Y/N 判定（層1: ショートカット → 層2: LLM 分類器）
        let shortcutHit = OnboardingKeywords.containsAny(userMessage, keywords: OnboardingKeywords.traitIndicators)
        let isUnderstood: Bool
        if shortcutHit {
            isUnderstood = true
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag).classify strategy=shortcut verdict=Y"
            )
            #if DEBUG
            print("[Onboarding] customTraits ショートカット判定=Y (trait-indicator hit)")
            #endif
        } else {
            isUnderstood = await classifyCustomTraitsWithLLM(userMessage: userMessage, probeTag: probeTag)
        }

        if !isUnderstood {
            // N 判定 → 聞き返し文を LLM に生成させる
            let buddyReply = await generateLLMReply(
                prompt: OnboardingPromptBuilder.unknownClarifyPrompt(
                    buddyName: name,
                    section: .customTraits,
                    userInput: userMessage
                ),
                placeholderIndex: placeholderIndex,
                fallback: Self.usesEnglish
                    ? "Sorry, I didn't quite get that. For example, say \"use a gentle tone\" or \"add a catchphrase.\""
                    : "ごめん、ちょっとわからなかった。例えば「語尾ににゃ」「関西弁で」みたいな感じで教えて。",
                probeTag: probeTag
            )
            saveOnboardingBuddyMessage(buddyReply)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(probeTag) strategy=hybrid decision=unknown(customTraits) section_turn=\(sectionTurnCount)"
            )
            #if DEBUG
            print("[Onboarding] customTraits 落選（分類器N）: \(buddyReply)")
            #endif
            return
        }

        // Y 判定 → 楽しげ応答を LLM に生成させる
        let buddyReply = await generateLLMReply(
            prompt: OnboardingPromptBuilder.customTraitsFreeResponsePrompt(buddyName: name, userInput: userMessage),
            placeholderIndex: placeholderIndex,
            fallback: Self.usesEnglish
                ? "Got it, I'll include \(Self.cleanUserInput(userMessage))."
                : "了解、\(Self.formatTraitConfirmation(Self.cleanUserInput(userMessage)))。",
            probeTag: probeTag
        )

        // 層3 保険: 応答が「わからない」系なら落選扱いに上書き
        // ただし shortcut 判定が Y のときは入力自体が明確な要望なので、応答が悪くても進める。
        // この場合は楽しげ応答を fallback テンプレートで差し替える。
        let finalBuddyReply: String
        if OnboardingPromptBuilder.isUnknownResponse(buddyReply) {
            if shortcutHit {
                finalBuddyReply = Self.usesEnglish
                    ? "Got it, I'll include \(Self.cleanUserInput(userMessage))."
                    : "了解、\(Self.formatTraitConfirmation(Self.cleanUserInput(userMessage)))。"
                #if DEBUG
                print("[Onboarding] customTraits 応答層3で fallback 差し替え（shortcut Y のため進行）: \(buddyReply) → \(finalBuddyReply)")
                #endif
            } else {
                saveOnboardingBuddyMessage(buddyReply)
                ProbeLogger.log(
                    ProbeChannel.onboarding,
                    "task=\(probeTag) strategy=hybrid decision=unknown(customTraits,layer3) section_turn=\(sectionTurnCount)"
                )
                #if DEBUG
                print("[Onboarding] customTraits 落選（応答層3保険）: \(buddyReply)")
                #endif
                return
            }
        } else {
            finalBuddyReply = buddyReply
        }

        // 理解できた → custom 保存して完了
        let customText = Self.cleanUserInput(userMessage)
        let nextQuestion = saveSectionConfirmedValues((
            enumValue: nil,
            customText: customText,
            isNullish: false
        ))
        saveOnboardingBuddyMessage(finalBuddyReply)
        ProbeLogger.log(
            ProbeChannel.onboarding,
            "task=\(probeTag) strategy=hybrid decision=customConfirmed custom=\(ProbeLogger.inline(customText))"
        )
        advanceSectionUI(cleaned: finalBuddyReply, nextQuestion: nextQuestion, placeholderIndex: placeholderIndex)
    }

    /// customTraits 入力を LLM Y/N 分類器で判定する。
    /// Y = 意味が通じる（通過）, N = 意味が通じない（落選）。
    /// LLM 呼び出し失敗や不在時は曖昧を通す方針で Y を返す。
    private func classifyCustomTraitsWithLLM(userMessage: String, probeTag: String) async -> Bool {
        guard let llmService = llmService, llmService.isLoaded else {
            return true
        }
        let prompts = OnboardingPromptBuilder.customTraitsClassificationPrompt(userInput: userMessage)
        let builtPrompt = Gemma4PromptBuilder.buildSingleTurn(
            system: prompts.system,
            user: prompts.user
        )
        let classifyTag = "\(probeTag).classify"
        do {
            let response = try await llmService.generate(
                prompt: builtPrompt,
                maxTokens: 4,
                samplingProfile: .extraction,
                probeTag: classifyTag
            )
            let verdict = OnboardingPromptBuilder.parseCustomTraitsClassification(response)
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(classifyTag) strategy=llm verdict=\(verdict ? "Y" : "N") raw=\(ProbeLogger.inline(response))"
            )
            #if DEBUG
            print("[Onboarding] customTraits LLM 分類=\(verdict ? "Y" : "N") raw=\(response)")
            #endif
            return verdict
        } catch {
            #if DEBUG
            print("[Onboarding] customTraits 分類器エラー: \(error)")
            #endif
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=\(classifyTag) strategy=llm error=\(error) verdict_fallback=Y"
            )
            return true
        }
    }

    /// LLM にプロンプトを送って応答を生成し、placeholder バブルにストリーミング表示する
    /// 失敗時は fallback テキストを表示
    private func generateLLMReply(
        prompt: (system: String, user: String),
        placeholderIndex: Int,
        fallback: String,
        probeTag: String
    ) async -> String {
        guard let llmService = llmService, llmService.isLoaded else {
            chatMessages[placeholderIndex].text = fallback
            return fallback
        }

        let builtPrompt = Gemma4PromptBuilder.buildSingleTurn(
            system: prompt.system,
            user: prompt.user
        )

        ProbeLogger.block(ProbeChannel.onboarding, title: "task=\(probeTag) prompt.system", text: prompt.system)

        do {
            let stream = llmService.generateStream(
                prompt: builtPrompt,
                maxTokens: 64,
                samplingProfile: .chat,
                probeTag: probeTag
            )
            var rawText = ""
            for try await piece in stream {
                rawText += piece
                let displayText = LLMOutputSanitizer.cleanup(rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !displayText.isEmpty {
                    chatMessages[placeholderIndex].text = displayText
                    streamingUpdateCount += 1
                }
            }
            let cleaned = LLMOutputSanitizer.cleanup(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                chatMessages[placeholderIndex].text = fallback
                return fallback
            }
            ProbeLogger.block(ProbeChannel.onboarding, title: "task=\(probeTag) output.final", text: cleaned)
            return cleaned
        } catch {
            #if DEBUG
            print("[Onboarding] LLM エラー: \(error). フォールバック使用")
            #endif
            chatMessages[placeholderIndex].text = fallback
            return fallback
        }
    }

    // MARK: - セクション遷移UI

    /// セクション確定後のバブル統合・遷移処理
    /// LLM 応答は既に placeholderIndex に表示済み。
    /// 次の質問文を1文字ずつストリーミング風に追記する。
    private func advanceSectionUI(cleaned: String, nextQuestion: String?, placeholderIndex: Int) {
        if let question = nextQuestion {
            // 次セクションの履歴にはこの統合バブルを含めない（前セクション内容の混入防止）
            sectionStartIndex = chatMessages.count
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""
            // LLM 受け止め文に続けて、固定質問文を1文字ずつ追記（ストリーミング風）
            Task { @MainActor in
                await streamAppend(question: "\n" + question, placeholderIndex: placeholderIndex)
            }
        } else {
            // 全セクション完了 → 締めメッセージを1文字ずつ追記
            Task { @MainActor in
                await streamAppend(
                    question: Self.usesEnglish ? "\nI'm excited for you to meet me." : "\n楽しみにしてて！",
                    placeholderIndex: placeholderIndex
                )
                #if DEBUG
                print("[Onboarding] 全セクション完了、ボタン表示")
                #endif
            }
        }
    }

    /// 固定文字列を placeholderIndex のバブルに1文字ずつ追記する（ストリーミング風表示）
    private func streamAppend(question text: String, placeholderIndex: Int) async {
        guard placeholderIndex < chatMessages.count else { return }
        if typingDelayMilliseconds <= 50 {
            // テスト/高速モード: 一括追記
            chatMessages[placeholderIndex].text += text
            streamingUpdateCount += 1
            return
        }
        for char in text {
            guard placeholderIndex < chatMessages.count else { return }
            chatMessages[placeholderIndex].text += String(char)
            streamingUpdateCount += 1
            try? await Task.sleep(for: .milliseconds(perCharTypingDelayMilliseconds))
        }
    }

    // MARK: - LLM応答のサニタイズ（表示用）

    /// LLM応答がゴミ（バディ名だけ、プロンプト復唱、ハルシネーション等）ならフォールバック表示に差し替え
    static func sanitizeSectionResponse(_ response: String, buddyName: String, userMessage: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // ゴミ応答の検出
        let garbagePatterns = [
            "タメ口", "敬語禁止", "質問禁止", "1文だけ", "1文で",
            "標準語", "受け止めて", "フランク", "楽しそうに", "カジュアル",
            "ユーザー", "返事する", "返事します", "返事して", "友達として",
            "システム", "プロンプト", "**",
        ]

        let isGarbage =
            trimmed.isEmpty ||
            trimmed.count <= 3 ||
            trimmed == buddyName ||
            trimmed == "\(buddyName)。" ||
            garbagePatterns.contains(where: { trimmed.contains($0) }) ||
            trimmed.count > 50

        if isGarbage {
            return buildEchoFallback(userMessage)
        }
        return trimmed
    }

    /// sanitize時のフォールバック — ユーザーの言葉を使った自然な応答を生成
    static func buildEchoFallback(_ userMessage: String) -> String {
        let cleaned = cleanUserInput(userMessage)
        if cleaned.isEmpty || isNullishAnswer(userMessage) {
            return usesEnglish ? "Okay." : "おっけー！"
        }
        if cleaned.count <= 12 {
            if usesEnglish {
                return "\(cleaned). Got it."
            }
            return "\(cleaned)ね！"
        }
        return usesEnglish ? "Okay." : "おっけー！"
    }

    // MARK: - ユーザー入力のクリーンアップ（custom値用）

    /// ユーザーの入力を軽くクリーンアップしてcustom値として使う
    static func cleanUserInput(_ input: String) -> String {
        var text = UserInputSanitizer.sanitize(input, policy: .customTraits)
        // 末尾の句読点・記号を除去
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "。！!？?、"))
        // 末尾の「で」「に」「を」「が」（ぶら下がり助詞）を除去
        let danglingParticles = ["でお願い", "にして", "がいい", "かな", "かも", "で"]
        for p in danglingParticles {
            if text.hasSuffix(p) && text.count > p.count + 2 {
                text = String(text.dropLast(p.count))
                break
            }
        }
        return UserInputSanitizer.sanitize(text, policy: .customTraits)
    }

    // MARK: - custom値抽出（LLM応答テキストからプログラムで要点を抜き出す、後方互換用）

    /// LLMの確認応答から語尾・接頭辞・バディ名を除去してcustom値を抽出する
    static func extractCustomFromResponse(_ response: String, buddyName: String) -> String {
        var text = response
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 「」で括られた値 + 直後が確認フレーズの場合、括弧内を優先抽出
        // 例: "モモの好みを「やさしい感じ」で確認しました。" → "やさしい感じ"
        // 例: "語尾に「にゃ」をつけるんだね！" → 括弧後が確認フレーズでないのでスキップ
        if let openRange = text.range(of: "「"),
           let closeRange = text.range(of: "」", range: openRange.upperBound..<text.endIndex) {
            let quoted = String(text[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let afterQuote = String(text[closeRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let confirmPhrases = ["で確認", "を確認", "って確認", "確認"]
            if quoted.count >= 2 && confirmPhrases.contains(where: { afterQuote.hasPrefix($0) }) {
                return quoted
            }
        }

        // バディ名を除去
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
        text = text.replacingOccurrences(of: name, with: "")

        // 接頭辞を除去（長いものから優先）
        let leadingPatterns = [
            "つまり、", "つまり ", "なるほど、", "なるほど ",
            "そっか、", "そっか ", "そうか、", "そうか ",
            "あー、", "うん、", "へぇ、", "おっ、", "おー、",
            "えーっと、", "えっと、", "わかった、", "わかった ",
            "おっけー、", "おっけー ", "オッケー、", "オッケー ",
        ]
        for pattern in leadingPatterns {
            if text.hasPrefix(pattern) {
                text = String(text.dropFirst(pattern.count))
                break
            }
        }

        // 2Bモデル特有の確認文パターンを除去（文全体が「〜確認した」等の場合、要点だけ残す）
        // 例: "ドS女王様キャラで確認した。" → "ドS女王様キャラ"
        // 例: "やさしい感じ、確認したよ。" → "やさしい感じ"
        let confirmSuffixes = [
            "って確認したね。", "って確認した。", "を確認した。", "で確認した。",
            "って確認したね", "って確認した", "を確認した", "で確認した",
            // 敬語形（2Bモデルが指示に反して敬語を使う場合がある）
            "で確認しました。", "を確認しました。", "って確認しました。",
            "で確認しました", "を確認しました", "って確認しました",
            "確認しました。", "確認しました",
            "、確認したよ。", "、確認したね。", "、確認した。",
            "、確認したよ", "、確認したね", "、確認した",
            "確認したよ。", "確認したね。", "確認した。",
            "確認したよ", "確認したね", "確認した",
            "確認するよ。", "確認するね。", "確認する。",
            "確認するよ", "確認するね", "確認する",
        ]
        for suffix in confirmSuffixes {
            if text.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count))
                break
            }
        }

        // 2Bモデル特有: 前置き文を除去（「〜の好みを教えてくれてありがとう。」等）
        let sentenceSeparators = ["。", "！", "! "]
        for sep in sentenceSeparators {
            if let range = text.range(of: sep) {
                let afterSep = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterSep.isEmpty && afterSep.count >= 2 {
                    // 後半に要点がある場合は後半を採用
                    text = afterSep
                }
            }
        }

        // 末尾の句読点・感嘆符を除去（語尾パターンマッチの前に実行）
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "。！!？?"))

        // 語尾パターンを除去（長いものから優先マッチ）
        let trailingPatterns = [
            "にしたいってことだね", "って感じだね", "な感じだね", "ってことだね",
            "にしたいんだね", "にするんだね", "で話すんだね", "のことだね", "で残すんだね",
            "って言ってくれてるね", "って言ってくれてる",
            "って意味だね", "って意味だ",
            "で返すね", "で返す", "と返すね", "と返す",
            "がいいんだね", "がいい",
            "、了解", "、わかった", "了解", "わかった",
            "んだね", "んだよ", "だね", "だよ", "ね",
        ]
        for pattern in trailingPatterns {
            if text.hasSuffix(pattern) {
                text = String(text.dropLast(pattern.count))
                break
            }
        }

        // 末尾の助詞・接続詞を除去（ただし内容が短くなりすぎる場合はスキップ）
        let trailingSuffixes = ["を", "と", "、"]
        for suffix in trailingSuffixes {
            if text.hasSuffix(suffix) && text.count > 4 {
                text = String(text.dropLast(suffix.count))
                break
            }
        }

        // バディ名除去後に先頭に残った助詞・句読点を除去
        // 例: "モモ、やさしい感じ" → バディ名除去 → "、やさしい感じ" → "やさしい感じ"
        while let first = text.first, "のは、。！! ".contains(first) {
            text = String(text.dropFirst(1))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - enum判定（キーワードマッチ）

    /// ユーザー発言とLLM応答からenumをキーワードマッチで判定する
    static func matchEnumForSection(_ section: OnboardingSection, text: String) -> String? {
        let lowered = text.lowercased()
        switch section {
        case .persona:
            if text.contains("クール") || text.contains("ドS") || text.contains("ツンデレ")
                || text.contains("冷たい") || text.contains("意地悪") || text.contains("毒舌")
                || text.contains("きつい") || text.contains("女王")
                || lowered.contains("cool") || lowered.contains("dry") || lowered.contains("strict") { return "cool" }
            if text.contains("元気") || text.contains("明るい") || text.contains("テンション")
                || text.contains("活発") || text.contains("にぎやか")
                || lowered.contains("bright") || lowered.contains("cheerful") || lowered.contains("energetic") { return "bright" }
            if text.contains("のんびり") || text.contains("まったり") || text.contains("ゆるい")
                || text.contains("おっとり") || text.contains("癒し")
                || lowered.contains("mellow") || lowered.contains("relaxed") || lowered.contains("chill") { return "mellow" }
            return "gentle"
        case .distance:
            if text.contains("寄り添") || text.contains("支え") || text.contains("そっと")
                || text.contains("見守")
                || lowered.contains("supportive") || lowered.contains("listen") { return "supportive" }
            if text.contains("率直") || text.contains("ストレート") || text.contains("はっきり")
                || text.contains("遠慮なく") || text.contains("ズバズバ")
                || text.contains("素直") || text.contains("正直")
                || lowered.contains("frank") || lowered.contains("direct") || lowered.contains("honest") { return "frank" }
            if text.contains("ツンデレ") || text.contains("いたずら") || text.contains("ふざけ")
                || text.contains("からかう")
                || lowered.contains("playful") || lowered.contains("joke") || lowered.contains("tease") { return "playful" }
            return "casual"
        case .diaryStyle:
            if text.contains("シンプル") || text.contains("簡潔") || text.contains("あっさり")
                || lowered.contains("short") || lowered.contains("simple") || lowered.contains("compact") { return "compact" }
            if text.contains("気持ち") || text.contains("感情") || text.contains("心")
                || text.contains("内面")
                || lowered.contains("feeling") || lowered.contains("emotion") || lowered.contains("mood") { return "feelingAware" }
            return "balanced"
        default:
            return nil
        }
    }

    // MARK: - セクション確定処理

    /// 確定値を保存し、次セクションへ遷移する。次のセクションの質問テキストを返す（.done なら nil）。
    private func saveSectionConfirmedValues(_ result: (enumValue: String?, customText: String, isNullish: Bool)) -> String? {
        let isNullish = result.isNullish
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName

        switch currentSection {
        case .persona:
            if isNullish {
                confirmedPersonaEnum = .gentle
                confirmedPersonaCustom = ""
            } else {
                confirmedPersonaCustom = UserInputSanitizer.sanitize(result.customText, policy: .customTraits)
                confirmedPersonaEnum = PersonaStyle(rawValue: result.enumValue ?? "") ?? .gentle
            }
            currentSection = .distance
            return Self.distanceQuestion

        case .distance:
            if isNullish {
                confirmedDistanceEnum = .casual
                confirmedDistanceCustom = ""
            } else {
                confirmedDistanceCustom = UserInputSanitizer.sanitize(result.customText, policy: .customTraits)
                confirmedDistanceEnum = ConversationDistance(rawValue: result.enumValue ?? "") ?? .casual
            }
            currentSection = .diaryStyle
            return Self.diaryStyleQuestion

        case .diaryStyle:
            if isNullish {
                confirmedDiaryEnum = .balanced
                confirmedDiaryCustom = ""
            } else {
                confirmedDiaryCustom = UserInputSanitizer.sanitize(result.customText, policy: .customTraits)
                confirmedDiaryEnum = MemoryPreference(rawValue: result.enumValue ?? "") ?? .balanced
            }
            currentSection = .customTraits
            return Self.customTraitsQuestion(buddyName: name)

        case .customTraits:
            if isNullish {
                confirmedCustomTraits = ""
            } else {
                confirmedCustomTraits = UserInputSanitizer.sanitize(result.customText, policy: .customTraits)
            }
            currentSection = .done
            return nil

        default:
            return nil
        }
    }

    /// 安全弁: セクション内ターン上限到達時、デフォルト値で次セクションへ進む
    private func applySafetyValve(for section: OnboardingSection) async {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName

        switch section {
        case .persona:
            confirmedPersonaEnum = .gentle
            confirmedPersonaCustom = ""
        case .distance:
            confirmedDistanceEnum = .casual
            confirmedDistanceCustom = ""
        case .diaryStyle:
            confirmedDiaryEnum = .balanced
            confirmedDiaryCustom = ""
        case .customTraits:
            confirmedCustomTraits = ""
        default:
            break
        }

        // 安全弁メッセージ + 次の質問を1バブルに統合
        let safetyMsg = safetyValveMessage(for: section)
        if let next = section.next {
            #if DEBUG
            print("[Onboarding] 安全弁: \(section) → \(next) デフォルト値適用")
            #endif
            currentSection = next
            sectionTurnCount = 0
            sectionLastSubstantiveInput = ""

            let nextQuestion = nextSectionQuestion(for: next, buddyName: name)
            if let question = nextQuestion {
                await showMessageWithTypingDelay(safetyMsg + "\n" + question)
                sectionStartIndex = chatMessages.count
            } else {
                // done → 締めメッセージのみ
                await showMessageWithTypingDelay(safetyMsg)
                #if DEBUG
                print("[Onboarding] 全セクション完了（安全弁経由）、ボタン表示")
                #endif
            }
        }

        isTyping = false
    }

    /// セクションの質問テキストを返す（.done なら nil）
    private func nextSectionQuestion(for section: OnboardingSection, buddyName: String) -> String? {
        switch section {
        case .persona: return Self.personaQuestion(buddyName: buddyName)
        case .distance: return Self.distanceQuestion
        case .diaryStyle: return Self.diaryStyleQuestion
        case .customTraits: return Self.customTraitsQuestion(buddyName: buddyName)
        default: return nil
        }
    }

    // MARK: - done 後の追加チャット

    private func handlePostDoneInput(_ text: String) async {
        let reply = Self.postDoneReplies.randomElement()!
        await showMessageWithTypingDelay(reply)
    }

    // MARK: - セクション専用システムプロンプト

    private func buildSectionSystemPrompt(for section: OnboardingSection, buddyName: String) -> String {
        if Self.usesEnglish {
            let base = """
            You are "\(buddyName)".
            You are only confirming onboarding preferences. Reply in 1-2 short sentences.
            If the user's preference is clear, acknowledge it briefly. Ask at most one question only when it is unclear.
            Do not explain the setup, repeat the instructions, or say meta phrases like "I am configuring".
            """
            switch section {
            case .persona:
                return base + "\nThe target preference is \(buddyName)'s personality or vibe. Accept clear preferences as stated."
            case .distance:
                return base + "\nThe target preference is conversation distance: closeness, tone, or style of interaction."
            case .diaryStyle:
                return base + "\nThe target preference is diary style: short, simple, event-focused, feeling-aware, and similar preferences."
            case .customTraits:
                return base + "\nThe target preference is extra speech habits or traits. Do not perform a requested dialect or catchphrase yet."
            default:
                return ""
            }
        }
        let base = """
        あなたは「\(buddyName)」。
        今は設定確認だけをする。返答は1〜2文。
        明確なら短く受け止めて終える。曖昧なときだけ質問は1問まで。
        説明・復唱・状況説明・「承知しました」「〜を決めている」などのメタ発話は禁止。
        """
        switch section {
        case .persona:
            return base + "\n確認対象は「\(buddyName)のキャラや雰囲気」。指定があればそのまま採用する。"
        case .distance:
            return base + "\n確認対象は会話の距離感。キャラ設定ではなく、話す近さやノリとして解釈する。"
        case .diaryStyle:
            return base + "\n確認対象は日記の残し方。短く、シンプル、できごと中心、気持ちも残す、などの好みとして解釈する。"
        case .customTraits:
            return base + "\n確認対象は追加の話し方やクセ。この返答の中ではまだ指定された方言や語尾を実演しない。"
        default:
            return ""
        }
    }

    private func buildSectionResponsePlan(
        for section: OnboardingSection,
        userMessage: String,
        buddyName: String
    ) -> SectionResponsePlan {
        if Self.isNullishAnswer(userMessage) {
            return .nullish(display: Self.nullishConfirmMessage(for: section))
        }

        if Self.isPureConfirmation(userMessage) {
            if !sectionLastSubstantiveInput.isEmpty {
                let source = sectionLastSubstantiveInput
                return .confirm(
                    display: Self.sectionConfirmationMessage(for: section, sourceInput: source),
                    sourceInput: source
                )
            }
            return .continue(display: Self.sectionFollowUpMessage(for: section, buddyName: buddyName))
        }

        let cleaned = Self.cleanUserInput(userMessage)
        guard !cleaned.isEmpty else {
            return .continue(display: Self.sectionFollowUpMessage(for: section, buddyName: buddyName))
        }
        if Self.looksLikeLowSignalInput(cleaned, section: section) {
            return .continue(display: Self.sectionFollowUpMessage(for: section, buddyName: buddyName))
        }

        if section == .distance && Self.needsDistanceClarification(cleaned) {
            return .continue(display: Self.distanceClarificationMessage())
        }

        return .confirm(
            display: Self.sectionConfirmationMessage(for: section, sourceInput: cleaned),
            sourceInput: cleaned
        )
    }

    private static func sectionConfirmationMessage(
        for section: OnboardingSection,
        sourceInput: String,
        enumValue: String? = nil,
        storedCustomText: String = ""
    ) -> String {
        let cleaned = cleanUserInput(sourceInput)
        if storedCustomText.isEmpty, let enumValue {
            return sectionEnumConfirmationMessage(for: section, enumValue: enumValue)
        }
        if usesEnglish {
            switch section {
            case .persona:
                return "Nice, I'll keep it \(cleaned)."
            case .distance:
                return "Got it, I'll talk in a \(cleaned) way."
            case .diaryStyle:
                return "Got it, I'll write diaries \(cleaned)."
            case .customTraits:
                return "Got it, I'll include \(cleaned)."
            default:
                return "Got it."
            }
        }
        switch section {
        case .persona:
            return "いいね、\(cleaned)でいくね。"
        case .distance:
            return "わかった、\(formatDistanceConfirmation(cleaned))。"
        case .diaryStyle:
            return "了解、日記は\(formatDiaryConfirmation(cleaned))。"
        case .customTraits:
            return "了解、\(formatTraitConfirmation(cleaned))。"
        default:
            return "了解！"
        }
    }

    private static func sectionEnumConfirmationMessage(for section: OnboardingSection, enumValue: String) -> String {
        if usesEnglish {
            switch section {
            case .persona:
                switch PersonaStyle(rawValue: enumValue) ?? .gentle {
                case .gentle: return "Nice, I'll keep it gentle."
                case .cool: return "Nice, I'll keep it cool."
                case .bright: return "Nice, I'll keep it bright."
                case .mellow: return "Nice, I'll keep it relaxed."
                }
            case .distance:
                switch ConversationDistance(rawValue: enumValue) ?? .casual {
                case .supportive: return "Got it, I'll stay quietly supportive."
                case .casual: return "Got it, I'll keep it casual."
                case .frank: return "Got it, I'll be direct."
                case .playful: return "Got it, I'll keep it playful."
                }
            case .diaryStyle:
                switch MemoryPreference(rawValue: enumValue) ?? .balanced {
                case .compact: return "Got it, I'll keep diaries short."
                case .balanced: return "Got it, I'll focus on what happened."
                case .feelingAware: return "Got it, I'll include feelings too."
                }
            case .customTraits, .done, .nickname:
                return "Got it."
            }
        }
        switch section {
        case .persona:
            switch PersonaStyle(rawValue: enumValue) ?? .gentle {
            case .gentle: return "いいね、やさしい感じでいくね。"
            case .cool: return "いいね、クールな感じでいくね。"
            case .bright: return "いいね、明るい感じでいくね。"
            case .mellow: return "いいね、のんびりした感じでいくね。"
            }
        case .distance:
            switch ConversationDistance(rawValue: enumValue) ?? .casual {
            case .supportive: return "わかった、寄り添う感じで話していくね。"
            case .casual: return "わかった、気軽な感じで話していくね。"
            case .frank: return "わかった、率直な感じで話していくね。"
            case .playful: return "わかった、少し軽やかなノリで話していくね。"
            }
        case .diaryStyle:
            switch MemoryPreference(rawValue: enumValue) ?? .balanced {
            case .compact: return "了解、日記はシンプルに残していくね。"
            case .balanced: return "了解、日記はできごと中心で残していくね。"
            case .feelingAware: return "了解、日記は気持ちも少し残していくね。"
            }
        case .customTraits, .done, .nickname:
            return "了解！"
        }
    }

    private static func normalizedStoredCustomText(
        for section: OnboardingSection,
        text: String,
        enumValue: String?
    ) -> String {
        let cleaned = cleanUserInput(text)
        guard !cleaned.isEmpty else { return "" }
        guard enumValue != nil else { return cleaned }

        switch section {
        case .distance:
            // persona と同じく raw テキストを保持する。
            // 下流の PersonaLineComposer.archetype が「ツンデレ」等を検出したり、
            // chat system prompt が距離感表現として利用する。
            return cleaned
        case .diaryStyle:
            let genericMarkers = ["シンプル", "簡潔", "短く", "あっさり", "できごと", "出来事", "気持ち", "感情"]
            if cleaned.count <= 10 && genericMarkers.contains(where: { cleaned.contains($0) }) {
                return ""
            }
            return cleaned
        case .persona:
            return cleaned
        case .customTraits:
            return cleaned
        case .done, .nickname:
            return cleaned
        }
    }

    private static func formatDistanceConfirmation(_ text: String) -> String {
        if text.hasSuffix("話して") {
            let stem = droppingSuffix("話して", from: text)
            return "\(stem)話す感じでいくね"
        }
        if text.hasSuffix("はなして") {
            let stem = droppingSuffix("はなして", from: text)
            return "\(stem)話す感じでいくね"
        }
        if text.hasSuffix("言って") {
            let stem = droppingSuffix("言って", from: text)
            return "\(stem)言う感じでいくね"
        }
        if text.hasSuffix("に") || text.hasSuffix("で") {
            return "\(text)話していくね"
        }
        return "\(text)感じで話していくね"
    }

    private static func formatDiaryConfirmation(_ text: String) -> String {
        let conciseKeywords = ["シンプル", "簡潔", "あっさり", "コンパクト"]
        if conciseKeywords.contains(where: { text == $0 }) {
            return "\(text)に残していくね"
        }
        if text.hasSuffix("に") || text.hasSuffix("で") {
            return "\(text)残していくね"
        }
        return "\(text)で残していくね"
    }

    private static func formatTraitConfirmation(_ text: String) -> String {
        if text.hasSuffix("話して") || text.hasSuffix("はなして") || text.hasSuffix("つけて") {
            return "\(text)いくね"
        }
        if text.contains("弁") || text.contains("敬語") || text.contains("タメ口") {
            return "\(text)でいくね"
        }
        if text.hasSuffix("で") {
            let stem = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(stem)も反映するね"
        }
        return "\(text)も反映するね"
    }

    private static func droppingSuffix(_ suffix: String, from text: String) -> String {
        guard text.hasSuffix(suffix) else { return text }
        let index = text.index(text.endIndex, offsetBy: -suffix.count)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sectionFollowUpMessage(for section: OnboardingSection, buddyName: String) -> String {
        if usesEnglish {
            switch section {
            case .persona:
                return "Tell me a little more about the vibe. Gentle, cool, bright, or relaxed is enough."
            case .distance:
                return "Tell me a little more about the conversation style. Casual, supportive, direct, or playful is enough."
            case .diaryStyle:
                return "Tell me a little more about the diary style. Short, event-focused, or feeling-aware is enough."
            case .customTraits:
                return "If you have an extra preference, say it in a few words. If not, \"none\" is fine."
            default:
                return sectionQuestionTextStatic(for: section, buddyName: buddyName)
            }
        }
        switch section {
        case .persona:
            return "もう少しだけ雰囲気を教えて？やさしい、クール、元気、みたいな感じでも大丈夫。"
        case .distance:
            return "話す距離感をもう少しだけ教えて？気軽、寄り添う、ズバッと率直、みたいな感じで大丈夫。"
        case .diaryStyle:
            return "日記の残し方をもう少しだけ教えて？シンプル、できごと中心、気持ちも残す、みたいな感じで大丈夫。"
        case .customTraits:
            return "追加の希望があれば、語尾や方言みたいに一言で教えて。なければ「なし」でも大丈夫。"
        default:
            return sectionQuestionTextStatic(for: section, buddyName: buddyName)
        }
    }

    private static func distanceClarificationMessage() -> String {
        if usesEnglish {
            return "I understand the personality. How should the conversation feel? Casual, supportive, or direct is enough."
        }
        return "キャラの雰囲気はわかったよ。話す距離感はどうしたい？気軽、寄り添う、ズバッと率直、みたいな感じで教えて。"
    }

    private static func needsDistanceClarification(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let personaMarkers = ["キャラ", "女王様", "ツンデレ", "ドs", "クール", "やさしい", "元気", "のんびり"]
        let distanceMarkers = ["気軽", "寄り添", "率直", "ズバ", "ユーモア", "話そう", "なんでも", "色々", "距離", "フランク"]
        return personaMarkers.contains(where: { lowered.contains($0.lowercased()) })
            && !distanceMarkers.contains(where: { lowered.contains($0.lowercased()) })
    }

    private static func looksLikeLowSignalInput(_ text: String, section: OnboardingSection) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let hesitationPrefixes = ["うーん", "うーむ", "んー", "えーと", "えっと", "うー"]
        if hesitationPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        if trimmed.range(of: #"^[A-Za-z0-9/_\-.]+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[^ぁ-んァ-ヶ一-龯A-Za-z0-9]+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[ぁ-んァ-ヶー]{8,}$"#, options: .regularExpression) != nil {
            return true
        }

        let explicitEnumKeyword: Bool = {
            switch section {
            case .persona:
                let markers = ["クール", "ドS", "ツンデレ", "冷たい", "意地悪", "毒舌", "きつい", "女王", "元気", "明るい", "テンション", "活発", "にぎやか", "のんびり", "まったり", "ゆるい", "おっとり", "癒し", "やさしい", "優しい"]
                return markers.contains(where: { trimmed.contains($0) })
            case .distance:
                let markers = ["寄り添", "支え", "見守", "率直", "ストレート", "はっきり", "ズバ", "遠慮なく", "気軽", "友達", "なんでも", "色々", "フランク", "ユーモア", "からかう", "ふざけ", "ツンデレ", "素直", "正直"]
                return markers.contains(where: { trimmed.contains($0) })
            case .diaryStyle:
                let markers = ["シンプル", "簡潔", "短く", "あっさり", "気持ち", "感情", "内面", "できごと", "出来事", "バランス"]
                return markers.contains(where: { trimmed.contains($0) })
            case .customTraits:
                let markers = ["方言", "関西弁", "東北弁", "敬語", "タメ口", "語尾", "テンション", "口癖", "話し方"]
                return markers.contains(where: { trimmed.contains($0) })
            default:
                return false
            }
        }()

        let hasJapaneseKeyword = explicitEnumKeyword
            || trimmed.contains("感じ")
            || trimmed.contains("口調")
            || trimmed.contains("方言")
            || trimmed.contains("弁")
            || trimmed.contains("語尾")
            || trimmed.contains("話")
            || trimmed.contains("日記")

        if trimmed.count <= 4 && !hasJapaneseKeyword {
            return true
        }

        let asciiLikeCount = trimmed.unicodeScalars.filter {
            $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil)
        }.count
        if asciiLikeCount >= max(4, trimmed.count / 2), !hasJapaneseKeyword {
            let englishWordCount = trimmed.split(whereSeparator: \.isWhitespace).count
            let hasEnglishPhrase = englishWordCount >= 2
                && trimmed.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
                && trimmed.count >= 8
            if hasEnglishPhrase {
                return false
            }
            return true
        }
        return false
    }

    private static func sectionQuestionTextStatic(for section: OnboardingSection, buddyName: String) -> String {
        switch section {
        case .persona: return personaQuestion(buddyName: buddyName)
        case .distance: return distanceQuestion
        case .diaryStyle: return diaryStyleQuestion
        case .customTraits: return customTraitsQuestion(buddyName: buddyName)
        default: return ""
        }
    }


    // MARK: - タイピング遅延付きメッセージ表示

    /// 固定メッセージを1.5秒のタイピングインジケータ付きで表示する
    /// 固定メッセージをストリーミング風に1文字ずつ表示する
    /// LLM ストリーミング応答と見た目を統一するため、
    /// 最初にタイピングインジケーター → 空バブル追加 → 1文字ずつ追記
    private func showMessageWithTypingDelay(_ text: String) async {
        isTyping = true
        try? await Task.sleep(for: .milliseconds(typingDelayMilliseconds))
        // 空バブルを追加してから1文字ずつ追記
        let placeholderIndex = chatMessages.count
        chatMessages.append(ChatDisplayMessage(text: "", isFromBuddy: true))
        if typingDelayMilliseconds <= 50 {
            // テスト/高速モード: 1文字ずつではなく一括追記（アニメーションなし）
            chatMessages[placeholderIndex].text = text
            streamingUpdateCount += 1
        } else {
            for char in text {
                guard placeholderIndex < chatMessages.count else { break }
                chatMessages[placeholderIndex].text += String(char)
                streamingUpdateCount += 1
                try? await Task.sleep(for: .milliseconds(perCharTypingDelayMilliseconds))
            }
        }
        // SwiftData にも保存
        if placeholderIndex < chatMessages.count {
            saveOnboardingBuddyMessage(chatMessages[placeholderIndex].text)
        }
        isTyping = false
    }

    // MARK: - チャット終了・パラメータ構築

    func endChat() {
        guard !isTyping else { return }
        #if DEBUG
        print("[Onboarding] endChat: 見た目タイプ選択へ遷移")
        #endif
        isOnboardingComplete = true
        prepareBothSeeds()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .choosingAppearance
        }
    }

    /// モンスターとおじさんの BuddySeed を両方ランダム生成する
    private func prepareBothSeeds() {
        let persona = confirmedPersonaEnum ?? .gentle
        let distance = confirmedDistanceEnum ?? .casual
        let memory = confirmedDiaryEnum ?? .balanced

        let baseMonster = BuddySeed.makeRandomMonster(
            personaStyle: persona,
            conversationDistance: distance,
            memoryPreference: memory,
            personalityNotes: "",
            customTraits: confirmedCustomTraits,
            personaStyleCustom: confirmedPersonaCustom,
            conversationDistanceCustom: confirmedDistanceCustom,
            memoryPreferenceCustom: confirmedDiaryCustom,
            roomThemeId: "room_default"
        )
        monsterCandidates = BuddyAppearanceCandidateFactory.makeCandidates(from: baseMonster)
        monsterSeed = monsterCandidates.first

        let baseOjisan = BuddySeed.makeRandomOjisan(
            personaStyle: persona,
            conversationDistance: distance,
            memoryPreference: memory,
            customTraits: confirmedCustomTraits,
            personaStyleCustom: confirmedPersonaCustom,
            conversationDistanceCustom: confirmedDistanceCustom,
            memoryPreferenceCustom: confirmedDiaryCustom
        )
        ojisanCandidates = BuddyAppearanceCandidateFactory.makeCandidates(from: baseOjisan)
        ojisanSeed = ojisanCandidates.first
    }

    /// ユーザーが見た目タイプを選択した後に呼ばれる
    func selectAppearance(isMonster: Bool) {
        if let seed = isMonster ? monsterCandidates.first ?? monsterSeed : ojisanCandidates.first ?? ojisanSeed {
            generatedSeed = seedWithConfirmedPersonality(seed)
        } else {
            generatedSeed = nil
        }
        appearanceRevealed = true

        #if DEBUG
        let type = isMonster ? "monster" : "ojisan"
        print("[Onboarding] 見た目タイプ選択: \(type), bodyId=\(generatedSeed?.bodyId ?? "?")")
        #endif
    }

    func selectAppearance(seed: BuddySeed) {
        generatedSeed = seedWithConfirmedPersonality(seed)
        appearanceRevealed = true

        #if DEBUG
        print("[Onboarding] 見た目候補選択: \(seed.characterType), bodyId=\(seed.bodyId)")
        #endif
    }

    #if DEBUG
    /// テスト用: endChat → 見た目選択 → 挨拶生成 → reveal までを一気通貫で進める
    /// 本番 UI ではユーザー操作の分岐があるためこれは使わない
    func finishOnboardingForTesting(isMonster: Bool = true, timeout: TimeInterval = 15) async {
        endChat()
        selectAppearance(isMonster: isMonster)
        proceedAfterAppearanceReveal()
        let deadline = Date().addingTimeInterval(timeout)
        while currentStep != .reveal && currentStep != .complete && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    #endif

    /// シルエット解除アニメーション完了後に呼ばれ、extracting → reveal へ進む
    func proceedAfterAppearanceReveal() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .extracting
        }
        Task {
            await buildSeedAndProceed()
        }
    }

    /// 確定済みの seed で挨拶を生成し、reveal へ進む
    private func buildSeedAndProceed() async {
        #if DEBUG
        print("[Onboarding] BuddySeed構築完了: persona='\(confirmedPersonaCustom)' distance='\(confirmedDistanceCustom)' diary='\(confirmedDiaryCustom)' traits='\(confirmedCustomTraits)'")
        #endif

        if let seed = generatedSeed {
            generatedSeed = seedWithConfirmedPersonality(seed)
        }
        await generateGreetings()
        proceedToReveal()
    }

    private func seedWithConfirmedPersonality(_ seed: BuddySeed) -> BuddySeed {
        var updated = seed
        updated.personaStyle = confirmedPersonaEnum ?? updated.personaStyle
        updated.conversationDistance = confirmedDistanceEnum ?? updated.conversationDistance
        updated.memoryPreference = confirmedDiaryEnum ?? updated.memoryPreference
        updated.customTraits = confirmedCustomTraits
        updated.personaStyleCustom = confirmedPersonaCustom
        updated.conversationDistanceCustom = confirmedDistanceCustom
        updated.memoryPreferenceCustom = confirmedDiaryCustom
        return updated
    }

    // MARK: - ニックネーム抽出（変更なし）

    private func extractNicknameWithLLM(from text: String) async -> String {
        guard let llmService = llmService, llmService.isLoaded else {
            return parseNicknameFallback(from: text)
        }

        let prompt = Gemma4PromptBuilder.buildSingleTurn(
            system: "ユーザーの発言からニックネーム（呼び名）だけを抽出してください。名前のみを出力。他の文字は一切不要。",
            user: "「\(text)」この発言からニックネームだけを抜き出して。名前のみ出力。"
        )

        do {
            let response = try await llmService.generate(
                prompt: prompt,
                maxTokens: 16,
                samplingProfile: .extraction,
                probeTag: "onboarding.nicknameExtraction"
            )
            let cleaned = response
                .replacingOccurrences(of: "<turn|>", with: "")
                .replacingOccurrences(of: "<|turn>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "「」『』\""))

            let safeCleaned = UserInputSanitizer.sanitize(cleaned, policy: .nickname)
            if safeCleaned.isEmpty || safeCleaned.count > UserInputSanitizer.Policy.nickname.maxLength {
                #if DEBUG
                print("[Onboarding] LLMニックネーム抽出失敗、フォールバック: \(cleaned)")
                #endif
                ProbeLogger.log(
                    ProbeChannel.onboarding,
                    "task=onboarding.nicknameExtraction input=\(ProbeLogger.inline(text)) extracted=\(ProbeLogger.inline(safeCleaned)) fallback_used=true"
                )
                return parseNicknameFallback(from: text)
            }
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=onboarding.nicknameExtraction input=\(ProbeLogger.inline(text)) extracted=\(ProbeLogger.inline(safeCleaned)) fallback_used=false"
            )
            return safeCleaned
        } catch {
            #if DEBUG
            print("[Onboarding] LLMニックネーム抽出エラー: \(error)")
            #endif
            ProbeLogger.log(
                ProbeChannel.onboarding,
                "task=onboarding.nicknameExtraction input=\(ProbeLogger.inline(text)) error=\(error) fallback_used=true"
            )
            return parseNicknameFallback(from: text)
        }
    }

    private func parseNicknameFallback(from text: String) -> String {
        let trimmed = UserInputSanitizer.sanitize(text, policy: .nickname)
        let suffixPatterns = ["って呼んでください", "って呼んで", "と呼んでください", "と呼んで", "でお願い", "ですよ", "です", "だよ", "かな", "で"]
        var name = trimmed
        for suffix in suffixPatterns {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        name = UserInputSanitizer.sanitize(name, policy: .nickname)
        if name.count <= UserInputSanitizer.Policy.nickname.maxLength && !name.isEmpty {
            return name
        } else if !name.isEmpty {
            let parts = name.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "、。！？")))
                .filter { !$0.isEmpty }
            return UserInputSanitizer.sanitize(
                parts.first ?? String(name.prefix(UserInputSanitizer.Policy.nickname.maxLength)),
                policy: .nickname
            )
        }
        return UserInputSanitizer.sanitize(String(trimmed.prefix(UserInputSanitizer.Policy.nickname.maxLength)), policy: .nickname)
    }

    private func isPositiveResponse(_ text: String) -> Bool {
        let positivePatterns = ["うん", "はい", "いい", "おk", "ok", "オッケー", "おっけ", "そう", "ええ", "もちろん", "お願い", "よろしく", "大丈夫", "それで", "yes", "yeah", "yep", "sure", "please", "sounds good", "that's fine"]
        let lowered = text.lowercased()
        return positivePatterns.contains { lowered.contains($0) }
    }

    // MARK: - LLMウォームアップ

    private func warmupLLM() async {
        guard let llmService = llmService else { return }
        let prompt = Gemma4PromptBuilder.buildSingleTurn(
            system: "JSONのみ出力。",
            user: "テスト"
        )
        do {
            _ = try await llmService.generate(prompt: prompt, maxTokens: 1)
            #if DEBUG
            print("[Onboarding] LLMウォームアップ完了")
            #endif
        } catch {
            #if DEBUG
            print("[Onboarding] LLMウォームアップ失敗: \(error)")
            #endif
        }
    }

    // MARK: - メッセージ管理

    private func addChatMessage(text: String, isFromBuddy: Bool) {
        chatMessages.append(ChatDisplayMessage(text: text, isFromBuddy: isFromBuddy))

        if let session = session, let modelContext = modelContext {
            let chatMsg = ChatMessage(text: text, isFromBuddy: isFromBuddy)
            chatMsg.session = session
            session.messages.append(chatMsg)
            session.messageCount += 1
            try? modelContext.save()
        }
    }

    private func saveOnboardingBuddyMessage(_ text: String) {
        guard let session = session, let modelContext = modelContext else { return }
        let chatMsg = ChatMessage(text: text, isFromBuddy: true)
        chatMsg.session = session
        session.messages.append(chatMsg)
        session.messageCount += 1
        try? modelContext.save()
    }

    // MARK: - Reveal 挨拶・フォールバックプール生成（変更なし）

    private func generateGreetings() async {
        guard let llmService = llmService, let seed = generatedSeed else { return }

        let name = UserInputSanitizer.sanitize(buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName, policy: .buddyName)
        let nick = UserInputSanitizer.sanitize(userNickname, policy: .nickname)
        let composer = PersonaLineComposer(displayName: name, seed: seed)

        if Self.usesEnglish {
            revealGreeting = fallbackRevealGreeting(for: seed)
            generatedFirstDayGreeting = fallbackFirstDayGreeting(for: seed, nickname: nick)
        } else {
            revealGreeting = composer.revealGreeting()
            generatedFirstDayGreeting = composer.firstDayGreeting(nickname: nick)
        }
        ProbeLogger.block(ProbeChannel.onboarding, title: "task=onboarding.reveal output.final", text: revealGreeting)
        ProbeLogger.log(ProbeChannel.onboarding, "task=onboarding.reveal deterministic=true final_chars=\(revealGreeting.count)")
        ProbeLogger.block(ProbeChannel.onboarding, title: "task=onboarding.firstDayGreeting output.final", text: generatedFirstDayGreeting)
        ProbeLogger.log(ProbeChannel.onboarding, "task=onboarding.firstDayGreeting deterministic=true final_chars=\(generatedFirstDayGreeting.count)")

        if Self.usesEnglish {
            generatedFallbackReplies = [
                "I hear you. What else happened today?",
                "That sounds like it mattered. Tell me a little more.",
                "Thanks for sharing that with me.",
                "Let's keep that in today's diary.",
            ]
        } else {
            let generator = FallbackReplyGenerator(llmService: llmService)
            let replies = await generator.generate(displayName: name, seed: seed)
            generatedFallbackReplies = replies
        }
        #if DEBUG
        print("[Onboarding] フォールバックプール生成完了: \(generatedFallbackReplies.count)件")
        #endif

        generatedHeroSubtitleFresh = Self.usesEnglish ? fallbackHeroSubtitleFresh(for: seed) : composer.heroSubtitleFresh()
        generatedHeroSubtitleResume = Self.usesEnglish ? fallbackHeroSubtitleResume(for: seed) : composer.heroSubtitleResume()
        ProbeLogger.block(ProbeChannel.onboarding, title: "task=onboarding.heroSubtitleFresh output.final", text: generatedHeroSubtitleFresh)
        ProbeLogger.block(ProbeChannel.onboarding, title: "task=onboarding.heroSubtitleResume output.final", text: generatedHeroSubtitleResume)
        #if DEBUG
        print("[Onboarding] hero subtitle生成完了: fresh='\(generatedHeroSubtitleFresh)' resume='\(generatedHeroSubtitleResume)'")
        #endif
    }

    /// 指定テンプレートと同じ意味の一文をバディの口調で新規に書く。失敗時は空文字を返す。
    /// 「言い換え」だと 2B はテンプレ丸コピーに寄るため、「同じ意味の一文をキャラらしく書く」と
    /// 指示して新規生成させる方が人格が強く反映される。
    private func translateToPersonaTone(template: String, displayName: String, seed: BuddySeed, probeTag: String) async -> String {
        guard let llmService = llmService else { return "" }
        let systemPrompt = BuddyProfile.buildUtteranceOnlySystemPrompt(displayName: displayName, seed: seed)
        let prompt = Gemma4PromptBuilder.buildSingleTurn(
            system: systemPrompt,
            user: "ホーム画面に出す短い案内文を1文だけ書く。意味は「\(template)」と同じにするが、同じ語順をそのまま写さない。25〜50文字。本文だけ出力。"
        )
        do {
            let raw = try await llmService.generate(
                prompt: prompt,
                maxTokens: 80,
                samplingProfile: .guided,
                probeTag: probeTag
            )
            var cleaned = LLMOutputSanitizer.cleanup(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "「」『』\"'`"))
            // task statement + **実返答** パターンなら中身を抽出
            if Self.containsInstructionLeak(cleaned) || cleaned.contains("**") {
                if let extracted = Self.extractMarkdownEmphasis(cleaned) {
                    #if DEBUG
                    print("[Onboarding] hero subtitle口調変換: **強調から抽出: \(extracted)")
                    #endif
                    cleaned = extracted
                }
            }
            // プロンプト漏れ検出：抽出後もなお指示文が残っていたら破棄
            if Self.containsInstructionLeak(cleaned) {
                #if DEBUG
                print("[Onboarding] hero subtitle口調変換: プロンプト漏れ検出 → 空文字: \(cleaned)")
                #endif
                ProbeLogger.log(ProbeChannel.onboarding, "task=\(probeTag) instruction_leak=true final_empty=true")
                return ""
            }
            if cleaned == template {
                ProbeLogger.log(ProbeChannel.onboarding, "task=\(probeTag) copied_template=true final_empty=true")
                return ""
            }
            if cleaned.count >= 8 && cleaned.count <= 80 {
                ProbeLogger.block(ProbeChannel.onboarding, title: "task=\(probeTag) output.final", text: cleaned)
                return cleaned
            }
            ProbeLogger.log(ProbeChannel.onboarding, "task=\(probeTag) final_empty=true cleaned_chars=\(cleaned.count)")
            return ""
        } catch {
            #if DEBUG
            print("[Onboarding] hero subtitle口調変換エラー: \(error)")
            #endif
            ProbeLogger.log(ProbeChannel.onboarding, "task=\(probeTag) error=\(error)")
            return ""
        }
    }

    /// LLM応答にプロンプト指示文の語が混入していないか判定する。
    /// 「同じ意味」「台詞だけ」「キャラらしい」「〇〇文字」などが含まれていたら true。
    static func containsInstructionLeak(_ text: String) -> Bool {
        let leakMarkers = [
            "同じ意味", "台詞だけ", "キャラらしい口調", "キャラらしい短",
            "と同じ意味", "一文を", "一文で返す", "1文で返す", "1文で返します",
            "文字で", "文字。", "50文字", "25〜", "〜50",
            "自己紹介寄り", "今日の話題は振らない", "日記チャット",
            "短い挨拶を", "短い一言", "姿を見せた時",
            "1〜2文", "2文で", "1文だけ",
            "出力。", "出力する", "書いて。", "返します。",
        ]
        return leakMarkers.contains { text.contains($0) }
    }

    /// LLM応答が `**「...」**` や `**『...』**` のマークダウン強調で実返答を包んでいる場合、
    /// その中身だけを抽出する。task statement を echo してから `**実返答**` を出力する
    /// 2B モデルの癖への対処。
    /// 見つからなければ元のテキストを返す。
    static func extractMarkdownEmphasis(_ text: String) -> String? {
        // `**...**` のペアを正規表現で抽出
        guard let regex = try? NSRegularExpression(pattern: "\\*\\*([^*]+?)\\*\\*", options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return nil }
        // 複数ペアがある場合は最長のものを選ぶ（実返答は概ね長い）
        var best = ""
        for m in matches {
            guard m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: text) else { continue }
            let inner = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "「」『』\"'`"))
            if inner.count > best.count {
                best = inner
            }
        }
        return best.isEmpty ? nil : best
    }

    /// LLM応答がメタ語り（「〜で返すね」「〜な挨拶はこれ」等）のあとに
    /// `「本文」` や `『本文』` で実返答を出す場合、中の最長ブロックを抽出する。
    /// 2B がナレーション+台詞形式で返す癖への対処。
    /// 見つからなければ nil。ユーザー呼び名部分（例: `「たろ」さん` の 2 文字など）は短すぎるので除外。
    static func extractQuotedText(_ text: String) -> String? {
        // 「...」『...』 "..." を列挙し、長さ8文字以上で最長のものを返す。
        let patterns = [
            "「([^「」]{6,})」",
            "『([^『』]{6,})』",
            "\"([^\"]{6,})\"",
        ]
        var best = ""
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for m in matches {
                guard m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: text) else { continue }
                let inner = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.count > best.count {
                    best = inner
                }
            }
        }
        return best.isEmpty ? nil : best
    }

    private func sanitizeRevealGreeting(_ text: String, seed: BuddySeed) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // task statement + **実返答** パターンなら中身を抽出
        if Self.containsInstructionLeak(cleaned) || cleaned.contains("**") {
            if let extracted = Self.extractMarkdownEmphasis(cleaned) {
                #if DEBUG
                print("[Onboarding] reveal sanitizer: **強調から抽出: \(extracted)")
                #endif
                cleaned = extracted
            }
        }
        // メタ語り + 「...」 実返答パターン: 最長の引用ブロックを抽出
        if Self.containsInstructionLeak(cleaned) || cleaned.contains("\n") || cleaned.count > 60 {
            if let quoted = Self.extractQuotedText(cleaned), quoted.count >= 8 {
                #if DEBUG
                print("[Onboarding] reveal sanitizer: 引用から抽出: \(quoted)")
                #endif
                cleaned = quoted
            }
        }

        // メタ語や指示復唱パターンを検出。
        let forbiddenTerms = [
            "日記", "記録", "メモ", "アプリ", "設定", "オンボーディング",
            "reveal", "に向けて", "一言を", "画面で", "作って", "言葉を創る",
        ]
        // 短すぎる挨拶（「わかった。」「うん。」等）もフォールバック
        let tooShort = cleaned.count < 8
        if cleaned.isEmpty || tooShort || cleaned.count > 60 || forbiddenTerms.contains(where: { cleaned.contains($0) }) {
            #if DEBUG
            print("[Onboarding] reveal sanitizer: rejected (count=\(cleaned.count), text=\(cleaned))")
            #endif
            return fallbackRevealGreeting(for: seed)
        }
        if Self.containsInstructionLeak(cleaned) {
            #if DEBUG
            print("[Onboarding] reveal sanitizer: プロンプト漏れ検出: \(cleaned)")
            #endif
            return fallbackRevealGreeting(for: seed)
        }
        return cleaned
    }

    /// 日記チャット初回挨拶の sanitizer。長めの2文まで許容する。
    /// 失敗時は空文字を返し、ChatViewModel 側の既存テンプレート生成ルートにフォールバックさせる。
    private func sanitizeFirstDayGreeting(_ text: String, seed: BuddySeed) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // task statement + **実返答** パターンなら中身を抽出
        if Self.containsInstructionLeak(cleaned) || cleaned.contains("**") {
            if let extracted = Self.extractMarkdownEmphasis(cleaned) {
                #if DEBUG
                print("[Onboarding] firstDay sanitizer: **強調から抽出: \(extracted)")
                #endif
                cleaned = extracted
            }
        }
        // メタ語り + 「...」 実返答パターン: 最長の引用ブロックを抽出
        if Self.containsInstructionLeak(cleaned) || cleaned.contains("\n") || cleaned.count > 120 {
            if let quoted = Self.extractQuotedText(cleaned), quoted.count >= 8 {
                #if DEBUG
                print("[Onboarding] firstDay sanitizer: 引用から抽出: \(quoted)")
                #endif
                cleaned = quoted
            }
        }

        let forbiddenTerms = [
            "記録", "アプリ", "設定", "オンボーディング",
            "reveal", "に向けて", "画面で", "作って", "言葉を創る",
        ]
        if cleaned.isEmpty || cleaned.count < 8 || cleaned.count > 120 {
            #if DEBUG
            print("[Onboarding] firstDay sanitizer: 長さ不適 (count=\(cleaned.count))")
            #endif
            return ""
        }
        if forbiddenTerms.contains(where: { cleaned.contains($0) }) {
            #if DEBUG
            print("[Onboarding] firstDay sanitizer: forbidden 検出: \(cleaned)")
            #endif
            return ""
        }
        if Self.containsInstructionLeak(cleaned) {
            #if DEBUG
            print("[Onboarding] firstDay sanitizer: プロンプト漏れ検出: \(cleaned)")
            #endif
            return ""
        }
        return cleaned
    }

    private func fallbackRevealGreeting(for seed: BuddySeed) -> String {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
        if Self.usesEnglish {
            return "Hi, I'm \(name). I'm glad to be here with you."
        }
        return PersonaLineComposer(displayName: name, seed: seed).revealGreeting()
    }

    private func fallbackFirstDayGreeting(for seed: BuddySeed, nickname: String) -> String {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
        if Self.usesEnglish {
            let prefix = nickname.isEmpty || nickname == "you" ? "" : "\(nickname), "
            return "Hi, \(prefix)I'm here. What happened today?"
        }
        return PersonaLineComposer(displayName: name, seed: seed)
            .firstDayGreeting(nickname: nickname == "きみ" ? "" : nickname)
    }

    private func fallbackHeroSubtitleFresh(for seed: BuddySeed) -> String {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
        if Self.usesEnglish {
            return "Tell \(name) a little about today."
        }
        return PersonaLineComposer(displayName: name, seed: seed).heroSubtitleFresh()
    }

    private func fallbackHeroSubtitleResume(for seed: BuddySeed) -> String {
        let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
        if Self.usesEnglish {
            return "You can pick up where today's chat left off."
        }
        return PersonaLineComposer(displayName: name, seed: seed).heroSubtitleResume()
    }

    static func isNullishAnswer(_ text: String) -> Bool {
        let canonical = canonicalShortAnswer(text)
        guard !canonical.isEmpty, canonical.count <= 24 else { return false }

        let nullishPatterns: Set<String> = [
            "特になし", "特に無し", "とくになし", "なし", "ない",
            "なんでもいい", "何でもいい", "どっちでもいい", "どれでもいい", "どうでもいい",
            "おまかせ", "お任せ", "任せる",
            "わからない", "分からない", "わかんない",
            "nothing", "none", "whatever", "no preference",
        ]
        return nullishPatterns.contains(canonical)
    }

    private static func canonicalShortAnswer(_ text: String) -> String {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[。！!？?、,，…〜~\\s]+$", with: "", options: .regularExpression)

        let trailingFillers = [
            "です", "ます", "だよ", "だね", "だな", "かな", "かも",
            "だ", "よ", "ね", "な", "で"
        ]
        var updated = true
        while updated {
            updated = false
            for suffix in trailingFillers where normalized.hasSuffix(suffix) && normalized.count > suffix.count {
                normalized = String(normalized.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                updated = true
                break
            }
        }
        return normalized
    }

    private func proceedToReveal() {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = .reveal
            }
        }
    }

    // MARK: - Retry

    func retryFromReveal() {
        #if DEBUG
        print("[Onboarding] retryFromReveal: persona から再開")
        #endif
        generatedSeed = nil
        isOnboardingComplete = false
        currentSection = .persona
        sectionStartIndex = 0
        sectionTurnCount = 0
        sectionLastSubstantiveInput = ""
        confirmedPersonaEnum = nil
        confirmedPersonaCustom = ""
        confirmedDistanceEnum = nil
        confirmedDistanceCustom = ""
        confirmedDiaryEnum = nil
        confirmedDiaryCustom = ""
        confirmedCustomTraits = ""
        chatMessages.removeAll()
        turnCount = 0

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .chat
        }

        Task {
            let name = buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName
            let message = Self.usesEnglish
                ? "Okay, let's choose again from the start.\n\(Self.personaQuestion(buddyName: name))"
                : "オッケー、最初から決め直そう！\n\(Self.personaQuestion(buddyName: name))"
            await showMessageWithTypingDelay(message)
            sectionStartIndex = chatMessages.count
        }
    }

    // MARK: - Completion（変更なし）

    func completeBuddyCreation(modelContext: ModelContext) {
        guard let seed = generatedSeed else { return }
        isProcessing = true

        let name = UserInputSanitizer.sanitize(buddyName.isEmpty ? AppText.current.buddyDefaultName : buddyName, policy: .buddyName)

        let finalSeed = seedWithConfirmedPersonality(seed)
        generatedSeed = finalSeed
        let buddy = BuddyProfile(displayName: name, seed: finalSeed)
        buddy.fallbackReplies = generatedFallbackReplies
        buddy.heroSubtitleFresh = generatedHeroSubtitleFresh
        buddy.heroSubtitleResume = generatedHeroSubtitleResume
        // 日記チャット初回挨拶は専用生成したものを使う。失敗時は空文字のままにして
        // ChatViewModel 側の既存ルート（テンプレート生成）にフォールバックさせる。
        buddy.firstDayGreeting = generatedFirstDayGreeting
        modelContext.insert(buddy)

        let state = BuddyState(buddyId: buddy.id)
        modelContext.insert(state)

        let user = UserProfile(
            nickname: UserInputSanitizer.sanitize(userNickname, policy: .nickname),
            onboardingCompleted: true
        )
        modelContext.insert(user)

        if let session = session {
            session.completionStatus = .completed
        }

        try? modelContext.save()
        isProcessing = false
    }

    // MARK: - レスポンスクリーンアップ（変更なし）

    private func cleanupResponse(_ response: String) -> String {
        var cleaned = response

        // thinkingブロック全体を除去（タグ＋中身）
        if let regex = try? NSRegularExpression(pattern: "<\\|channel>thought[\\s\\S]*?<channel\\|>", options: []) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }

        // Gemma制御トークン除去
        cleaned = cleaned.replacingOccurrences(of: "<turn|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|channel>thought", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<channel|>", with: "")

        // 特殊トークン除去
        if let regex = try? NSRegularExpression(pattern: "<unused\\d+>|<pad>|<unk>|<mask>|<eos>|\\[multimodal\\]", options: []) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }

        if let regex = try? NSRegularExpression(pattern: "<next_topic:[^>]+>", options: []) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        if let markerRange = cleaned.range(of: "<next_topic:") {
            cleaned = String(cleaned[..<markerRange.lowerBound])
        }

        // タイムスタンプ除去（完全形 [22:40] と、ストリーミング中の不完全形 [2, [22:, [22:4 も除去）
        if let regex = try? NSRegularExpression(pattern: "^\\s*\\[\\d{1,2}(:\\d{0,2})?\\]?\\s*(?=\\S|$)", options: .anchorsMatchLines) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        let trimmedForCheck = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let partialTimestamp = try? NSRegularExpression(pattern: "^\\[\\d{0,2}:?\\d{0,2}\\]?$", options: []),
           partialTimestamp.firstMatch(in: trimmedForCheck, range: NSRange(trimmedForCheck.startIndex..., in: trimmedForCheck)) != nil {
            cleaned = ""
        }

        // 応答全体を囲む「」を除去（LLMがセリフとして出力するパターン）
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("「") && cleaned.hasSuffix("」") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // 10文超え切り捨て（無限ループ防止）
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentencePattern = try! NSRegularExpression(pattern: "[^。！？]+[。！？]", options: [])
        let matches = sentencePattern.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        if matches.count > 10 {
            let endRange = matches[9].range
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: endRange.location + endRange.length)
            cleaned = String(cleaned[..<endIndex])
        }

        return cleaned
    }

}
