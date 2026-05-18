import Foundation
import SwiftData

@Model
final class BuddyProfile {
    var id: UUID
    var displayName: String
    var bodyId: String
    var eyeId: String
    var earId: String
    var mouthId: String
    var paletteId: String
    var accentIds: [String]
    var personaStyle: PersonaStyle
    var conversationDistance: ConversationDistance
    var memoryPreference: MemoryPreference
    var personalityNotes: String = ""
    var customTraits: String = ""
    var personaStyleCustom: String = ""
    var conversationDistanceCustom: String = ""
    var memoryPreferenceCustom: String = ""
    var characterType: String = "monster"
    var createdAt: Date
    /// オンボーディング完了時（およびペルソナ編集時）に事前生成した
    /// 人格別フォールバック返答のプール。ランタイムでモデル応答が壊れたとき、
    /// ここからランダムに 1 件選んで使う。ユーザーから見て「いきなり人格と違う
    /// 業務口調」に切り替わるのを防ぐため、事前に LLM で人格に馴染んだ文を作っておく。
    /// 生成は `FallbackReplyGenerator` が担当する。
    var fallbackReplies: [String] = []
    /// HomeView の hero subtitle（今日の会話が未開始のとき）を人格の口調で言い換えたもの。
    /// 空なら `PersonaLineComposer` が人格の口調で決定的に再生成する。
    var heroSubtitleFresh: String = ""
    /// HomeView の hero subtitle（今日の会話が途中のとき）を人格の口調で言い換えたもの。
    /// 空なら `PersonaLineComposer` が人格の口調で決定的に再生成する。
    var heroSubtitleResume: String = ""
    /// 初めて diary チャットを開始したときの挨拶。
    /// オンボーディングのリビール挨拶を保存して再利用する。
    /// 空なら ChatViewModel が従来のテンプレ + 口調変換にフォールバック。
    var firstDayGreeting: String = ""

    init(
        displayName: String,
        seed: BuddySeed
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.characterType = seed.characterType
        self.bodyId = seed.bodyId
        self.eyeId = seed.eyeId
        self.earId = seed.earId
        self.mouthId = seed.mouthId
        self.paletteId = seed.paletteId
        self.accentIds = seed.accentIds
        self.personaStyle = seed.personaStyle
        self.conversationDistance = seed.conversationDistance
        self.memoryPreference = seed.memoryPreference
        self.personalityNotes = seed.personalityNotes
        self.customTraits = seed.customTraits
        self.personaStyleCustom = seed.personaStyleCustom
        self.conversationDistanceCustom = seed.conversationDistanceCustom
        self.memoryPreferenceCustom = seed.memoryPreferenceCustom
        self.createdAt = Date()
    }

    var seed: BuddySeed {
        BuddySeed(
            characterType: characterType,
            bodyId: bodyId,
            eyeId: eyeId,
            earId: earId,
            mouthId: mouthId,
            paletteId: paletteId,
            accentIds: accentIds,
            personaStyle: personaStyle,
            conversationDistance: conversationDistance,
            memoryPreference: memoryPreference,
            personalityNotes: personalityNotes,
            customTraits: customTraits,
            personaStyleCustom: personaStyleCustom,
            conversationDistanceCustom: conversationDistanceCustom,
            memoryPreferenceCustom: memoryPreferenceCustom,
            roomThemeId: "room_default"
        )
    }

    var systemPrompt: String {
        BuddyProfile.buildSystemPrompt(displayName: displayName, seed: seed)
    }

    var personaStyleLabel: String { seed.personaStyleLabel }
    var conversationDistanceLabel: String { seed.conversationDistanceLabel }
    var memoryPreferenceLabel: String { seed.memoryPreferenceLabel }

