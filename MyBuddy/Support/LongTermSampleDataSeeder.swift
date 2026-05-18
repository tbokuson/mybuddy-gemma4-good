#if DEBUG
import Foundation
import SwiftData
import UIKit

struct LongTermSampleDataSeeder {
    struct Configuration: Equatable {
        nonisolated static let defaultDayCount = 180
        nonisolated static let minimumDayCount = 1
        nonisolated static let maximumDayCount = 365

        var dayCount: Int = Self.defaultDayCount
        var resetBeforeSeeding = false
    }

    struct Result: Equatable {
        var insertedDays: Int
        var insertedJournalCount: Int
        var insertedSessionCount: Int
        var insertedMessageCount: Int
        var insertedDiaryNoteCount: Int
        var skippedBecauseDataExists: Bool
    }

    @discardableResult
    static func seedIfNeeded(
        in context: ModelContext,
        configuration: Configuration
    ) throws -> Result {
        let existingUsers = try context.fetch(FetchDescriptor<UserProfile>())
        if !existingUsers.isEmpty && !configuration.resetBeforeSeeding {
            return Result(
                insertedDays: 0,
                insertedJournalCount: 0,
                insertedSessionCount: 0,
                insertedMessageCount: 0,
                insertedDiaryNoteCount: 0,
                skippedBecauseDataExists: true
            )
        }

        if configuration.resetBeforeSeeding {
            try clearAllLocalData(in: context)
        }

        let dayCount = clampedDayCount(configuration.dayCount)
        let calendar = Calendar.current
        let today = DayBoundary.appToday()
        let buddySeed = BuddySeed(
            bodyId: "round",
            eyeId: "sparkle",
            earId: "round",
            mouthId: "smile",
            paletteId: "pastel",
            accentIds: [PersonaStyle.gentle.avatarEmotionAccentId, ConversationDistance.casual.avatarInterestAccentId],
            personaStyle: .gentle,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "長期利用検証用。落ち着いて短く返す。",
            customTraits: "関西弁は使わず、やさしく自然に話す",
            personaStyleCustom: "やさしく落ち着いた話し方",
            conversationDistanceCustom: "友だちみたいに気軽",
            memoryPreferenceCustom: "出来事と気持ちを短く読み返しやすく残す",
            roomThemeId: "room_default"
        )
        let buddy = BuddyProfile(displayName: "モモ", seed: buddySeed)
        let buddyState = BuddyState(buddyId: buddy.id)
        buddyState.streakDays = min(dayCount, 120)
        buddyState.intimacyLevel = min(dayCount / 2, 100)
        buddyState.lastCheckInDate = Date()
        buddyState.longTermMemories = [
            "朝の習慣": "カフェや散歩で一日を始めることが多い",
            "仕事": "打ち合わせや資料作成が多い",
            "気分転換": "短い散歩、読書、料理",
            "記録の好み": "長すぎず、あとで読み返しやすい日記が好き"
        ]

        let user = UserProfile(nickname: "たろう", onboardingCompleted: true)
        context.insert(user)
        context.insert(buddy)
        context.insert(buddyState)

        var insertedSessions = 0
        var insertedMessages = 0
        var insertedNotes = 0
        let sampleImage = makeSampleImageData()

        for dayOffset in stride(from: dayCount - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let scenario = scenario(for: dayOffset)
            let dayStart = DayBoundary.startOfAppDay(for: calendar.date(byAdding: .hour, value: 12, to: date) ?? date)

            let journal = JournalEntry(
                date: date,
                title: scenario.title,
                summaryText: scenario.summary,
                fullDiaryText: scenario.body,
                emotionTags: scenario.emotions,
                tomorrowNote: scenario.tomorrow,
                imageDataList: dayOffset % 17 == 0 ? [sampleImage] : nil,
                nameCoverage: 1.0
            )
            journal.createdAt = calendar.date(byAdding: .hour, value: 21, to: dayStart) ?? Date()
            context.insert(journal)

            for noteIndex in 0..<3 {
                let note = DiaryNote(
                    date: date,
                    fact: scenario.facts[noteIndex],
                    emotion: scenario.emotions.first ?? "落ち着き"
                )
                note.createdAt = calendar.date(byAdding: .minute, value: noteIndex * 30, to: dayStart) ?? Date()
                note.consumedInJournal = true
                context.insert(note)
                insertedNotes += 1
            }

            let session = ConversationSession(type: .daily)
            session.date = date
            session.startedAt = calendar.date(byAdding: .hour, value: 20, to: dayStart) ?? Date()
            session.endedAt = calendar.date(byAdding: .minute, value: 38, to: session.startedAt) ?? Date()
            session.completionStatus = .completed
            context.insert(session)
            insertedSessions += 1

            for (index, item) in scenario.messages.enumerated() {
                let message = ChatMessage(
                    text: item.text,
                    isFromBuddy: item.isFromBuddy,
                    imageData: dayOffset % 23 == 0 && index == 1 ? sampleImage : nil
                )
                message.timestamp = calendar.date(byAdding: .minute, value: index * 4, to: session.startedAt) ?? Date()
                message.session = session
                context.insert(message)
                session.messages.append(message)
                insertedMessages += 1
            }
            session.messageCount = scenario.messages.count
        }

        try context.save()
        return Result(
            insertedDays: dayCount,
            insertedJournalCount: dayCount,
            insertedSessionCount: insertedSessions,
            insertedMessageCount: insertedMessages,
            insertedDiaryNoteCount: insertedNotes,
            skippedBecauseDataExists: false
        )
    }

