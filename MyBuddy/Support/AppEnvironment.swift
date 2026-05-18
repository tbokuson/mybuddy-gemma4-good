import Foundation
import SwiftData
import UIKit

enum AppEnvironment {
    private static let environment = ProcessInfo.processInfo.environment

    enum UITestScenario: String {
        case defaultSeeded
        case postOnboardingReady
        case uiAudit
        case appStoreScreenshots
        case ojisanSeeded
    }

    enum UITestOnboardingPreviewStep: String {
        case reveal
    }

    #if DEBUG
    static var usesOllamaBackend: Bool {
        environment["MYBUDDY_LLM_BACKEND"]?.lowercased() == "ollama"
    }

    static var ollamaConfiguration: OllamaConfiguration {
        OllamaConfiguration(
            baseURL: URL(string: environment["MYBUDDY_OLLAMA_BASE_URL"] ?? "http://127.0.0.1:11434")!,
            model: environment["MYBUDDY_OLLAMA_MODEL"] ?? "gemma4:e2b",
            keepAlive: environment["MYBUDDY_OLLAMA_KEEP_ALIVE"] ?? "30m"
        )
    }
    #endif

    static var isUITestMode: Bool {
        environment["MYBUDDY_UI_TEST_MODE"] == "1"
    }

    static var isRunningUnderXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    static var shouldAutoInitializeLLM: Bool {
        !isRunningUnderXCTest || isUITestMode
    }

    static var shouldForceModelSetup: Bool {
        environment["MYBUDDY_FORCE_MODEL_SETUP"] == "1"
    }

    static var seedsUITestData: Bool {
        isUITestMode && environment["MYBUDDY_UI_TEST_SKIP_ONBOARDING"] != "0"
    }

    static var uiTestScenario: UITestScenario {
        guard isUITestMode,
              let rawValue = environment["MYBUDDY_UI_TEST_SCENARIO"],
              let scenario = UITestScenario(rawValue: rawValue) else {
            return .defaultSeeded
        }
        return scenario
    }

    static var uiTestOnboardingPreviewStep: UITestOnboardingPreviewStep? {
        guard isUITestMode,
              let rawValue = environment["MYBUDDY_UI_TEST_ONBOARDING_STEP"] else {
            return nil
        }
        return UITestOnboardingPreviewStep(rawValue: rawValue)
    }