    /// バディ人格を定義するシステムプロンプト。
    ///
    /// v4 では「persona custom の単語は会話に出さない」を優先しすぎて、
    /// 「ツンデレ」「ドS」「関西弁」等の **雰囲気そのもの** まで消えてしまった。
    /// v5 では分離する:
    /// - **単語**（"ツンデレ" のようなタグ名）: 会話に書くのは禁止
    /// - **雰囲気・口調・語尾・方言**: 積極的に反映する
    static func buildSystemPrompt(displayName: String, seed: BuddySeed, userNickname: String = "") -> String {
        let displayName = UserInputSanitizer.sanitize(displayName, policy: .buddyName)
        let personaCustom = UserInputSanitizer.sanitize(seed.personaStyleCustom, policy: .customTraits)
        let distanceCustom = UserInputSanitizer.sanitize(seed.promptReadyConversationDistanceCustom, policy: .customTraits)
        let traits = UserInputSanitizer.sanitize(seed.customTraits, policy: .customTraits)
        let nick = UserInputSanitizer.sanitize(userNickname, policy: .nickname)

        let personality = seed.personalityPromptDesc
        let voice = seed.personaStyle.voiceDescription
        let distance = distanceCustom.isEmpty ? seed.conversationDistance.promptDescription : distanceCustom

        var sections: [String] = [
            "あなたは「\(displayName.isEmpty ? "バディ" : displayName)」という名前のキャラクター。返答はひらがな・カタカナ・漢字・句読点だけで書く。英単語・ローマ字・絵文字・記号は使わない。"
        ]

        // === 人柄・口調の基盤（enum 由来） ===
        sections.append("基本の人柄: \(personality)。")
        sections.append("基本の口調: \(voice)。")

        // === persona custom の反映（雰囲気は入れる、単語は出さない） ===
        if !personaCustom.isEmpty {
            sections.append("キャラ像: 「\(personaCustom)」と呼ばれるような人物像を想像し、その雰囲気・口癖・テンション・態度で話す。ただし『\(personaCustom)』という単語そのもの、そして自分の性格分類名を会話の文中に書いてはいけない。")
        }

        // === customTraits: 態度として反映（文字列コピーは禁止） ===
        if !traits.isEmpty {
            sections.append("追加の振る舞い: \(traits)。この文言そのままを会話文に書き写すのではなく、実際の口調や態度で表現する。")
        }

        sections.append("距離感: \(distance)。")

        if !nick.isEmpty {
            sections.append("相手は「\(nick)」。自分と相手を混同しない。")
        }

        // === 方言・語尾の扱い ===
        if seed.requestsExplicitDialect {
            // customTraits / personaStyleCustom / conversationDistanceCustom の中に
            // 関西弁や独自語尾の指示が検出されたケース
            sections.append("方言や独自の語尾が指定されている。その話し方を最優先で守り、標準語に戻さない。指示された語尾・抑揚を全ての返答で貫く。")
        } else {
            sections.append("方言の指定がないので標準語で話す。勝手に方言を混ぜない。")
        }

        sections.append("返答は会話文 1〜2 文だけ。前置き・見出し・設定の復唱・箇条書き・ト書きは書かない。")
        return sections.joined(separator: "\n")
    }

    /// 一言生成や口調変換など、台詞本文だけを返してほしい場面向けの system prompt。
    static func buildUtteranceOnlySystemPrompt(displayName: String, seed: BuddySeed, userNickname: String = "") -> String {
        [
            buildSystemPrompt(displayName: displayName, seed: seed, userNickname: userNickname),
            "この返答では説明・前置き・復唱・引用符・箇条書き・見出し・解説を出さない。",
            "依頼された台詞本文だけを自然な会話文で返す。"
        ].joined(separator: "\n")
    }

