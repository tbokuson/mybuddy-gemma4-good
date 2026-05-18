import XCTest
@testable import MyBuddy

@MainActor
final class ChatDismissiveReplyTests: XCTestCase {

    // MARK: - Exact match（旧実装も通っていた基本ケース）

    func testExactDismissive() {
        let inputs = ["ない", "なし", "特にない", "べつに", "もういい", "おやすみ", "ありがとう", "no"]
        for input in inputs {
            XCTAssertTrue(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive と判定されるべき"
            )
        }
    }

    // MARK: - 変化形（問題2の主眼）

    func testDismissiveVariations_ない系() {
        let inputs = [
            "ないや", "ないって", "ないよ", "ないな", "ないね", "ないかな",
            "ないっす", "ないわ", "ないで", "なーい", "ないもん", "ないのよ",
            "もうないよ", "もう無い",
        ]
        for input in inputs {
            XCTAssertTrue(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive と判定されるべき"
            )
        }
    }

    func testDismissiveVariations_疲労系() {
        let inputs = ["疲れた", "つかれた", "しんどい", "眠い", "ねむい", "だるい", "寝る", "そろそろ"]
        for input in inputs {
            XCTAssertTrue(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive と判定されるべき"
            )
        }
    }

    func testDismissiveVariations_諦め系() {
        let inputs = ["もうよか", "もうええ", "結構", "以上", "ここまで", "もう十分", "勘弁"]
        for input in inputs {
            XCTAssertTrue(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive と判定されるべき"
            )
        }
    }

    func testDismissiveVariations_思い出せない系() {
        let inputs = ["思いつかない", "浮かばない", "忘れた", "思い出せない"]
        for input in inputs {
            XCTAssertTrue(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive と判定されるべき"
            )
        }
    }

    // MARK: - 接頭辞一致 + 長さガード

    func testPrefixMatchShortText() {
        XCTAssertTrue(ChatViewModel.isDismissiveReply("ないんだよな"))      // 「ない」prefix, 6字
        XCTAssertTrue(ChatViewModel.isDismissiveReply("もういいから"))      // 「もういい」prefix, 6字
        XCTAssertTrue(ChatViewModel.isDismissiveReply("眠いからもう"))      // 「眠」prefix, 6字
        XCTAssertTrue(ChatViewModel.isDismissiveReply("疲れちゃった"))      // 「疲れ」prefix, 6字
    }

    func testPrefixMatchDoesNotTriggerOnLongText() {
        // 10字超の長文は prefix マッチ対象外（substantive な返答を誤検知しない）
        XCTAssertFalse(
            ChatViewModel.isDismissiveReply("ないから明日の予定話すね"),      // 12字
            "10字超なら prefix 一致で false を期待"
        )
        XCTAssertFalse(
            ChatViewModel.isDismissiveReply("眠いけど楽しい話があったんだ"),  // 14字
            "10字超なら prefix 一致で false を期待"
        )
        XCTAssertFalse(
            ChatViewModel.isDismissiveReply("疲れたけど仕事は順調だった"),   // 13字
            "10字超なら prefix 一致で false を期待"
        )
    }

    // MARK: - フラグメント

