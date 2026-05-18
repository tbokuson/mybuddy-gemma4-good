import XCTest
@testable import MyBuddy

/// customTraits の Y/N 判定（ショートカット + LLM 分類器 + パーサー）の網羅テスト。
/// LLM 自体のモックは難しいため、キーワードショートカットと parseCustomTraitsClassification の挙動を徹底検証する。
final class CustomTraitsClassificationTests: XCTestCase {

    // MARK: - ショートカット: trait-indicator キーワードで Y 即確定

    func testShortcutHitsForDialect() {
        let inputs = [
            "関西弁で",
            "大阪弁っぽく",
            "博多弁で話して",
            "九州弁",
            "東北訛り",
            "沖縄っぽい口調",
            "名古屋弁",
            "広島弁で",
            "京都のおっとりした口調",
        ]
        for input in inputs {
            XCTAssertTrue(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は方言指定なのでショートカット Y"
            )
        }
    }

    func testShortcutHitsForSpeechStyle() {
        let inputs = [
            "敬語で丁寧に",
            "タメ口でいいよ",
            "砕けた感じで",
            "偉そうな口調で",
            "命令口調で",
            "子供っぽく話して",
            "語尾にゃを付けて",
            "語尾にわんを付けて",
            "ござる口調で",
            "口調はそのままでOK",
            "話し方はソフトに",
        ]
        for input in inputs {
            XCTAssertTrue(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は話し方指定なのでショートカット Y"
            )
        }
    }

    func testShortcutHitsForCharacterTypes() {
        let inputs = [
            "ギャルっぽく",
            "ヤンキーっぽい感じで",
            "姉御肌のキャラで",
            "お嬢様口調で",
            "オタクっぽい感じ",
            "先生風に",
            "王子様キャラで",
            "執事みたいな感じで",
        ]
        for input in inputs {
            XCTAssertTrue(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」はキャラ指定なのでショートカット Y"
            )
        }
    }

    func testShortcutHitsForEndings() {
        // 語尾の具体的指定（narrow な indicator のみ期待する）
        let inputs = [
            "語尾ににゃ",
            "語尾にわん",
            "語尾はござる",
            "っぽく話して",
            "風に話して",
            "なのだ口調で",
            "っすって語尾で",
            "わよ、って口調",
            "語尾がわね",
        ]
        for input in inputs {
            XCTAssertTrue(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は語尾指定なのでショートカット Y"
            )
        }
    }

    func testShortcutHitsForEccentricButValid() {
        // 突飛だが trait-indicator を含む
        let inputs = [
            "語尾に毎回『ぴょん』つけて",  // 語尾
            "宇宙人口調で",                // 口調
            "脳内で関西弁で話して",        // 関西 / 弁
            "語尾に絵文字つけて🎵",        // 語尾 / 絵文字
            "ぶりっ子キャラで",            // ぶりっ / キャラ
            "毎回敬語",                    // 敬語
            "あだ名で呼んで",              // あだ名 / 呼んで→呼び方ではない…
        ]
        for input in inputs {
            XCTAssertTrue(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は突飛だが trait-indicator ありでショートカット Y"
            )
        }
    }

    /// 「感じ」「みたい」「ような」は narrow ではないため shortcut 非該当。
    /// これらは LLM 分類器に判断を委ねる（Y-bias で通すことが多い）。
    func testShortcutMissesForBroadSuffixes() {
        let inputs = [
            "元気な感じで",       // "感じ" 除外後は indicator なし
            "かわいい感じで",     // 同上
            "お母さんみたいな",   // 同上
            "天使のような雰囲気", // 同上
            "なんか変な感じ",     // 曖昧
            "普通じゃない感じ",   // 曖昧
        ]
        for input in inputs {
            XCTAssertFalse(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は広すぎるので shortcut miss (LLM判定へ)"
            )
        }
    }

    // MARK: - ショートカット: trait-indicator なし → LLM 分類器へ回る