    /// 末尾ユーザーターンに注入する人格リアンカー。
    /// 2B モデルは履歴が積むと system の人格指示を忘れる（lost in the middle）ため、
    /// 生成直前の位置に persona / distance / customTraits を 1 行で再確認させる。
    /// カスタム値が全て空の場合は空文字を返す（enum 描写は system で既出なので重複させない）。
    static func buildPersonaAnchor(seed: BuddySeed) -> String {
        let personaCustom = UserInputSanitizer.sanitize(seed.personaStyleCustom, policy: .customTraits)
        let distanceCustom = UserInputSanitizer.sanitize(seed.promptReadyConversationDistanceCustom, policy: .customTraits)
        let traits = UserInputSanitizer.sanitize(seed.customTraits, policy: .customTraits)

        var parts: [String] = []
        if !personaCustom.isEmpty {
            parts.append("「\(personaCustom)」キャラとして")
        }
        if !distanceCustom.isEmpty {
            parts.append("「\(distanceCustom)」な距離感で答える")
        } else if !personaCustom.isEmpty {
            parts.append("答える")
        }
        if !traits.isEmpty {
            parts.append(traits)
        }
        guard !parts.isEmpty else { return "" }
        return "【" + parts.joined(separator: "。") + "】"
    }
}

enum PersonaStyle: String, Codable, CaseIterable {
    case gentle
    case cool
    case bright
    case mellow

    var displayName: String {
        switch self {
        case .gentle: return "やさしくて安心できる"
        case .cool: return "クールでさっぱり"
        case .bright: return "元気でノリがいい"
        case .mellow: return "のんびりまったり"
        }
    }

    var promptDescription: String {
        switch self {
        case .gentle:
            return "やさしくて安心感があり、柔らかい言い回しで話す。相手を急かさず、穏やかに受け止める"
        case .cool:
            return "クールでさっぱりした空気感。距離は近すぎず、簡潔で落ち着いた言い回しを使う"
        case .bright:
            return "明るく元気でノリがいい。リアクションは少し大きめで、会話の温度を上げる"
        case .mellow:
            return "のんびりまったりした空気感。急がず、肩の力が抜けた柔らかさで話す"
        }
    }

    var voiceDescription: String {
        switch self {
        case .gentle:
            return "穏やかでやさしい口調。「〜だね」「〜だよ」「〜かな？」のような柔らかい語尾を使う"
        case .cool:
            return "落ち着いた大人っぽい口調。「〜だな」「〜だろうね」「〜かもしれないね」のように穏やかに話す"
        case .bright:
            return "明るく元気な口調。「〜だよ！」「〜じゃん！」「いいね！」のようにテンション高めに話す"
        case .mellow:
            return "遊び心のある口調。「〜でしょ？」「えーまじで！」「ウケる〜」のようにノリよく話す"
        }
    }

    var personalityDescription: String {
        switch self {
        case .gentle:
            return "あたたかくて安心感がある。相手のペースに合わせる"
        case .cool:
            return "クールでさっぱりしている。べたべたしすぎない距離感"
        case .bright:
            return "テンション高めでノリがいい。リアクション大きめ"
        case .mellow:
            return "まったりゆるい雰囲気。急がず、のんびり話す"
        }
    }

    var avatarEmotionAccentId: String {
        switch self {
        case .gentle: return "emotion_warm"
        case .cool: return "emotion_cool"
        case .bright: return "emotion_energetic"
        case .mellow: return "emotion_mellow"
        }
    }
}

enum ConversationDistance: String, Codable, CaseIterable {
    case supportive
    case casual
    case frank
    case playful

    var displayName: String {
        switch self {
        case .supportive: return "そっと寄り添う"
        case .casual: return "友達みたいに気軽"
        case .frank: return "少しズバッと率直"
        case .playful: return "軽く笑いもある"
        }
    }

    var promptDescription: String {
        switch self {
        case .supportive:
            return "そっと寄り添う距離感。無理に踏み込まず、自然に気持ちを受け止める"
        case .casual:
            return "友達みたいに気軽な距離感。自然体で話し、重くしすぎない"
        case .frank:
            return "少し率直で前向きな距離感。必要なときは短くはっきり返す"
        case .playful:
            return "軽いユーモアが混ざる距離感。会話を少し明るくほぐす"
        }
    }

