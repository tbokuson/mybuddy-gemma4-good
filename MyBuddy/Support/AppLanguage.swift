import Foundation

enum ResolvedAppLanguage: String, Sendable {
    case japanese = "ja"
    case english = "en"
}

enum AppLanguageMode: String, CaseIterable, Identifiable {
    case system
    case japanese = "ja"
    case english = "en"

    static let storageKey = "app.languageMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .japanese: return "Japanese"
        case .english: return "English"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .system: return "システム"
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }

    var resolvedLanguage: ResolvedAppLanguage {
        switch self {
        case .japanese:
            return .japanese
        case .english:
            return .english
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            return preferred.hasPrefix("ja") ? .japanese : .english
        }
    }

    static var current: AppLanguageMode {
        AppLanguageMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static var currentResolved: ResolvedAppLanguage {
        current.resolvedLanguage
    }
}

struct AppText {
    let resolvedLanguage: ResolvedAppLanguage

    static var current: AppText {
        AppText(language: AppLanguageMode.currentResolved)
    }

    init(language: ResolvedAppLanguage) {
        self.resolvedLanguage = language
    }

    var isEnglish: Bool { resolvedLanguage == .english }

    var homeTab: String { isEnglish ? "Home" : "ホーム" }
    var journalTab: String { isEnglish ? "Diary" : "日記" }
    var adminTab: String { isEnglish ? "Admin" : "管理" }
    var settingsTab: String { isEnglish ? "Settings" : "設定" }

    var loading: String { isEnglish ? "Loading..." : "読み込み中..." }
    var notConfigured: String { isEnglish ? "Not configured" : "未設定" }
    var launchPreparingTitle: String { isEnglish ? "Preparing to launch" : "起動準備をしています" }
    var launchPreparingMessage: String {
        isEnglish
            ? "Checking MyBuddy's setup. Please wait a moment."
            : "MyBuddyの準備を確認しています。少しだけお待ちください。"
    }
    var modelSetupHeroTitle: String {
        isEnglish ? "Talk a little. Keep today as a diary." : "話すだけで、今日が日記になる。"
    }
    var modelSetupEyebrow: String { isEnglish ? "BEFORE YOU START" : "はじめる前に" }
    var modelSetupTitle: String { isEnglish ? "Add MyBuddy's local AI" : "MyBuddyのAIを追加します" }
    var modelSetupSubtitle: String {
        isEnglish
            ? "On first launch, MyBuddy downloads the files it needs to run on this iPhone."
            : "初回だけ、iPhoneの中で動くためのファイルをダウンロードします。"
    }
    var modelSetupOnDeviceRow: String {
        isEnglish ? "Chat and diary creation run on this iPhone" : "会話と日記づくりはiPhoneの中で動きます"
    }
    var modelSetupWifiRow: String {
        isEnglish ? "The files are large, so Wi-Fi is required" : "大きめのファイルなのでWi-Fi接続が必要です"
    }
    var modelSetupOfflineRow: String {
        isEnglish
            ? "After setup, chat and diary creation do not use the internet"
            : "この準備のあと、会話や日記づくりでインターネットに接続しません"
    }
    var modelSetupDownloadingTitle: String { isEnglish ? "Downloading" : "ダウンロード中" }
    var modelSetupDownloadingButton: String { isEnglish ? "Downloading..." : "ダウンロード中..." }
    var modelSetupRetry: String { isEnglish ? "Try again" : "もう一度試す" }
    var modelSetupPreparing: String { isEnglish ? "Preparing" : "準備中です" }
    var modelSetupErrorTitle: String { isEnglish ? "Setup could not be completed" : "うまく準備できませんでした" }
    var modelSetupDeclineNotice: String {
        isEnglish
            ? "The download has not started yet. Initial setup is required to use MyBuddy."
            : "ダウンロードはまだ開始していません。MyBuddyを使うには、初回セットアップが必要です。"
    }
    var modelSetupNotNow: String { isEnglish ? "Not now" : "今は開始しない" }
    var modelSetupWifiHint: String {
        isEnglish ? "Please check your Wi-Fi before starting." : "開始前にWi-Fiを確認してください。"
    }
    var modelSetupWifiAlertTitle: String {
        isEnglish ? "Continue without Wi-Fi?" : "Wi-Fiなしで続けますか？"
    }
    var modelSetupWifiAlertMessage: String {
        isEnglish
            ? "The AI model files are large, so we recommend using Wi-Fi. If you continue downloading, please be aware that mobile data charges may apply."
            : "AIモデルファイルのサイズが大きいため、Wi-Fiの利用をお勧めします。このままダウンロードする場合は、モバイルデータ通信料にご注意ください。"
    }
    var modelSetupWifiAlertCancel: String { isEnglish ? "Cancel" : "キャンセル" }
    var modelSetupWifiAlertContinue: String { isEnglish ? "Continue" : "続ける" }
    func approximateSize(_ size: String) -> String {
        isEnglish ? "about \(size)" : "約\(size)"
    }
    func modelSetupSizeRow(size: String) -> String {
        isEnglish ? "Download size is \(size)" : "ダウンロードサイズは\(size)です"
    }
    func modelSetupStartDownload(size: String) -> String {
        isEnglish ? "Start \(size) download" : "\(size)をダウンロード開始"
    }
    var aiLoadError: String { isEnglish ? "AI loading error" : "AIの読み込みエラー" }
    var startConversation: String { isEnglish ? "Start today's chat" : "今日の会話をはじめる" }
    var continueConversation: String { isEnglish ? "Continue chatting" : "会話の続きをはじめる" }
    var recentJournals: String { isEnglish ? "Recent diaries" : "最近の日記" }
    var aiLoadingMessage: String {
        isEnglish
            ? "MyBuddy is loading the local AI. Please wait a moment."
            : "MyBuddyのAIを読み込み中です。準備ができるまで少しだけ待ってください。"
    }
    var missingBuddyTitle: String { isEnglish ? "Buddy data was not found" : "バディのデータが見つかりません" }
    var missingBuddyMessage: String { isEnglish ? "Please reinstall the app." : "アプリを再インストールしてください" }
    var close: String { isEnglish ? "Close" : "閉じる" }
    var todaysBuddy: String { isEnglish ? "Today's buddy" : "今日のバディ" }
    var todayDiaryBadge: String { isEnglish ? "Diary created today" : "今日の日記あり" }