    nonisolated static func configuration(
        arguments: [String],
        environment: [String: String]
    ) -> Configuration? {
        let enabledByArgument = arguments.contains("--mybuddy-seed-long-term-data")
        let enabledByEnvironment = environment["MYBUDDY_SEED_LONG_TERM_DATA"] == "1"
        guard enabledByArgument || enabledByEnvironment else { return nil }

        let reset = arguments.contains("--mybuddy-reset-before-long-term-seed")
            || environment["MYBUDDY_RESET_BEFORE_LONG_TERM_SEED"] == "1"
        let dayCount = environment["MYBUDDY_LONG_TERM_SEED_DAYS"]
            .flatMap(Int.init)
            .map(clampedDayCount) ?? Configuration.defaultDayCount

        return Configuration(dayCount: dayCount, resetBeforeSeeding: reset)
    }

    nonisolated static func clampedDayCount(_ value: Int) -> Int {
        min(max(value, Configuration.minimumDayCount), Configuration.maximumDayCount)
    }

    private static func clearAllLocalData(in context: ModelContext) throws {
        try deleteAll(ChatMessage.self, in: context)
        try deleteAll(DiaryNote.self, in: context)
        try deleteAll(BuddyProfile.self, in: context)
        try deleteAll(BuddyState.self, in: context)
        try deleteAll(ConversationSession.self, in: context)
        try deleteAll(JournalEntry.self, in: context)
        try deleteAll(UserProfile.self, in: context)
        clearSeedRelatedDefaults()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        for item in try context.fetch(descriptor) {
            context.delete(item)
        }
    }

    private static func clearSeedRelatedDefaults(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix("home.todayJournalCreated.")
            || key.hasPrefix("journal.unread.")
            || BuddyAppearanceCandidateFactory.isDailyChangeKey(key) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func scenario(for dayOffset: Int) -> Scenario {
        let scenarios = Scenario.samples
        return scenarios[dayOffset % scenarios.count]
    }

    private static func makeSampleImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 320))
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: 420, height: 320))
            let colors = [
                UIColor(red: 0.95, green: 0.62, blue: 0.32, alpha: 1).cgColor,
                UIColor(red: 0.83, green: 0.90, blue: 0.72, alpha: 1).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
            }
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.32).cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 44, y: 48, width: 120, height: 120))
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 250, y: 120, width: 96, height: 96))
        }
        return image.jpegData(compressionQuality: 0.82) ?? Data()
    }
}