    static var shouldShowDebugAdminTab: Bool {
        #if DEBUG
        !(isUITestMode && uiTestScenario == .appStoreScreenshots)
        #else
        false
        #endif
    }

    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            BuddyProfile.self,
            BuddyState.self,
            JournalEntry.self,
            ConversationSession.self,
            ChatMessage.self,
            DiaryNote.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITestMode)

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            if !isUITestMode {
                configureStoreProtection()
            }
            if seedsUITestData {
                seedUITestDataIfNeeded(in: container)
            }
            #if DEBUG
            seedLongTermSampleDataIfRequested(in: container)
            #endif
            return container
        } catch {
            fatalError("ModelContainerの作成に失敗しました: \(error.localizedDescription)")
        }
    }

    /// SwiftData ストアのあるディレクトリに対して iCloud バックアップ除外と完全暗号化を設定する
    private static func configureStoreProtection() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        // iCloud バックアップから除外（プライバシーファーストのため会話・日記データをクラウドに残さない）
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = appSupportURL
        try? mutableURL.setResourceValues(resourceValues)

        // NSFileProtectionComplete: 端末ロック時にファイルへのアクセスを遮断
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: appSupportURL.path
        )
    }

    private static func seedUITestDataIfNeeded(in container: ModelContainer) {
        let context = container.mainContext
        let hasUsers = ((try? context.fetch(FetchDescriptor<UserProfile>())) ?? []).isEmpty == false
        guard !hasUsers else { return }

        clearUITestUserDefaults()

        let buddySeed: BuddySeed
        let userNickname: String
        let streakDays: Int
        let intimacyLevel: Int
        let buddyDisplayName: String
        let seedsEnglishContent = AppLanguageMode.currentResolved == .english
        switch uiTestScenario {
        case .defaultSeeded:
            buddySeed = .appDefault
            userNickname = "たろう"
            streakDays = 3
            intimacyLevel = 7
            buddyDisplayName = "テストバディ"
        case .postOnboardingReady:
            buddySeed = BuddySeed(
                bodyId: "round",
                eyeId: "sparkle",
                earId: "round",
                mouthId: "smile",
                paletteId: "warm",
                accentIds: [PersonaStyle.gentle.avatarEmotionAccentId, ConversationDistance.supportive.avatarInterestAccentId],
                personaStyle: .gentle,
                conversationDistance: .supportive,
                memoryPreference: .compact,
                personalityNotes: "初期設定を丁寧に進めるタイプ",
                customTraits: "",
                personaStyleCustom: "やさしく落ち着いた話し方",
                conversationDistanceCustom: "聞き上手で、少し丁寧",
                memoryPreferenceCustom: "シンプルで読み返しやすい日記",
                roomThemeId: "room_default"
            )
            userNickname = "たろう"
            streakDays = 1
            intimacyLevel = 2
            buddyDisplayName = "テストバディ"
        case .uiAudit:
            buddySeed = BuddySeed(
                bodyId: "round",
                eyeId: "sparkle",
                earId: "round",
                mouthId: "smile",
                paletteId: "warm",
                accentIds: [PersonaStyle.gentle.avatarEmotionAccentId, ConversationDistance.casual.avatarInterestAccentId],
                personaStyle: .gentle,
                conversationDistance: .casual,
                memoryPreference: .compact,
                personalityNotes: seedsEnglishContent
                    ? "Likes walks and cafes, and prefers a quiet evening reflection."
                    : "散歩とカフェが好きで、夜は静かに振り返りたい",
                customTraits: seedsEnglishContent
                    ? "Responds gently even when the day feels small."
                    : "短い日でも、やわらかく受け止めてほしい",
                personaStyleCustom: seedsEnglishContent
                    ? "Gentle and calm"
                    : "やさしく落ち着いた話し方",
                conversationDistanceCustom: seedsEnglishContent
                    ? "Casual, like a close friend"
                    : "友だちみたいに気軽",
                memoryPreferenceCustom: seedsEnglishContent
                    ? "Keep diaries short and easy to reread"
                    : "短く読み返しやすく残したい",
                roomThemeId: "room_default"
            )
            userNickname = seedsEnglishContent ? "Taro" : "たろう"
            streakDays = 5
            intimacyLevel = 12
            buddyDisplayName = seedsEnglishContent ? "Test Buddy" : "テストバディ"
        case .appStoreScreenshots:
            buddySeed = BuddySeed(
                bodyId: "round",
                eyeId: "sparkle",
                earId: "round",
                mouthId: "smile",
                paletteId: "pastel",
                accentIds: [PersonaStyle.gentle.avatarEmotionAccentId, ConversationDistance.casual.avatarInterestAccentId],
                personaStyle: .gentle,
                conversationDistance: .casual,
                memoryPreference: .feelingAware,
                personalityNotes: seedsEnglishContent
                    ? "Helps reflect gently, even from short notes on busy days."
                    : "忙しい日でも、短い言葉をやさしく受け止めて振り返りを手伝う",
                customTraits: seedsEnglishContent
                    ? "Soft, everyday, and attentive"
                    : "やわらかく、日常に寄り添う話し方",
                personaStyleCustom: seedsEnglishContent
                    ? "Gentle and calm"
                    : "やさしく落ち着いた話し方",
                conversationDistanceCustom: seedsEnglishContent
                    ? "Casual, like a close friend"
                    : "友だちみたいに気軽",
                memoryPreferenceCustom: seedsEnglishContent
                    ? "Keep events and feelings naturally"
                    : "出来事と気持ちを自然に残したい",
                roomThemeId: "room_default"
            )
            userNickname = seedsEnglishContent ? "Taro" : "たろう"
            streakDays = 7
            intimacyLevel = 14
            buddyDisplayName = seedsEnglishContent ? "Yamada" : "やまだ"
        case .ojisanSeeded:
            buddySeed = BuddySeed.makeRandomOjisan(
                personaStyle: .gentle,
                conversationDistance: .casual,
                memoryPreference: .balanced,
                personalityNotes: "見た目変更の確認用",
                customTraits: "落ち着いた相棒",
                personaStyleCustom: "やさしく落ち着いた話し方",
                conversationDistanceCustom: "友だちみたいに気軽",
                memoryPreferenceCustom: "短く読み返しやすく残したい"
            )
            userNickname = "たろう"
            streakDays = 2
            intimacyLevel = 6
            buddyDisplayName = "テストバディ"
        }

        let buddy = BuddyProfile(displayName: buddyDisplayName, seed: buddySeed)
        let state = BuddyState(buddyId: buddy.id)
        state.streakDays = streakDays
        state.intimacyLevel = intimacyLevel

        context.insert(UserProfile(nickname: userNickname, onboardingCompleted: true))
        context.insert(buddy)
        context.insert(state)

        if uiTestScenario == .uiAudit {
            seedUIAuditContent(context: context, buddy: buddy, state: state)
        } else if uiTestScenario == .appStoreScreenshots {
            seedAppStoreScreenshotContent(context: context, buddy: buddy, state: state)
        }

        do {
            try context.save()
        } catch {
            assertionFailure("UIテスト用データの投入に失敗しました: \(error.localizedDescription)")
        }
    }

    private static func clearUITestUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: JournalTypographyStyle.storageKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("home.todayJournalCreated.") {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where BuddyAppearanceCandidateFactory.isDailyChangeKey(key) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func seedUIAuditContent(
        context: ModelContext,
        buddy: BuddyProfile,
        state: BuddyState
    ) {
        let seedsEnglishContent = AppLanguageMode.currentResolved == .english
        state.longTermMemories = seedsEnglishContent
            ? [
                "Recent mood": "Wants to quietly sort out the day at night",
                "Favorite time": "Morning cafe time",
                "Reset habit": "Taking a short walk in the park"
            ]
            : [
                "最近の気分": "夜は静かに一日を整理したい",
                "好きな時間": "朝のカフェ時間",
                "気分転換": "公園を少し歩くこと"
            ]
        state.lastCheckInDate = Date()

        let sampleImageA = makeUITestImageData(
            primary: UIColor(red: 0.96, green: 0.69, blue: 0.44, alpha: 1),
            secondary: UIColor(red: 0.98, green: 0.84, blue: 0.63, alpha: 1)
        )
        let sampleImageB = makeUITestImageData(
            primary: UIColor(red: 0.71, green: 0.82, blue: 0.71, alpha: 1),
            secondary: UIColor(red: 0.91, green: 0.95, blue: 0.84, alpha: 1)
        )

        let dailySession = ConversationSession(type: .daily)
        context.insert(dailySession)

        let messages: [(String, Bool, Data?)] = seedsEnglishContent
            ? [
                ("Welcome back, Taro. How did today feel?", true, nil),
                ("I had toast at a cafe in Kanda this morning, then took a short walk.", false, sampleImageA),
                ("That sounds like a gentle morning. Did the walk make you feel a little lighter?", true, nil),
                ("Yes. I had a long meeting in the afternoon, but I felt calm again at night.", false, sampleImageB),
                ("I'll keep that calm feeling in today's diary.", true, nil)
            ]
            : [
                ("おかえり、たろう。今日はどんな感じだった？", true, nil),
                ("朝は神田のカフェでトーストを食べて、そのあと少し散歩したよ。", false, sampleImageA),
                ("いい朝だったんだね。歩いたあと、気分は少し軽くなった？", true, nil),
                ("うん。午後は打ち合わせが長かったけど、夜は落ち着いた。", false, sampleImageB),
                ("その落ち着いた感じ、今日の日記にもそっと残しておくね。", true, nil)
            ]

        for (offset, item) in messages.enumerated() {
            let chatMessage = ChatMessage(text: item.0, isFromBuddy: item.1, imageData: item.2)
            chatMessage.timestamp = Calendar.current.date(byAdding: .minute, value: offset * 4, to: Date()) ?? Date()
            chatMessage.session = dailySession
            dailySession.messages.append(chatMessage)
        }
        dailySession.messageCount = messages.count

        let todayEntry = seedsEnglishContent
            ? JournalEntry(
                date: DayBoundary.appToday(),
                title: "A Day That Found Its Quiet Space",
                summaryText: "A short walk after breakfast in Kanda, a long meeting, and a calm evening.",
                fullDiaryText: "I had toast at a cafe in Kanda this morning, then took a short walk. The afternoon meeting was long, but by night my mind had settled again. Even inside a busy day, there was still a little room to feel calm.",
                emotionTags: ["relieved", "calm"],
                tomorrowNote: "Leave a small pocket of quiet in the morning again.",
                imageDataList: [sampleImageA, sampleImageB]
            )
            : JournalEntry(
                date: DayBoundary.appToday(),
                title: "静かな余白が戻った日",
                summaryText: "神田のカフェ、長い打ち合わせ、夜の落ち着きまでが短くまとまった一日。",
                fullDiaryText: "朝は神田のカフェでトーストを食べて、少し散歩した。午後の打ち合わせは長かったけれど、夜には気持ちが静かに戻ってきた。忙しさの中でも、落ち着ける時間が少し残った日だった。",
                emotionTags: ["ほっとした", "落ち着き"],
                tomorrowNote: "明日も朝の余白を少し残せるとよさそう。",
                imageDataList: [sampleImageA, sampleImageB]
            )
        context.insert(todayEntry)

        let pastEntry = seedsEnglishContent
            ? JournalEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: DayBoundary.appToday()) ?? DayBoundary.appToday(),
                title: "A Night Made Softer by Rain",
                summaryText: "Rain on the way home slowed the day down just enough.",
                fullDiaryText: "It was raining on the way home, and my steps felt a little heavy at first. As I listened to the sound of the rain, the rush of the day loosened. The evening moved slowly, and that ended up being exactly what I needed.",
                emotionTags: ["softened", "safe"],
                tomorrowNote: "Do not overpack the morning schedule.",
                imageDataList: [sampleImageB]
            )
            : JournalEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: DayBoundary.appToday()) ?? DayBoundary.appToday(),
                title: "雨音で少し深呼吸できた夜",
                summaryText: "帰り道に雨が降っていて、慌ただしさが少しだけ静まった。",
                fullDiaryText: "帰り道に雨が降っていて、足取りは少し重かったけれど、音を聞いているうちに気持ちがゆるんだ。夜は急がずに過ごせて、結果的にはちょうどよかった。",
                emotionTags: ["しっとり", "安心"],
                tomorrowNote: "午前の予定を詰めすぎない。",
                imageDataList: [sampleImageB]
            )
        context.insert(pastEntry)

        UserDefaults.standard.set(true, forKey: "home.todayJournalCreated.\(Int(DayBoundary.startOfAppDay().timeIntervalSince1970))")
    }

    private static func seedAppStoreScreenshotContent(
        context: ModelContext,
        buddy: BuddyProfile,
        state: BuddyState
    ) {
        let seedsEnglishContent = AppLanguageMode.currentResolved == .english
        state.longTermMemories = seedsEnglishContent
            ? [
                "Favorite morning": "Writing a little at a neighborhood cafe",
                "Calming time": "Tidying the room at night with a warm drink",
                "What to keep": "Short notes about both events and feelings"
            ]
            : [
                "好きな朝の過ごし方": "近所のカフェで少しだけ書きものをする",
                "落ち着く時間": "夜に部屋を片づけて、あたたかい飲み物を飲む",
                "残したいこと": "出来事だけでなく、その時の気分も短く残したい"
            ]
        state.lastCheckInDate = Date()

        let tramImage = makeScreenshotImageData(
            environmentKey: "MYBUDDY_APPSTORE_SCREENSHOT_IMAGE_1",
            primary: UIColor(red: 0.97, green: 0.71, blue: 0.43, alpha: 1),
            secondary: UIColor(red: 0.99, green: 0.87, blue: 0.66, alpha: 1)
        )
        let mealImage = makeScreenshotImageData(
            environmentKey: "MYBUDDY_APPSTORE_SCREENSHOT_IMAGE_2",
            primary: UIColor(red: 0.73, green: 0.84, blue: 0.73, alpha: 1),
            secondary: UIColor(red: 0.93, green: 0.95, blue: 0.84, alpha: 1)
        )

        let dailySession = ConversationSession(type: .daily)
        context.insert(dailySession)

        let messages: [(String, Bool, Data?)] = seedsEnglishContent
            ? [
                ("Welcome back. What was today like?", true, nil),
                ("I took the train a little farther than usual today. The city looked beautiful through the window, so even the ride felt nice.", false, tramImage),
                ("A good view while traveling can change the whole mood of the day.", true, nil),
                ("I had a warm lunch and ate slowly, so the afternoon felt settled too.", false, mealImage),
                ("I'll keep the train ride and that calm meal in today's diary.", true, nil)
            ]
            : [
                ("おかえり。今日はどんな一日だった？", true, nil),
                ("今日は電車で少し遠くまで出かけたよ。窓から見える街並みがきれいで、移動中も楽しかった。", false, tramImage),
                ("移動中にいい景色が見えると、それだけで気分が少し変わるね。", true, nil),
                ("お昼は温かい食事をゆっくり食べられて、午後も落ち着いて過ごせた。", false, mealImage),
                ("電車で出かけたことと、食事で落ち着けた感じを今日の日記に残しておくね。", true, nil)
            ]

        for (offset, item) in messages.enumerated() {
            let chatMessage = ChatMessage(text: item.0, isFromBuddy: item.1, imageData: item.2)
            chatMessage.timestamp = Calendar.current.date(byAdding: .minute, value: offset * 5, to: Date()) ?? Date()
            chatMessage.session = dailySession
            dailySession.messages.append(chatMessage)
        }
        dailySession.messageCount = messages.count

        let todayEntry = seedsEnglishContent
            ? JournalEntry(
                date: DayBoundary.appToday(),
                title: "A Day Out by Train",
                summaryText: "I went a little farther by train and felt grounded by a warm meal.",
                fullDiaryText: "I took the train a little farther than usual today. The city looked beautiful through the window, and the ride itself felt enjoyable. At lunch, I had a warm meal and ate slowly, which helped the afternoon feel calm. It was not a huge event, but it still left a clear sense of satisfaction.",
                emotionTags: ["happy", "relieved"],
                tomorrowNote: "Make a little time to settle down tomorrow too.",
                imageDataList: [tramImage, mealImage]
            )
            : JournalEntry(
                date: DayBoundary.appToday(),
                title: "電車で出かけた日",
                summaryText: "電車で少し遠くまで出かけ、温かい食事で落ち着けた一日。",
                fullDiaryText: "今日は電車で少し遠くまで出かけた。窓から見える街並みがきれいで、移動している時間も楽しかった。お昼には温かい食事をゆっくり食べられて、午後も落ち着いた気持ちで過ごせた。特別に大きな出来事ではないけれど、ちゃんと満足感の残る一日だった。",
                emotionTags: ["楽しかった", "ほっとした"],
                tomorrowNote: "明日も、落ち着ける時間を少し作ろう。",
                imageDataList: [tramImage, mealImage]
            )
        context.insert(todayEntry)

        let yesterdayEntry = seedsEnglishContent
            ? JournalEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: DayBoundary.appToday()) ?? DayBoundary.appToday(),
                title: "A Deep Breath After the Rain",
                summaryText: "A small detour after the rain made the way home feel lighter.",
                fullDiaryText: "On the way home, I took a small detour after the rain stopped. The air felt soft, and as I walked, my mood became a little lighter too. It had been a busy day, but I was glad there was time at the end to take a deep breath.",
                emotionTags: ["calm", "reset"],
                tomorrowNote: "Look up at the sky for a moment on the way home.",
                imageDataList: []
            )
            : JournalEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: DayBoundary.appToday()) ?? DayBoundary.appToday(),
                title: "雨上がりに深呼吸した日",
                summaryText: "帰り道の雨上がりに、少しだけ遠回りして気分が軽くなった。",
                fullDiaryText: "帰り道、雨が上がったあとに少しだけ遠回りした。空気がやわらかくて、歩いているうちに気分も少し軽くなった。忙しい日だったけれど、最後に深呼吸できる時間があってよかった。",
                emotionTags: ["穏やか", "リセット"],
                tomorrowNote: "無理せず、帰り道に少しだけ空を見よう。",
                imageDataList: []
            )
        context.insert(yesterdayEntry)

        UserDefaults.standard.set(true, forKey: "home.todayJournalCreated.\(Int(DayBoundary.startOfAppDay().timeIntervalSince1970))")
    }

    private static func makeUITestImageData(primary: UIColor, secondary: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: 1200, height: 900))
            let cgContext = context.cgContext
            let colors = [primary.cgColor, secondary.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0, 1]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
            }

            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.28).cgColor)
            cgContext.fillEllipse(in: CGRect(x: 120, y: 120, width: 320, height: 320))
            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cgContext.fillEllipse(in: CGRect(x: 720, y: 240, width: 240, height: 240))
        }

        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private static func makeScreenshotImageData(
        environmentKey: String,
        primary: UIColor,
        secondary: UIColor
    ) -> Data {
        #if DEBUG
        if let path = environment[environmentKey],
           !path.isEmpty,
           let image = UIImage(contentsOfFile: path),
           let data = image.jpegData(compressionQuality: 0.88) {
            return data
        }
        #endif

        return makeUITestImageData(primary: primary, secondary: secondary)
    }

    #if DEBUG
    private static func seedLongTermSampleDataIfRequested(in container: ModelContainer) {
        guard let configuration = LongTermSampleDataSeeder.configuration(
            arguments: ProcessInfo.processInfo.arguments,
            environment: environment
        ) else {
            return
        }

        do {
            let result = try LongTermSampleDataSeeder.seedIfNeeded(
                in: container.mainContext,
                configuration: configuration
            )
            if result.skippedBecauseDataExists {
                print("[LongTermSeed] 既存データがあるため投入をスキップしました。リセットする場合は --mybuddy-reset-before-long-term-seed を付けてください。")
            } else {
                print("[LongTermSeed] \(result.insertedDays)日分 / 日記\(result.insertedJournalCount)件 / メッセージ\(result.insertedMessageCount)件を投入しました。")
            }
        } catch {
            assertionFailure("長期利用検証データの投入に失敗しました: \(error.localizedDescription)")
        }
    }
    #endif
}