    var settingsTitle: String { settingsTab }
    var appInfo: String { isEnglish ? "App info" : "アプリ情報" }
    var version: String { isEnglish ? "Version" : "バージョン" }
    var languageTitle: String { isEnglish ? "Language" : "言語" }
    var appLanguage: String { isEnglish ? "App language" : "アプリの言語" }
    var appLanguageDescription: String {
        isEnglish
            ? "Switch the main demo UI and AI output language."
            : "主要UIとAI出力の言語を切り替えます。"
    }
    var buddySettings: String { isEnglish ? "Buddy settings" : "バディ設定" }
    var appearanceDescription: String {
        isEnglish
            ? "Keep the personality and diary style, and change only the appearance."
            : "性格や日記スタイルはそのまま、見た目だけ変更できます。"
    }
    var currentAppearance: String { isEnglish ? "Current appearance" : "現在の見た目" }
    var changedToday: String { isEnglish ? "Changed today" : "今日は変更済み" }
    var changeAppearance: String { isEnglish ? "Change appearance from today's options" : "今日の候補から見た目を変更" }
    var appearanceLimitChanged: String {
        isEnglish
            ? "Appearance can be changed once per day. Try again tomorrow."
            : "見た目の変更は1日1回までです。明日また変更できます。"
    }
    var appearanceLimitAvailable: String {
        isEnglish
            ? "Three random candidates appear. You can change once per day."
            : "候補はランダムで3つ出ます。変更は1日1回までです。"
    }
    var buddySettingsUnavailable: String { isEnglish ? "Available after creating a buddy." : "バディ作成後に設定できます。" }
    var appearanceCandidateTitle: String { isEnglish ? "Today's appearance options" : "今日の候補" }
    var appearanceCandidateDescription: String {
        isEnglish
            ? "Only the appearance changes. Personality and diary style stay the same."
            : "性格はそのまま、見た目だけ変わります。"
    }
    var appearancePreviewTitle: String { isEnglish ? "Use this appearance?" : "この見た目にしますか？" }
    var appearancePreviewDescriptionSuffix: String {
        isEnglish
            ? " option. Personality and diary style stay the same."
            : "の候補です。性格や日記スタイルは変わりません。"
    }
    var returnToCandidates: String { isEnglish ? "Back to options" : "候補に戻る" }
    var policies: String { isEnglish ? "Policies" : "ポリシー・規約" }
    var privacyPolicy: String { isEnglish ? "Privacy Policy" : "プライバシーポリシー" }
    var termsOfService: String { isEnglish ? "Terms of Service" : "利用規約" }
    var ossLicenses: String { isEnglish ? "OSS Licenses" : "OSS ライセンス" }
    var dataManagement: String { isEnglish ? "Data management" : "データ管理" }
    var resetBuddyAndDiary: String { isEnglish ? "Reset buddy and diaries" : "バディと日記をリセット" }
    var resetConfirmTitle: String { isEnglish ? "Reset everything?" : "本当にリセットしますか？" }
    var resetConfirmAction: String {
        isEnglish ? "Delete buddy and diaries, then reset" : "バディと日記を削除してリセット"
    }
    var cancel: String { isEnglish ? "Cancel" : "キャンセル" }
    var resetMessage: String {
        isEnglish
            ? "Your buddy, chat history, diaries, and memories will be deleted. This cannot be undone."
            : "バディ、会話履歴、日記、全ての記憶が削除されます。この操作は取り消せません。"
    }