private struct Scenario {
    var title: String
    var summary: String
    var body: String
    var emotions: [String]
    var tomorrow: String
    var facts: [String]
    var messages: [(text: String, isFromBuddy: Bool)]

    static let samples: [Scenario] = [
        Scenario(
            title: "朝の散歩で整った日",
            summary: "朝に少し歩いて、仕事前の気分が軽くなった。",
            body: "朝は近所を少し歩いてから仕事を始めた。短い時間だったけれど、外の空気を吸えたことで気持ちが軽くなった。午後は資料作成に集中して、夜は早めに休む準備ができた。",
            emotions: ["すっきり", "落ち着き"],
            tomorrow: "明日も朝に少し余白を作る。",
            facts: ["朝に近所を散歩した", "午後は資料作成に集中した", "夜は早めに休む準備をした"],
            messages: [
                ("おかえり。今日はどんな一日だった？", true),
                ("朝に少し散歩してから仕事を始めたよ。", false),
                ("外に出る時間があったんだね。気分は変わった？", true),
                ("少し軽くなった。午後は資料作成が多かった。", false),
                ("その切り替え、今日の大事なところだね。", true),
                ("夜は早めに休むつもり。", false)
            ]
        ),
        Scenario(
            title: "打ち合わせが長かった日",
            summary: "長い打ち合わせで疲れたが、夜には少し落ち着いた。",
            body: "今日は打ち合わせが長く続いて、思ったより疲れた。夕方には頭が重かったけれど、帰ってから温かいものを飲んで少し落ち着いた。慌ただしさの中でも、最後は静かに戻れた。",
            emotions: ["疲れた", "安心"],
            tomorrow: "明日は予定の間に休憩を入れる。",
            facts: ["打ち合わせが長く続いた", "夕方に疲れを感じた", "帰宅後に温かいものを飲んだ"],
            messages: [
                ("今日は長かった感じ？", true),
                ("うん、打ち合わせが続いて疲れた。", false),
                ("それは消耗するね。帰ってから少し休めた？", true),
                ("温かいものを飲んで、少し落ち着いた。", false),
                ("最後に落ち着けたのはよかったね。", true),
                ("明日は休憩をちゃんと入れたい。", false)
            ]
        ),
        Scenario(
            title: "カフェで少し進んだ日",
            summary: "カフェで作業して、止まっていたことが少し進んだ。",
            body: "昼にカフェへ行って、止まっていた作業を少し進めた。大きく進んだわけではないけれど、手をつけられたことで安心した。帰り道は夕方の空がきれいで、少し得した気分になった。",
            emotions: ["前進", "うれしい"],
            tomorrow: "明日は小さく続きを進める。",
            facts: ["昼にカフェへ行った", "止まっていた作業を進めた", "帰り道に夕方の空を見た"],
            messages: [
                ("今日は何か進んだことあった？", true),
                ("昼にカフェで作業した。止まってたところに手をつけたよ。", false),
                ("手をつけられたの、大きいね。どんな気分？", true),
                ("少し安心した。帰りの空もきれいだった。", false),
                ("その小さい前進、ちゃんと残しておこう。", true),
                ("明日も続きを少しやる。", false)
            ]
        ),
        Scenario(
            title: "家で静かに過ごした日",
            summary: "外出は少なかったが、家で整える時間が取れた。",
            body: "今日は外に出る時間は少なかった。洗濯をして、部屋を少し片づけて、家の中を整えた。派手な出来事はなかったけれど、生活が少し軽くなった感じがした。",
            emotions: ["穏やか", "すっきり"],
            tomorrow: "明日は外に少し出る。",
            facts: ["外出は少なかった", "洗濯をした", "部屋を少し片づけた"],
            messages: [
                ("今日は家で過ごした感じかな？", true),
                ("うん、洗濯して部屋を少し片づけた。", false),
                ("生活が整う日だったんだね。やってみてどうだった？", true),
                ("少しすっきりした。派手ではないけどよかった。", false),
                ("そういう日もちゃんと大事だね。", true),
                ("明日は少し外に出たい。", false)
            ]
        )
    ]
}
#endif