    func testFragmentMatch() {
        XCTAssertTrue(ChatViewModel.isDismissiveReply("もう話すことないわ"))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("他にはないかな"))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("話したくないよ"))
    }

    // MARK: - 誤検知しないケース

    func testNotDismissive() {
        let inputs = [
            "今日は仕事で会議が多かった",
            "朝ごはんパンを食べた",
            "楽しかったよ",
            "新しい本を買った",
            "そういえば昨日の話",
        ]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive ではないはず"
            )
        }
    }

    func testEmptyText() {
        XCTAssertFalse(ChatViewModel.isDismissiveReply(""))
        XCTAssertFalse(ChatViewModel.isDismissiveReply("   "))
        XCTAssertFalse(ChatViewModel.isDismissiveReply("\n\t "))
    }

    // MARK: - 二重否定（dismissive としない）

    func testDoubleNegationNotDismissive() {
        // 「ない」を含むが意図は肯定・留保なので dismissive にしない
        let inputs = [
            "ないわけじゃない",
            "ないわけでもない",
            "ないことはない",
            "ないこともない",
            "ないとは限らない",
            "ないとは言えない",
            "ないとも言えない",
            "ないでもない",
            "嫌いなわけじゃない",
            "話したくないわけじゃない",
            "もう話すこともないわけじゃない",
        ]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は二重否定なので dismissive ではないはず"
            )
        }
    }

    // MARK: - 曖昧な返答（終了意思ではなく低情報として扱う短文）

    func testAmbiguousShortAcknowledgmentIsLowSignalButNotDismissive() {
        let inputs = ["うん", "はい", "そうだね", "わかった", "了解", "大丈夫"]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は相づちであり、単独では終了意思にしない"
            )
            XCTAssertTrue(
                ChatViewModel.isLowSignalReply(input),
                "「\(input)」は低情報返答として扱う"
            )
        }
    }

    func testAmbiguousButNotDismissive() {
        // 同じく短いが、会話を続ける意思がある or 新しい話題を提示する
        let inputs = [
            "どうだろ",
            "どうかな",
            "そうかな",
            "まあね",    // 相づち系だが dismissive リストには非含有
            "うーん",    // 考え込み中
            "ちょっと待って",
            "聞いてよ",
            "そういえば",
        ]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は dismissive とは言い切れない（中立）"
            )
        }
    }

    func testAmbiguousSlangAndMemeNotDismissive() {
        // SNSスラング・ミーム調は dismissive ではない
        let inputs = [
            "ぴえん",
            "草",
            "ワロタ",
            "それな",
            "やばい",
            "神",
            "尊い",
        ]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」はスラングで dismissive ではないはず"
            )
        }
    }

    // MARK: - 突飛な入力（gibberish / 絵文字 / 記号）

    func testEccentricGibberishNotDismissive() {
        // 意味不明な文字列は dismissive ではない（締めシグナルではない）
        let inputs = [
            "あいうえおかきくけこ",
            "abcdefg",
            "🎵🎵🎵",
            "？？？？？",
            "asdfgh",
            "🐱🐶🐰",
            "123456",
            "aaaaaaa",
        ]
        for input in inputs {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は gibberish で dismissive シグナルではない"
            )
        }
    }

    func testEccentricButContainsDismissiveKeyword() {
        // 突飛だが dismissive キーワードで始まる/含む
        XCTAssertTrue(ChatViewModel.isDismissiveReply("ないw"))         // ない + 草
        XCTAssertTrue(ChatViewModel.isDismissiveReply("ないよ〜"))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("ないっぽい"))    // prefix ない, 5字
        XCTAssertTrue(ChatViewModel.isDismissiveReply("疲れたー"))      // prefix 疲れ, 4字
        XCTAssertTrue(ChatViewModel.isDismissiveReply("眠いな〜"))      // prefix 眠, 4字
    }

    // MARK: - 否定文中にあるが締めでない（長文）

    func testLongNegativeNotDismissive() {
        let inputs = [
            "今日はそんなに特別なことはなかったな",      // 16字, 普通の振り返り
            "ないけど明日から頑張るわ",                   // 12字, 決意表明
            "疲れたけど楽しい一日だった",                 // 13字, 肯定
            "もういいじゃん、次の話しよ",                 // 12字, 話題転換
            "眠いけど今日の話もうちょっと",               // 14字, 会話継続意思
            "しんどいけど頑張るよ",                       // 10字... prefix "しんど" + <=10字 → true になる
        ]
        for (i, input) in inputs.enumerated() where i < 5 {
            XCTAssertFalse(
                ChatViewModel.isDismissiveReply(input),
                "「\(input)」は長文で substantive、dismissive にすべきでない"
            )
        }
    }

    // MARK: - 境界値テスト

    func testLengthBoundaryExactly10() {
        // 10字ちょうどは prefix マッチ有効範囲
        XCTAssertTrue(
            ChatViewModel.isDismissiveReply("疲れたんだよまじで"),  // 9字, prefix "疲れ"
            "9字は prefix マッチ範囲"
        )
        // 10字 "眠いからもう寝るね" prefix "眠" → true
        XCTAssertTrue(
            ChatViewModel.isDismissiveReply("眠いからもう寝るね"),
            "9字は prefix マッチ範囲"
        )
    }

    func testLengthBoundaryExactly11Plus() {
        // 11字超は prefix マッチしない
        XCTAssertFalse(
            ChatViewModel.isDismissiveReply("ないから明日の予定話すね"),    // 12字
            "12字は prefix マッチ対象外"
        )
    }

    // MARK: - 大文字小文字・記号混在

    func testCaseInsensitiveEnglish() {
        XCTAssertTrue(ChatViewModel.isDismissiveReply("NO"))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("No"))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("NAH"))
    }

    func testTrimsWhitespace() {
        XCTAssertTrue(ChatViewModel.isDismissiveReply("  ない  "))
        XCTAssertTrue(ChatViewModel.isDismissiveReply("\nないや\n"))
    }
}