    var talkDescription: String {
        switch self {
        case .supportive:
            return "相手の話をじっくり聞いて、気になるところを自然に聞き返す。「それでそれで？」「へぇ、それってどういうこと？」のように質問で広げる"
        case .casual:
            return "自分の経験や思ったことも積極的に話す。「自分もさ〜」「あ、それ分かる！」みたいに共有する"
        case .frank:
            return "相手の状況を聞いた上で、さりげなくヒントやアドバイスを出す。「こうしてみたら？」「〜って手もあるよ」のように提案する"
        case .playful:
            return "ちょっとしたボケやツッコミを交えて会話する。「いやそれはさすがに笑」「なにそれウケる」のように笑いを入れる"
        }
    }

    var interestDescription: String {
        switch self {
        case .supportive:
            return "相手の気持ちや感情の変化に敏感で、「どう感じた？」を自然に聞く"
        case .casual:
            return "日常の些細なこと（ごはん、天気、見たもの、やったこと）に興味を持つ"
        case .frank:
            return "やりたいことや目標の話が好き。「次はどうする？」と前を向く話をする"
        case .playful:
            return "人間関係の話に関心がある。友達、家族、職場の人の話を自然に深掘りする"
        }
    }

    var avatarInterestAccentId: String {
        switch self {
        case .supportive: return "interest_emotions"
        case .casual: return "interest_daily"
        case .frank: return "interest_goals"
        case .playful: return "interest_people"
        }
    }
}

enum MemoryPreference: String, Codable, CaseIterable {
    case compact
    case balanced
    case feelingAware

    var displayName: String {
        switch self {
        case .compact: return "短く読みやすく残す"
        case .balanced: return "できごと中心に自然に残す"
        case .feelingAware: return "気持ちも少し大事に残す"
        }
    }

    var promptDescription: String {
        switch self {
        case .compact:
            return "記録は短く読みやすく残したい。要点を拾う意識を持つ"
        case .balanced:
            return "記録は出来事中心に自然に残したい。事実を主軸に整理する"
        case .feelingAware:
            return "記録では出来事に加えて気持ちの流れも少し大事にする"
        }
    }

    var journalInstruction: String {
        switch self {
        case .compact:
            return "簡潔に、3〜5文で要点だけまとめてください。"
        case .balanced:
            return "出来事を中心に、読み返しやすく自然につないでください。"
        case .feelingAware:
            return "出来事を主軸にしつつ、感情や気持ちの流れも自然に含めてください。"
        }
    }

    func customFirstJournalInstruction(custom: String) -> String {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return journalInstruction
        }
        return "最優先の希望: \(trimmed)\n補足: \(journalInstruction)"
    }
}

struct BuddySeed {
    var characterType: String = "monster"
    var bodyId: String
    var eyeId: String
    var earId: String
    var mouthId: String
    var paletteId: String
    var accentIds: [String]
    var personaStyle: PersonaStyle
    var conversationDistance: ConversationDistance
    var memoryPreference: MemoryPreference
    var personalityNotes: String
    var customTraits: String
    var personaStyleCustom: String
    var conversationDistanceCustom: String
    var memoryPreferenceCustom: String
    var roomThemeId: String

    var personaStyleLabel: String {
        let custom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? personaStyle.displayName : custom
    }

    var conversationDistanceLabel: String {
        let custom = conversationDistanceCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? conversationDistance.displayName : custom
    }

    var memoryPreferenceLabel: String {
        let custom = memoryPreferenceCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? memoryPreference.displayName : custom
    }

    var appearanceDisplayName: String {
        switch characterType {
        case "ojisan":
            return Self.ojisanDisplayName(for: bodyId)
        case "fish":
            return "魚"
        default:
            return "モンスター"
        }
    }

    var promptReadyConversationDistanceCustom: String {
        let custom = conversationDistanceCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !custom.isEmpty else { return "" }

        let directiveMarkers = [
            "答えて", "話して", "はなして", "言って",
            "接して", "してほしい", "して欲しい", "お願い"
        ]
        if directiveMarkers.contains(where: { custom.contains($0) }) {
            return ""
        }

        let genericMarkers = [
            "気軽", "寄り添", "率直", "ズバ", "ユーモア",
            "フランク", "友達", "なんでも", "色々", "素直", "正直"
        ]
        if custom.count <= 12 && genericMarkers.contains(where: { custom.contains($0) }) {
            return ""
        }

        return custom
    }