    var writeDiary: String { isEnglish ? "Create diary" : "日記をつける" }
    var updateDiary: String { isEnglish ? "Update diary" : "日記を更新" }
    var diaryPreparing: String { isEnglish ? "Preparing diary" : "日記準備中" }
    var diaryUpdating: String { isEnglish ? "Updating diary" : "日記更新中" }
    var diaryLoadingNew: String { isEnglish ? "Creating your diary..." : "日記をつけています..." }
    var diaryLoadingUpdate: String { isEnglish ? "Adding to your diary..." : "日記に書き加えています..." }
    var diarySuggestTitle: String { isEnglish ? "Create today's diary?" : "今日の日記をつけますか？" }
    var diarySuggestSubtitle: String { isEnglish ? "You can keep chatting after this." : "会話はこのまま続けられます" }
    var create: String { isEnglish ? "Create" : "作成" }
    var visionLoading: String { isEnglish ? "Preparing to look at the image..." : "画像を見る準備をしています..." }
    var chatPlaceholder: String { isEnglish ? "Type a message..." : "メッセージを入力..." }
    var todayDiaryAvailable: String { isEnglish ? "Today's diary is ready" : "今日の日記を読めます" }
    var diaryUpdatesWhileChatting: String {
        isEnglish
            ? "If you keep chatting, it will update little by little."
            : "会話を続けると、内容が少しずつ更新されます"
    }
    var diaryUpdatingLong: String {
        isEnglish
            ? "Updating the diary with the new conversation."
            : "新しい会話を反映して、日記を更新しています。"
    }
    var diaryPreparingLong: String {
        isEnglish
            ? "Turning the conversation into today's diary."
            : "会話をもとに、今日の日記をまとめています。"
    }
    var diaryStatusUpdateHint: String {
        isEnglish
            ? "Use \"Update diary\" in the top right. It also updates automatically when you close this screen or leave the app."
            : "右上の「日記を更新」で反映できます。画面を閉じた時やアプリ移動時にも自動で更新されます。"
    }
    var diaryStatusCreateHint: String {
        isEnglish
            ? "Use \"Create diary\" in the top right. It also creates automatically when you close this screen or leave the app."
            : "右上の「日記をつける」で作れます。画面を閉じた時やアプリ移動時にも自動で作成されます。"
    }
    var diaryGeneratingNew: String { isEnglish ? "Creating diary..." : "日記を作成中..." }
    var diaryGeneratingUpdate: String { isEnglish ? "Updating diary..." : "日記を更新中..." }
    var diaryCreated: String { isEnglish ? "Today's diary is ready" : "今日の日記ができました" }
    var diaryUpdated: String { isEnglish ? "Diary updated" : "日記を更新しました" }
    var tapToRead: String { isEnglish ? "Tap to read" : "タップして読む" }
    var buddyNoteTitle: String { isEnglish ? "A note from" : "からの一言" }
    var buddyDefaultName: String { isEnglish ? "Buddy" : "バディ" }
    var done: String { isEnglish ? "Done" : "完了" }
    var imageUnavailableReply: String {
        isEnglish
            ? "I received the image. I cannot analyze it right now, so could you describe what is in it?"
            : "画像は受け取れたよ。いま画像解析が使えないから、写っている内容を言葉で教えてくれる？"
    }