    func testShortcutMissesForGibberish() {
        let inputs = [
            "あなかはやまま",
            "🎵🎵🎵",
            "asdfgh",
            "aaaaaa",
            "qwerty",
            "abcdef",
            "？？？？",
            "🐱🐶🐰",
        ]
        for input in inputs {
            XCTAssertFalse(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は gibberish でショートカット対象外 (LLM判定行き)"
            )
        }
    }

    func testShortcutMissesForAmbiguousShortPhrases() {
        // 曖昧で indicator 含まない入力は LLM 判定に任せる（ショートカットでは Y にならない）
        let inputs = [
            "もうちょっと元気に",
            "もう少し柔らかく",
            "元気な子",
        ]
        for input in inputs {
            XCTAssertFalse(
                OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators),
                "「\(input)」は indicator 含まず LLM 判定へ"
            )
        }
    }

    // MARK: - parseCustomTraitsClassification: 曖昧な LLM 出力

    func testParseYWithSurroundingText() {
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Y"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Y\n"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification(" Y "))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("y"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Yes"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("YES"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("yes, valid"))
    }

    func testParseNWithSurroundingText() {
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("N"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("n"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("No"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("NO"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("nope"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("N (意味不明)"))
    }

    func testParseWithQuotesAndBrackets() {
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("「Y」"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("「N」"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("'Y'"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("(N)"))
    }

    func testParseJapaneseYesNo() {
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("はい"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("はい、通じます"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("可"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("イエス"))

        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("いいえ"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("いいえ、わかりません"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("否"))
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("ノー"))
    }

    func testParseAmbiguousDefaultsToYes() {
        // 曖昧・解釈不能な出力は Y に倒す（ユーザー体験: 通す方が自然）
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification(""))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("   "))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("?"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("？"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("わからない"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("123"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("理解できました"))
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("その要望は"))
    }

    // MARK: - 層3 保険（isUnknownResponse）でさらに落とす突飛パターン

    func testLayer3CatchesLLMConfusion() {
        // LLM が Y と答えたが応答が「わからない」系だった場合、層3で落とす
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("わからなかった"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("うーん、それはピンとこない"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("ごめん、ちょっとわからなかった"))
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("ピンとこないけど"))
    }

    func testLayer3DoesNotOverReachOnPositiveWithNegativeMidText() {
        // 応答の中盤以降に「わからない」があっても、先頭20字なら理解済み
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("にゃ語尾可愛いね！でもたまにわからなくなるかも"))
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("関西弁ね、任せて！ちょっと慣れないとわからない部分あるかも"))
    }

    // MARK: - 統合シナリオ（3層判定の組み合わせを idea 的に検証）

    /// 「ショートカット Y → 既定 Y 判定」の流れ想定
    func testIntegrationPositiveShortcut() {
        // shortcut hit & not unknown → customConfirmed
        let input = "語尾ににゃ"
        XCTAssertTrue(OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators))
        // 仮に LLM が「にゃ、いいね！」と返す
        XCTAssertFalse(OnboardingPromptBuilder.isUnknownResponse("にゃ、いいね！"))
    }

    /// 「ショートカット miss → LLM=N → N 判定」の流れ想定
    func testIntegrationNegativeClassifier() {
        let input = "あなかはやまま"
        XCTAssertFalse(OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators))
        // LLM 分類器が "N" を返す
        XCTAssertFalse(OnboardingPromptBuilder.parseCustomTraitsClassification("N"))
    }

    /// 「ショートカット miss → LLM=Y → 応答が『わからない』→ 層3で落選」
    func testIntegrationLayer3Rescue() {
        let input = "すごい感じ"
        // shortcut miss（indicator なし）
        XCTAssertFalse(OnboardingKeywords.containsAny(input, keywords: OnboardingKeywords.traitIndicators))
        // LLM 分類器が Y と誤判定したとする
        XCTAssertTrue(OnboardingPromptBuilder.parseCustomTraitsClassification("Y"))
        // でも応答生成 LLM が「わからなかった」と返したら層3で落選
        XCTAssertTrue(OnboardingPromptBuilder.isUnknownResponse("わからなかった、例を教えて"))
    }
}