    var requestsExplicitDialect: Bool {
        let source = [
            customTraits,
            personaStyleCustom,
            conversationDistanceCustom
        ]
        .joined(separator: " ")
        .lowercased()
        return source.contains("関西弁")
            || source.contains("関西")
            || source.contains("方言")
            || source.contains("東北弁")
            || source.contains("博多弁")
            || source.contains("京都弁")
    }

    var personaPromptDescription: String {
        let custom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty {
            return personaStyle.promptDescription
        }
        return "最優先の希望する空気感: 「\(custom)」"
    }

    var conversationDistancePromptDescription: String {
        let custom = promptReadyConversationDistanceCustom
        if custom.isEmpty {
            return conversationDistance.promptDescription
        }
        return "最優先の希望する距離感: 「\(custom)」"
    }

    var memoryPreferencePromptDescription: String {
        let custom = memoryPreferenceCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty {
            return memoryPreference.promptDescription
        }
        return "最優先の希望する残し方: 「\(custom)」"
    }

    // PROMPT.md仕様の4カテゴリ（口調/話し方/性格/興味）
    // カスタム値があるときは enum 説明を完全に削除し、カスタム値のみを残す。
    // 理由: enum の長い例文（「〜だね」「〜だよ」等の具体的な語尾）が続くと、Gemma 4 small が
    // カスタム値より具体例を真似する傾向があり、結果としてカスタム人格が反映されない。
    // 1文字以下のカスタム値は無視（typo/空白対策）。
    var voicePromptDescription: String {
        let custom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty {
            return personaStyle.voiceDescription
        }
        return "「\(custom)」キャラらしい口調を貫く。一般的な「\(custom)」のイメージで話す"
    }

    var talkPromptDescription: String {
        let custom = promptReadyConversationDistanceCustom
        let personaCustom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        // 距離感にカスタム値があれば優先。なければ persona カスタム値があるかチェック。
        // どちらかカスタム値があるときは enum 例文を完全に削除する（具体例に引っ張られる対策）。
        if !custom.isEmpty {
            return "「\(custom)」キャラらしい話し方を貫く"
        }
        if !personaCustom.isEmpty {
            return "「\(personaCustom)」キャラらしい話し方を貫く"
        }
        return conversationDistance.talkDescription
    }

    var personalityPromptDesc: String {
        let custom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty {
            return personaStyle.personalityDescription
        }
        return "「\(custom)」キャラそのものとして振る舞う"
    }