    var noJournalsTitle: String { isEnglish ? "No diaries yet" : "まだ日記がありません" }
    var noJournalsDescription: String {
        isEnglish
            ? "Chat with your buddy, and diaries will appear here."
            : "バディと会話すると、\nここに日記が並んでいきます。"
    }
    var allJournals: String { isEnglish ? "All diaries" : "すべての日記" }
    var flashback: String { isEnglish ? "A look back" : "あの日のふりかえり" }
    var edit: String { isEnglish ? "Edit" : "編集" }
    var save: String { isEnglish ? "Save" : "保存" }
    var titlePlaceholder: String { isEnglish ? "Title" : "タイトル" }

    var onboardingProgressNaming: String {
        isEnglish ? "Getting ready to create your buddy" : "バディをつくる準備をしています"
    }
    var onboardingProgressChat: String {
        isEnglish ? "Creating your buddy through conversation" : "会話から、あなたのバディをつくっています"
    }
    var onboardingWelcomeTitle: String {
        isEnglish ? "Turn chats into a diary." : "話すだけで、日記になる。"
    }
    var onboardingWelcomeSubtitle: String {
        isEnglish
            ? "A private record only for you.\nShort chats turn into gentle diary entries."
            : "誰にも見られない、あなただけの記録。\n短い会話が、やさしい日記に変わります。"
    }
    var onboardingStart: String { isEnglish ? "Get started" : "はじめる" }
    var onboardingPrivacyTitle: String {
        isEnglish ? "Your record stays\non this iPhone" : "あなたの記録は\nこのiPhoneの中だけ"
    }
    var onboardingPrivacySubtitle: String {
        isEnglish
            ? "So you can write honestly, chats and diaries are stored only on this iPhone."
            : "安心して本音を残せるように、\n会話や日記はこのiPhoneの中だけに保存されます。"
    }
    var onboardingPrivacyDeviceRow: String {
        isEnglish ? "Chats and diaries are saved on device" : "会話と日記はすべて端末内に保存"
    }
    var onboardingPrivacyNoSendRow: String {
        isEnglish ? "They are not sent to an external server" : "外部への送信はありません"
    }
    var onboardingPrivacyAIRow: String {
        isEnglish ? "The AI runs on this iPhone" : "AIはiPhoneの中で動きます"
    }
    var onboardingAgreeStart: String { isEnglish ? "Agree and start" : "同意してはじめる" }
    var onboardingNamingTitle: String { isEnglish ? "Name your buddy" : "バディに名前をつけよう" }
    var onboardingBuddyNamePlaceholder: String { isEnglish ? "Buddy name" : "バディの名前" }
    var onboardingNameReady: String { isEnglish ? "Continue with this name" : "この名前で進めます" }
    var onboardingNameRequired: String { isEnglish ? "Enter your buddy's name" : "バディの名前を入力してください" }
    var onboardingNameConfirm: String { isEnglish ? "Start with this name" : "この名前で始める" }
    var onboardingFirstChat: String { isEnglish ? "First chat" : "出会いの会話" }
    var onboardingShortAnswerHint: String {
        isEnglish ? "Short answers are fine" : "短く答えるだけで大丈夫です"
    }
    var onboardingInputPlaceholder: String { chatPlaceholder }
    var onboardingCompleteTitle: String { isEnglish ? "All set!" : "準備完了！" }
    var onboardingCompleteSubtitle: String {
        isEnglish ? "Now tell your buddy about today." : "さっそく、今日のことを話してみよう"
    }
    var onboardingRevealComplete: String { isEnglish ? "Nice to meet you!" : "よろしくね！" }
    var onboardingRetry: String { isEnglish ? "Start over" : "やり直す" }
    var onboardingChooseTypeAgain: String { isEnglish ? "Choose another type" : "タイプを選び直す" }

    func onboardingWaitingTitle(buddyName: String) -> String {
        isEnglish ? "Preparing to welcome \(buddyName)" : "\(buddyName)を迎える準備をしています"
    }

    var onboardingWaitingSubtitle: String {
        isEnglish
            ? "Getting the first reply ready. Please wait a little longer."
            : "最初の返事を整えています。もう少しだけ待ってください。"
    }

    func onboardingExtractingTitle(buddyName: String) -> String {
        isEnglish ? "Shaping \(buddyName)'s personality" : "\(buddyName)らしさを整えています"
    }

    var onboardingExtractingSubtitle: String {
        isEnglish
            ? "Using the conversation to shape the look and voice."
            : "会話の雰囲気から、見た目や話し方を整えています。"
    }

    func onboardingEndChatButton(buddyName: String) -> String {
        isEnglish ? "Looks good. Meet \(buddyName)" : "これでOK！\(buddyName)の姿を見る"
    }

