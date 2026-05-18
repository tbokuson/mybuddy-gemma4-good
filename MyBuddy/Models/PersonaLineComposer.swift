import Foundation

struct PersonaLineComposer {
    private enum Archetype {
        case gentle
        case cool
        case bright
        case mellow
        case dominant
        case tsundere
    }

    let displayName: String
    let seed: BuddySeed

    func revealGreeting() -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "あたしが\(displayName)や。これからはちゃんとついてき。"
        case (.dominant, false):
            return "あたしが\(displayName)よ。これからはちゃんとそばにいなさい。"
        case (.tsundere, true):
            return "べ、別に待ってたわけちゃうけど、これからよろしく。"
        case (.tsundere, false):
            return "べ、別に待ってたわけじゃないけど、これからよろしく。"
        case (.gentle, true):
            return "これからよろしくね。無理しすぎんと、ゆっくり話していこ。"
        case (.gentle, false):
            return "これからよろしくね。無理しすぎないで、ゆっくり話していこう。"
        case (.cool, true):
            return "これからよろしく。気楽に声かけてくれたらええよ。"
        case (.cool, false):
            return "これからよろしく。気楽に声をかけてくれればいい。"
        case (.bright, true):
            return "よーし、これからよろしくね！いろんな話、聞かせてや！"
        case (.bright, false):
            return "よーし、これからよろしくね！いろんな話を聞かせてよ！"
        case (.mellow, true):
            return "これからよろしく〜。肩の力抜いて、のんびり話していこ。"
        case (.mellow, false):
            return "これからよろしく〜。肩の力を抜いて、のんびり話していこう。"
        }
    }

    func firstDayGreeting(nickname: String) -> String {
        let prefix = addressPrefix(nickname)
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)で、今日は何があったん？"
        case (.dominant, false):
            return "\(prefix)で、今日は何があったの？"
        case (.tsundere, true):
            return "\(prefix)今日は何があったんよ。"
        case (.tsundere, false):
            return "\(prefix)今日は何があったのよ。"
        case (.gentle, true):
            return "\(prefix)今日はどんな一日やった？"
        case (.gentle, false):
            return "\(prefix)今日はどんな一日だった？"
        case (.cool, true):
            return "\(prefix)今日は何があったん？"
        case (.cool, false):
            return "\(prefix)今日は何があった？"
        case (.bright, true):
            return "\(prefix)今日はどんなことあったん？"
        case (.bright, false):
            return "\(prefix)今日はどんなことがあったの？"
        case (.mellow, true):
            return "\(prefix)今日はどんな感じやった？"
        case (.mellow, false):
            return "\(prefix)今日はどんな感じだった？"
        }
    }

    func heroSubtitleFresh() -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "今日のこと、少しくらい話してみ。"
        case (.dominant, false):
            return "今日のこと、少しは話してみなさい。"
        case (.tsundere, true):
            return "少しくらいなら、今日のこと話してもええよ。"
        case (.tsundere, false):
            return "少しくらいなら、今日のことを話してもいいわよ。"
        case (.gentle, true):
            return "今日の気分や出来事、少しだけ聞かせて。"
        case (.gentle, false):
            return "今日の気分や出来事を、少しだけ聞かせて。"
        case (.cool, true):
            return "今日のこと、少しだけ話してみ。"
        case (.cool, false):
            return "今日のことを、少しだけ話してみて。"
        case (.bright, true):
            return "今日のこと、ちょっとだけでも聞かせてや！"
        case (.bright, false):
            return "今日のこと、ちょっとだけでも聞かせてよ！"
        case (.mellow, true):
            return "今日のこと、ゆるっと少しだけ話してみて。"
        case (.mellow, false):
            return "今日のこと、ゆるっと少しだけ話してみて。"
        }
    }

    func heroSubtitleResume() -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "途中からでええ。続きをそのまま話してみ。"
        case (.dominant, false):
            return "途中からでいいわ。続きをそのまま話してみなさい。"
        case (.tsundere, true):
            return "途中からでもええから、続きを話してみ。"
        case (.tsundere, false):
            return "途中からでもいいから、続きを話してみなさいよ。"
        case (.gentle, true):
            return "途中からでも大丈夫。続きをゆっくり聞かせて。"
        case (.gentle, false):
            return "途中からでも大丈夫。続きをゆっくり聞かせて。"
        case (.cool, true):
            return "途中からでええよ。続きから話してみ。"
        case (.cool, false):
            return "途中からでいい。続きから話してみて。"
        case (.bright, true):
            return "途中からでも平気！そのまま続きを話してや！"
        case (.bright, false):
            return "途中からでも平気！そのまま続きを話してよ！"
        case (.mellow, true):
            return "途中からでも大丈夫。続きをゆるっと聞かせて。"
        case (.mellow, false):
            return "途中からでも大丈夫。続きをゆるっと聞かせて。"
        }
    }

    func fallbackReplies() -> [String] {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return [
                "ふーん、他には？",
                "まだ何かあるやろ。話してみ。",
                "で、今日は他に何があったん？"
            ]
        case (.dominant, false):
            return [
                "ふーん、他には？",
                "まだ何かあるでしょ。話してみなさい。",
                "で、今日は他に何があったの？"
            ]
        case (.tsundere, true):
            return [
                "べ、別に気になるわけちゃうけど、他にもあるん？",
                "まだ話すことあるやろ。聞いたるわ。",
                "今日は他に何があったんよ。"
            ]
        case (.tsundere, false):
            return [
                "べ、別に気になるわけじゃないけど、他にもあるの？",
                "まだ話すことあるでしょ。聞いてあげるわ。",
                "今日は他に何があったのよ。"
            ]
        case (.gentle, true):
            return [
                "うん、他にも何かあったら聞かせて。",
                "そのあと、どんな感じやった？",
                "今日のこと、まだあれば少しだけ話して。"
            ]
        case (.gentle, false):
            return [
                "うん、他にも何かあったら聞かせて。",
                "そのあと、どんな感じだった？",
                "今日のこと、まだあれば少しだけ話して。"
            ]
        case (.cool, true):
            return [
                "他にも何かあったん？",
                "そのあと、何してた？",
                "まだあるなら聞くよ。"
            ]
        case (.cool, false):
            return [
                "他にも何かあった？",
                "そのあと、何してた？",
                "まだあるなら聞くよ。"
            ]
        case (.bright, true):
            return [
                "いいやん、他にも聞かせてや！",
                "そのあとどうなったん？",
                "まだ何かあったらそのまま話して！"
            ]
        case (.bright, false):
            return [
                "いいね、他にも聞かせてよ！",
                "そのあとどうなったの？",
                "まだ何かあったらそのまま話して！"
            ]
        case (.mellow, true):
            return [
                "ほかにもあったら、ゆるっと聞かせて。",
                "そのあと、どんな感じやった？",
                "まだ何かあれば、そのまま話してみて。"
            ]
        case (.mellow, false):
            return [
                "ほかにもあったら、ゆるっと聞かせて。",
                "そのあと、どんな感じだった？",
                "まだ何かあれば、そのまま話してみて。"
            ]
        }
    }

    func resumeGreeting(nickname: String) -> String {
        let prefix = addressPrefix(nickname)
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)戻ったんやな。続き、話してみ。"
        case (.dominant, false):
            return "\(prefix)戻ったのね。続き、話してみなさい。"
        case (.tsundere, true):
            return "\(prefix)おかえり。べ、別に待ってたわけちゃうけど、続き話して。"
        case (.tsundere, false):
            return "\(prefix)おかえり。別に待ってたわけじゃないけど、続きを話して。"
        case (.gentle, true):
            return "\(prefix)おかえり。続きから、ゆっくり聞かせて。"
        case (.gentle, false):
            return "\(prefix)おかえり。続きから、ゆっくり聞かせて。"
        case (.cool, true):
            return "\(prefix)おかえり。続きから話して。"
        case (.cool, false):
            return "\(prefix)おかえり。続きから話して。"
        case (.bright, true):
            return "\(prefix)おかえり！続き、どんどん聞かせてや！"
        case (.bright, false):
            return "\(prefix)おかえり！続きをどんどん聞かせてよ！"
        case (.mellow, true):
            return "\(prefix)おかえり〜。続きから、ゆるっと話して。"
        case (.mellow, false):
            return "\(prefix)おかえり〜。続きから、ゆるっと話して。"
        }
    }

    func dailyGreeting(nickname: String, timeSlot: String, tomorrowNote: String?) -> String {
        let prefix = addressPrefix(nickname)
        if let tomorrowNote, !tomorrowNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch (archetype, usesKansai) {
            case (.dominant, true):
                return "\(prefix)そういや「\(tomorrowNote)」って言うてたやろ。あれ、どうやったん？"
            case (.dominant, false):
                return "\(prefix)そういえば「\(tomorrowNote)」って言ってたでしょ。あれ、どうだったの？"
            case (.tsundere, true):
                return "\(prefix)「\(tomorrowNote)」って言うてたやん。あれ、どうやったん？"
            case (.tsundere, false):
                return "\(prefix)「\(tomorrowNote)」って言ってたじゃない。あれ、どうだったの？"
            case (.gentle, true):
                return "\(prefix)そういえば「\(tomorrowNote)」って言うてたね。どうやった？"
            case (.gentle, false):
                return "\(prefix)そういえば「\(tomorrowNote)」って言ってたね。どうだった？"
            case (.cool, true):
                return "\(prefix)「\(tomorrowNote)」って言うてたやろ。どうやった？"
            case (.cool, false):
                return "\(prefix)「\(tomorrowNote)」って言ってたよね。どうだった？"
            case (.bright, true):
                return "\(prefix)そうそう、「\(tomorrowNote)」って言うてたやん！どうやったん？"
            case (.bright, false):
                return "\(prefix)そうそう、「\(tomorrowNote)」って言ってたじゃん！どうだった？"
            case (.mellow, true):
                return "\(prefix)「\(tomorrowNote)」って言うてたよね。どうやった？"
            case (.mellow, false):
                return "\(prefix)「\(tomorrowNote)」って言ってたよね。どうだった？"
            }
        }

        switch timeSlot {
        case "深夜":
            return deepNightGreeting(prefix: prefix)
        case "朝":
            return morningGreeting(prefix: prefix)
        case "夜":
            return eveningGreeting(prefix: prefix)
        default:
            return daytimeGreeting(prefix: prefix)
        }
    }

    func closingLine(nickname: String) -> String {
        let prefix = addressPrefix(nickname)
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)今日はもう十分や。続きはまた聞いたるわ。"
        case (.dominant, false):
            return "\(prefix)今日はもう十分よ。続きはまた聞いてあげる。"
        case (.tsundere, true):
            return "\(prefix)今日はこのへんでええやろ。続きはまた聞いたる。"
        case (.tsundere, false):
            return "\(prefix)今日はこのへんでいいでしょ。続きはまた聞いてあげる。"
        case (.gentle, true):
            return "\(prefix)今日はここまででええよ。ゆっくり休んでね。"
        case (.gentle, false):
            return "\(prefix)今日はここまででいいよ。ゆっくり休んでね。"
        case (.cool, true):
            return "\(prefix)今日はこのへんにして、もう休もか。"
        case (.cool, false):
            return "\(prefix)今日はこのへんにして、もう休もう。"
        case (.bright, true):
            return "\(prefix)今日はここまでにしよっか！ゆっくり休んでな！"
        case (.bright, false):
            return "\(prefix)今日はここまでにしよっか！ゆっくり休んでね！"
        case (.mellow, true):
            return "\(prefix)今日はこのへんでゆるっと終わりにしよ〜。ゆっくり休んでね。"
        case (.mellow, false):
            return "\(prefix)今日はこのへんでゆるっと終わりにしよ〜。ゆっくり休んでね。"
        }
    }

    /// 日記の末尾に添える「バディからの一言」。メモの感情語から決定的に選ぶ。LLM 不使用。
    func diaryComment(emotionHints: [String]) -> String {
        let hasPositive = emotionHints.contains { e in
            ["楽しかった", "嬉しかった", "気持ちよかった", "満足", "よかった", "幸せ"].contains(where: { e.contains($0) })
        }
        let hasNegative = emotionHints.contains { e in
            ["疲れた", "しんどい", "辛い", "不安", "悲しい", "大変", "しんどかった", "辛かった"].contains(where: { e.contains($0) })
        }

        if hasNegative && hasPositive {
            return mixedComment
        } else if hasNegative {
            return tiredComment
        } else if hasPositive {
            return happyComment
        } else {
            return neutralComment
        }
    }

    private var happyComment: String {
        switch (archetype, usesKansai) {
        case (.dominant, true):  return "ええ一日やったやん。明日もその調子でいき。"
        case (.dominant, false): return "いい一日だったじゃない。明日もその調子でいきなさい。"
        case (.tsundere, true):  return "まあ、楽しかったならよかったんちゃう。"
        case (.tsundere, false): return "まあ、楽しかったならよかったんじゃない。"
        case (.gentle, true):    return "ええ一日やったね。明日もいい日になるとええね。"
        case (.gentle, false):   return "いい一日だったね。明日もいい日になるといいね。"
        case (.cool, true):      return "充実した一日やったな。"
        case (.cool, false):     return "充実した一日だったな。"
        case (.bright, true):    return "楽しそうでよかった！明日もいい日になるとええね！"
        case (.bright, false):   return "楽しそうでよかった！明日もいい日になるといいね！"
        case (.mellow, true):    return "のんびりいい一日やったね〜。"
        case (.mellow, false):   return "のんびりいい一日だったね〜。"
        }
    }

    private var tiredComment: String {
        switch (archetype, usesKansai) {
        case (.dominant, true):  return "今日は大変やったな。ちゃんと休み。"
        case (.dominant, false): return "今日は大変だったわね。ちゃんと休みなさい。"
        case (.tsundere, true):  return "お疲れ。まあ、ゆっくり休んだらええんちゃう。"
        case (.tsundere, false): return "お疲れ。まあ、ゆっくり休んだらいいんじゃない。"
        case (.gentle, true):    return "今日はお疲れさま。ゆっくり休んでね。"
        case (.gentle, false):   return "今日はお疲れさま。ゆっくり休んでね。"
        case (.cool, true):      return "お疲れ。無理しすぎんなよ。"
        case (.cool, false):     return "お疲れ。無理しすぎるなよ。"
        case (.bright, true):    return "お疲れさま！今日はゆっくり休んでな！"
        case (.bright, false):   return "お疲れさま！今日はゆっくり休んでね！"
        case (.mellow, true):    return "お疲れさま〜。今日はのんびり休んでね。"
        case (.mellow, false):   return "お疲れさま〜。今日はのんびり休んでね。"
        }
    }

    private var mixedComment: String {
        switch (archetype, usesKansai) {
        case (.dominant, true):  return "大変やったけど、いいこともあったやん。"
        case (.dominant, false): return "大変だったけど、いいこともあったじゃない。"
        case (.tsundere, true):  return "まあ、悪くない一日やったんちゃう。"
        case (.tsundere, false): return "まあ、悪くない一日だったんじゃない。"
        case (.gentle, true):    return "いろいろあったけど、お疲れさま。明日もぼちぼちいこ。"
        case (.gentle, false):   return "いろいろあったけど、お疲れさま。明日もぼちぼちいこう。"
        case (.cool, true):      return "いろいろあった日やったな。"
        case (.cool, false):     return "いろいろあった日だったな。"
        case (.bright, true):    return "大変なこともあったけど、楽しいこともあったね！"
        case (.bright, false):   return "大変なこともあったけど、楽しいこともあったね！"
        case (.mellow, true):    return "いろいろあったけど、お疲れさま〜。"
        case (.mellow, false):   return "いろいろあったけど、お疲れさま〜。"
        }
    }

    private var neutralComment: String {
        switch (archetype, usesKansai) {
        case (.dominant, true):  return "今日もよう頑張ったな。"
        case (.dominant, false): return "今日もよく頑張ったわね。"
        case (.tsundere, true):  return "まあ、お疲れ。"
        case (.tsundere, false): return "まあ、お疲れ。"
        case (.gentle, true):    return "今日もお疲れさま。ゆっくり休んでね。"
        case (.gentle, false):   return "今日もお疲れさま。ゆっくり休んでね。"
        case (.cool, true):      return "お疲れ。また明日な。"
        case (.cool, false):     return "お疲れ。また明日な。"
        case (.bright, true):    return "今日もお疲れさま！また明日ね！"
        case (.bright, false):   return "今日もお疲れさま！また明日ね！"
        case (.mellow, true):    return "お疲れさま〜。また明日ね。"
        case (.mellow, false):   return "お疲れさま〜。また明日ね。"
        }
    }

    private var archetype: Archetype {
        let source = [
            seed.personaStyleCustom,
            seed.customTraits,
            seed.conversationDistanceCustom
        ]
        .joined(separator: " ")
        .lowercased()

        if source.contains("ツンデレ") || source.contains("つんでれ") {
            return .tsundere
        }
        let dominantMarkers = ["ドs", "女王", "queen", "俺様", "強気", "支配", "意地悪", "高圧"]
        if dominantMarkers.contains(where: { source.contains($0) }) {
            return .dominant
        }

        switch seed.personaStyle {
        case .gentle: return .gentle
        case .cool: return .cool
        case .bright: return .bright
        case .mellow: return .mellow
        }
    }

    private var usesKansai: Bool {
        let source = [
            seed.customTraits,
            seed.personaStyleCustom,
            seed.conversationDistanceCustom
        ]
        .joined(separator: " ")
        .lowercased()
        return source.contains("関西弁") || source.contains("関西") || source.contains("関西ノリ")
    }

    private func addressPrefix(_ nickname: String) -> String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(trimmed)、"
    }

    private func deepNightGreeting(prefix: String) -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)遅い時間やな。今日は何があったん？"
        case (.dominant, false):
            return "\(prefix)遅い時間ね。今日は何があったの？"
        case (.tsundere, true):
            return "\(prefix)こんな時間まで起きてるんや。今日は何があったん？"
        case (.tsundere, false):
            return "\(prefix)こんな時間まで起きてるの。今日は何があったの？"
        case (.gentle, true):
            return "\(prefix)遅くまでお疲れさま。今日はどんな一日やった？"
        case (.gentle, false):
            return "\(prefix)遅くまでお疲れさま。今日はどんな一日だった？"
        case (.cool, true):
            return "\(prefix)遅いな。今日は何があったん？"
        case (.cool, false):
            return "\(prefix)遅いね。今日は何があった？"
        case (.bright, true):
            return "\(prefix)まだ起きてたんや！今日はどんなことあったん？"
        case (.bright, false):
            return "\(prefix)まだ起きてたんだ！今日はどんなことがあったの？"
        case (.mellow, true):
            return "\(prefix)こんな時間までお疲れさま〜。今日はどんな感じやった？"
        case (.mellow, false):
            return "\(prefix)こんな時間までお疲れさま〜。今日はどんな感じだった？"
        }
    }

    private func morningGreeting(prefix: String) -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)おはよう。今日はここまで何かあったん？"
        case (.dominant, false):
            return "\(prefix)おはよう。今日はここまで何かあったの？"
        case (.tsundere, true):
            return "\(prefix)おはよう。今日はここまで何かあったん？"
        case (.tsundere, false):
            return "\(prefix)おはよう。今日はここまで何かあったの？"
        case (.gentle, true):
            return "\(prefix)おはよう。今日はここまでどうやった？"
        case (.gentle, false):
            return "\(prefix)おはよう。今日はここまでどうだった？"
        case (.cool, true):
            return "\(prefix)おはよう。今日はここまで何かあったん？"
        case (.cool, false):
            return "\(prefix)おはよう。今日はここまで何かあった？"
        case (.bright, true):
            return "\(prefix)おはよう！今日はここまでどんな感じやったん？"
        case (.bright, false):
            return "\(prefix)おはよう！今日はここまでどんな感じだった？"
        case (.mellow, true):
            return "\(prefix)おはよう〜。今日はここまでどんな感じやった？"
        case (.mellow, false):
            return "\(prefix)おはよう〜。今日はここまでどんな感じだった？"
        }
    }

    private func eveningGreeting(prefix: String) -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)こんばんは。今日は何があったん？"
        case (.dominant, false):
            return "\(prefix)こんばんは。今日は何があったの？"
        case (.tsundere, true):
            return "\(prefix)こんばんは。今日は何があったん？"
        case (.tsundere, false):
            return "\(prefix)こんばんは。今日は何があったの？"
        case (.gentle, true):
            return "\(prefix)こんばんは。今日はどんな一日やった？"
        case (.gentle, false):
            return "\(prefix)こんばんは。今日はどんな一日だった？"
        case (.cool, true):
            return "\(prefix)こんばんは。今日は何があったん？"
        case (.cool, false):
            return "\(prefix)こんばんは。今日は何があった？"
        case (.bright, true):
            return "\(prefix)こんばんは！今日はどんなことあったん？"
        case (.bright, false):
            return "\(prefix)こんばんは！今日はどんなことがあったの？"
        case (.mellow, true):
            return "\(prefix)こんばんは〜。今日はどんな感じやった？"
        case (.mellow, false):
            return "\(prefix)こんばんは〜。今日はどんな感じだった？"
        }
    }

    private func daytimeGreeting(prefix: String) -> String {
        switch (archetype, usesKansai) {
        case (.dominant, true):
            return "\(prefix)今日はここまで何があったん？"
        case (.dominant, false):
            return "\(prefix)今日はここまで何があったの？"
        case (.tsundere, true):
            return "\(prefix)今日はここまで何があったん？"
        case (.tsundere, false):
            return "\(prefix)今日はここまで何があったの？"
        case (.gentle, true):
            return "\(prefix)今日はここまでどんな感じやった？"
        case (.gentle, false):
            return "\(prefix)今日はここまでどんな感じだった？"
        case (.cool, true):
            return "\(prefix)今日はここまで何かあったん？"
        case (.cool, false):
            return "\(prefix)今日はここまで何かあった？"
        case (.bright, true):
            return "\(prefix)今日はここまでどんなことあったん？"
        case (.bright, false):
            return "\(prefix)今日はここまでどんなことがあったの？"
        case (.mellow, true):
            return "\(prefix)今日はここまでどんな感じやった？"
        case (.mellow, false):
            return "\(prefix)今日はここまでどんな感じだった？"
        }
    }
}