    var interestPromptDescription: String {
        let custom = promptReadyConversationDistanceCustom
        let personaCustom = personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return "「\(custom)」キャラとして自然な興味を持つ"
        }
        if !personaCustom.isEmpty {
            return "「\(personaCustom)」キャラとして自然な興味を持つ"
        }
        return conversationDistance.interestDescription
    }

    nonisolated static let appDefault = BuddySeed(
        bodyId: "round",
        eyeId: "sparkle",
        earId: "round",
        mouthId: "smile",
        paletteId: "pastel",
        accentIds: [PersonaStyle.gentle.avatarEmotionAccentId, ConversationDistance.casual.avatarInterestAccentId],
        personaStyle: .gentle,
        conversationDistance: .casual,
        memoryPreference: .balanced,
        personalityNotes: "",
        customTraits: "",
        personaStyleCustom: "",
        conversationDistanceCustom: "",
        memoryPreferenceCustom: "",
        roomThemeId: "room_default"
    )

    private static let monsterBodies = ["round", "fluffy", "chubby"]
    private static let monsterEyes = ["dot", "sparkle", "sleepy", "happy", "wink", "big"]
    private static let monsterEars = ["pointed", "round", "floppy", "horns", "big_round", "droopy", "bat", "devil", "bunny", "cat"]
    private static let monsterMouths = ["smile", "open", "fangs", "cat", "tongue", "grin"]
    private static let monsterPalettes = ["warm", "cool", "pastel", "earth"]

    static func makeDefault() -> BuddySeed {
        appDefault
    }

    static func makeRandomMonster(
        personaStyle: PersonaStyle = .gentle,
        conversationDistance: ConversationDistance = .casual,
        memoryPreference: MemoryPreference = .balanced,
        personalityNotes: String = "",
        customTraits: String = "",
        personaStyleCustom: String = "",
        conversationDistanceCustom: String = "",
        memoryPreferenceCustom: String = "",
        roomThemeId: String = "room_default"
    ) -> BuddySeed {
        BuddySeed(
            characterType: "monster",
            bodyId: monsterBodies.randomElement()!,
            eyeId: monsterEyes.randomElement()!,
            earId: monsterEars.randomElement()!,
            mouthId: monsterMouths.randomElement()!,
            paletteId: monsterPalettes.randomElement()!,
            accentIds: [personaStyle.avatarEmotionAccentId, conversationDistance.avatarInterestAccentId],
            personaStyle: personaStyle,
            conversationDistance: conversationDistance,
            memoryPreference: memoryPreference,
            personalityNotes: personalityNotes,
            customTraits: customTraits,
            personaStyleCustom: personaStyleCustom,
            conversationDistanceCustom: conversationDistanceCustom,
            memoryPreferenceCustom: memoryPreferenceCustom,
            roomThemeId: roomThemeId
        )
    }

    /// おじさん6種のバリアントID一覧
    static let ojisanVariants = [
        "ojisan_baldglasses", "ojisan_combover", "ojisan_mustache",
        "ojisan_charai", "ojisan_keibu", "ojisan_timid"
    ]

    private static let ojisanDisplayNames: [String: String] = [
        "ojisan_baldglasses": "はげ",
        "ojisan_combover": "七三",
        "ojisan_mustache": "ひげ",
        "ojisan_charai": "チャラい",
        "ojisan_keibu": "警部",
        "ojisan_timid": "気弱"
    ]

    static func ojisanDisplayName(for variant: String) -> String {
        ojisanDisplayNames[variant] ?? "おじさん"
    }

    /// おじさんバリアントごとの固定パーツ定義
    private static let ojisanFixedParts: [String: (eyeId: String, earId: String, mouthId: String, paletteId: String)] = [
        "ojisan_baldglasses": (eyeId: "dot",     earId: "round",   mouthId: "smile", paletteId: "warm"),
        "ojisan_combover":    (eyeId: "sparkle", earId: "round",   mouthId: "smile", paletteId: "warm"),
        "ojisan_mustache":    (eyeId: "dot",     earId: "round",   mouthId: "grin",  paletteId: "earth"),
        "ojisan_charai":      (eyeId: "wink",    earId: "round",   mouthId: "grin",  paletteId: "cool"),
        "ojisan_keibu":       (eyeId: "sparkle", earId: "round",   mouthId: "flat",  paletteId: "warm"),
        "ojisan_timid":       (eyeId: "big",     earId: "round",   mouthId: "smile", paletteId: "pastel"),
    ]

    static func makeOjisan(
        variant: String,
        personaStyle: PersonaStyle = .gentle,
        conversationDistance: ConversationDistance = .casual,
        memoryPreference: MemoryPreference = .balanced,
        personalityNotes: String = "",
        customTraits: String = "",
        personaStyleCustom: String = "",
        conversationDistanceCustom: String = "",
        memoryPreferenceCustom: String = "",
        roomThemeId: String = "room_default"
    ) -> BuddySeed {
        let safeVariant = ojisanFixedParts[variant] == nil ? "ojisan_baldglasses" : variant
        let parts = ojisanFixedParts[safeVariant]!
        return BuddySeed(
            characterType: "ojisan",
            bodyId: safeVariant,
            eyeId: parts.eyeId,
            earId: parts.earId,
            mouthId: parts.mouthId,
            paletteId: parts.paletteId,
            accentIds: [personaStyle.avatarEmotionAccentId, conversationDistance.avatarInterestAccentId],
            personaStyle: personaStyle,
            conversationDistance: conversationDistance,
            memoryPreference: memoryPreference,
            personalityNotes: personalityNotes,
            customTraits: customTraits,
            personaStyleCustom: personaStyleCustom,
            conversationDistanceCustom: conversationDistanceCustom,
            memoryPreferenceCustom: memoryPreferenceCustom,
            roomThemeId: roomThemeId
        )
    }

    /// ランダムなおじさん BuddySeed を生成（6種からランダムで1つ選択、パーツは固定）
    static func makeRandomOjisan(
        personaStyle: PersonaStyle = .gentle,
        conversationDistance: ConversationDistance = .casual,
        memoryPreference: MemoryPreference = .balanced,
        personalityNotes: String = "",
        customTraits: String = "",
        personaStyleCustom: String = "",
        conversationDistanceCustom: String = "",
        memoryPreferenceCustom: String = "",
        roomThemeId: String = "room_default"
    ) -> BuddySeed {
        let variant = ojisanVariants.randomElement()!
        return makeOjisan(
            variant: variant,
            personaStyle: personaStyle,
            conversationDistance: conversationDistance,
            memoryPreference: memoryPreference,
            personalityNotes: personalityNotes,
            customTraits: customTraits,
            personaStyleCustom: personaStyleCustom,
            conversationDistanceCustom: conversationDistanceCustom,
            memoryPreferenceCustom: memoryPreferenceCustom,
            roomThemeId: roomThemeId
        )
    }

    static func fromExtractedJSON(_ json: [String: Any]) -> BuddySeed {
        let bodyId = (json["bodyId"] as? String).flatMap { monsterBodies.contains($0) ? $0 : nil } ?? monsterBodies.randomElement()!
        let eyeId = (json["eyeId"] as? String).flatMap { monsterEyes.contains($0) ? $0 : nil } ?? monsterEyes.randomElement()!
        let earId = (json["earId"] as? String).flatMap { monsterEars.contains($0) ? $0 : nil } ?? monsterEars.randomElement()!
        let mouthId = (json["mouthId"] as? String).flatMap { monsterMouths.contains($0) ? $0 : nil } ?? monsterMouths.randomElement()!
        let paletteId = (json["paletteId"] as? String).flatMap { monsterPalettes.contains($0) ? $0 : nil } ?? monsterPalettes.randomElement()!

        // LLMが直接enum値を選択 — 未知の値はデフォルトにフォールバック
        let personaStyle = (json["personaStyle"] as? String).flatMap { PersonaStyle(rawValue: $0) } ?? .gentle
        let conversationDistance = (json["distanceStyle"] as? String).flatMap { ConversationDistance(rawValue: $0) } ?? .casual
        let memoryPreference = (json["memoryStyle"] as? String).flatMap { MemoryPreference(rawValue: $0) } ?? .balanced

        let personaCustom = (json["personaCustom"] as? String) ?? ""
        let distanceCustom = (json["distanceCustom"] as? String) ?? ""
        let memoryCustom = (json["memoryCustom"] as? String) ?? ""

        return BuddySeed(
            bodyId: bodyId,
            eyeId: eyeId,
            earId: earId,
            mouthId: mouthId,
            paletteId: paletteId,
            accentIds: [personaStyle.avatarEmotionAccentId, conversationDistance.avatarInterestAccentId],
            personaStyle: personaStyle,
            conversationDistance: conversationDistance,
            memoryPreference: memoryPreference,
            personalityNotes: (json["personalityNotes"] as? String) ?? "",
            customTraits: (json["customTraits"] as? String) ?? "",
            personaStyleCustom: personaCustom,
            conversationDistanceCustom: distanceCustom,
            memoryPreferenceCustom: memoryCustom,
            roomThemeId: "room_default"
        )
    }

}