    func onboardingAppearanceTitle(buddyName: String, hasSelectedType: Bool) -> String {
        if isEnglish {
            return hasSelectedType ? "Which one feels right?" : "What type should \(buddyName) be?"
        }
        return hasSelectedType ? "この中ならどの子？" : "\(buddyName)のタイプは？"
    }

    func onboardingAppearanceSubtitle(hasSelectedType: Bool) -> String {
        if isEnglish {
            return hasSelectedType ? "Choose from three options." : "Start by choosing the overall type."
        }
        return hasSelectedType ? "3つの候補から選べます" : "まずは大きなタイプを選んでね"
    }

    var buddyProfileSubtitle: String {
        isEnglish ? "A profile of what makes this buddy feel like themselves" : "この子らしさをまとめたプロフィール"
    }
    var buddyProfilePersona: String { isEnglish ? "Vibe" : "空気感" }
    var buddyProfileDistance: String { isEnglish ? "Conversation style" : "距離感" }
    var buddyProfileMemory: String { isEnglish ? "Diary style" : "覚え方" }
    var buddyProfileSpecialRule: String { isEnglish ? "Special rule" : "特別ルール" }
    var buddyProfileAboutYou: String { isEnglish ? "About you" : "あなたのこと" }
    func buddyProfileTitle(_ name: String) -> String {
        isEnglish ? "\(name)'s profile" : "\(name)のプロフィール"
    }

    func personaLabel(style: PersonaStyle, custom: String) -> String {
        if !custom.isEmpty { return custom }
        if !isEnglish { return style.displayName }
        switch style {
        case .gentle: return "Gentle"
        case .cool: return "Cool"
        case .bright: return "Bright"
        case .mellow: return "Relaxed"
        }
    }

    func distanceLabel(distance: ConversationDistance, custom: String) -> String {
        if !custom.isEmpty { return custom }
        if !isEnglish { return distance.displayName }
        switch distance {
        case .supportive: return "Quietly supportive"
        case .casual: return "Casual, like a friend"
        case .frank: return "Frank and direct"
        case .playful: return "Playful"
        }
    }

    func memoryLabel(memory: MemoryPreference, custom: String) -> String {
        if !custom.isEmpty { return custom }
        if !isEnglish { return memory.displayName }
        switch memory {
        case .compact: return "Short and simple"
        case .balanced: return "Natural, event-focused"
        case .feelingAware: return "Includes feelings"
        }
    }

    var englishGreeting: String { "Hi, I'm here. What happened today?" }
    var englishResumeGreeting: String { "Welcome back. Want to continue from where we left off?" }
    var englishClosing: String { "Thanks for sharing today." }
    var englishFallbackQuestion: String { "I hear you. What else happened today?" }
    var englishClosingFallback: String { "Rest well today." }

    func streakLabel(days: Int) -> String {
        if isEnglish {
            return days == 1 ? "1 day streak" : "\(days) day streak"
        }
        return "\(days)日連続"
    }

    func imageCountLabel(count: Int) -> String {
        isEnglish ? "\(count) images" : "\(count)枚"
    }

    func appearanceDisplayName(for seed: BuddySeed) -> String {
        if !isEnglish {
            return seed.appearanceDisplayName
        }

        switch seed.characterType {
        case "ojisan":
            return "Human buddy"
        case "fish":
            return "Fish"
        default:
            return "Monster"
        }
    }

    func appearanceKindName(for kind: BuddyAppearanceKind) -> String {
        if !isEnglish {
            return kind.displayName
        }

        switch kind {
        case .monster:
            return "Monster"
        case .ojisan:
            return "Human"
        }
    }

    func appearanceKindDescription(for kind: BuddyAppearanceKind) -> String {
        if !isEnglish {
            return kind.shortDescription
        }

        switch kind {
        case .monster:
            return "Soft and friendly"
        case .ojisan:
            return "Human-like and warm"
        }
    }

    func candidateLabel(index: Int) -> String {
        isEnglish ? "Option \(index)" : "候補\(index)"
    }

    func appearanceCandidateTitle(for buddyName: String) -> String {
        isEnglish ? "\(buddyName)'s options today" : "\(buddyName)の今日の候補"
    }

    func confirmAppearanceLabel(for buddyName: String) -> String {
        isEnglish ? "Use this look for \(buddyName)" : "\(buddyName)をこの見た目にする"
    }
}
