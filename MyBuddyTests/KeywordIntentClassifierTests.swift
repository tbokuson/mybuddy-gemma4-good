import XCTest
@testable import MyBuddy

final class KeywordIntentClassifierTests: XCTestCase {
    let classifier = KeywordIntentClassifier()

    // MARK: - Persona

    func testPersonaGentleKeywords() {
        let inputs = ["やさしい感じ", "優しい子", "穏やかな", "ふんわりした", "癒し系", "ほんわか", "あったかい感じ"]
        for input in inputs {
            let result = classifier.classify(input, section: .persona)
            XCTAssertEqual(result, .enumMatched("gentle"), "「\(input)」は gentle にマッチするべき")
        }
    }

    func testPersonaCoolKeywords() {
        let inputs = ["クール", "cool", "ドS", "ツンデレ", "かっこいい", "クールビューティー", "無愛想", "硬派", "ドライ", "辛口"]
        for input in inputs {
            let result = classifier.classify(input, section: .persona)
            XCTAssertEqual(result, .enumMatched("cool"), "「\(input)」は cool にマッチするべき")
        }
    }

    func testPersonaBrightKeywords() {
        let inputs = ["元気", "明るい", "テンション高め", "活発", "陽気", "ハイテンション", "陽キャ", "パワフル"]
        for input in inputs {
            let result = classifier.classify(input, section: .persona)
            XCTAssertEqual(result, .enumMatched("bright"), "「\(input)」は bright にマッチするべき")
        }
    }

    func testPersonaMellowKeywords() {
        let inputs = ["のんびり", "まったり", "ゆるい", "マイペース", "ゆるふわ", "のほほん", "スローライフ"]
        for input in inputs {
            let result = classifier.classify(input, section: .persona)
            XCTAssertEqual(result, .enumMatched("mellow"), "「\(input)」は mellow にマッチするべき")
        }
    }

    func testPersonaUnknown() {
        let inputs = ["🎵🎵🎵", "aaa", "qwerty"]
        for input in inputs {
            let result = classifier.classify(input, section: .persona)
            XCTAssertEqual(result, .unknown, "「\(input)」は unknown になるべき")
        }
    }

    // MARK: - Distance

    func testDistanceSupportiveKeywords() {
        let inputs = ["寄り添って", "そっと見守", "支えて", "聞き役でいて", "共感して"]
        for input in inputs {
            let result = classifier.classify(input, section: .distance)
            XCTAssertEqual(result, .enumMatched("supportive"), "「\(input)」は supportive にマッチするべき")
        }
    }

    func testDistanceCasualKeywords() {
        let inputs = ["友達みたいに", "友達みたいに接して", "気軽に", "フランクに", "タメ口で", "ラフな感じ"]
        for input in inputs {
            let result = classifier.classify(input, section: .distance)
            XCTAssertEqual(result, .enumMatched("casual"), "「\(input)」は casual にマッチするべき")
        }
    }

    func testDistanceFrankKeywords() {
        let inputs = ["率直に", "ストレートに", "はっきり", "ズバズバ", "素直に", "正直に", "ダイレクト"]
        for input in inputs {
            let result = classifier.classify(input, section: .distance)
            XCTAssertEqual(result, .enumMatched("frank"), "「\(input)」は frank にマッチするべき")
        }
    }

    func testDistancePlayfulKeywords() {
        let inputs = ["からかってほしい", "いたずらっぽく", "冗談混じりで", "ユーモアたっぷり", "おちゃめに"]
        for input in inputs {
            let result = classifier.classify(input, section: .distance)
            XCTAssertEqual(result, .enumMatched("playful"), "「\(input)」は playful にマッチするべき")
        }
    }

    // MARK: - DiaryStyle

    func testDiaryStyleCompactKeywords() {
        let inputs = ["シンプル", "簡潔に", "あっさり", "短く", "コンパクト", "ざっくり"]
        for input in inputs {
            let result = classifier.classify(input, section: .diaryStyle)
            XCTAssertEqual(result, .enumMatched("compact"), "「\(input)」は compact にマッチするべき")
        }
    }

    func testDiaryStyleBalancedKeywords() {
        let inputs = ["できごと中心", "事実を", "普通で", "淡々と", "日常の記録"]
        for input in inputs {
            let result = classifier.classify(input, section: .diaryStyle)
            XCTAssertEqual(result, .enumMatched("balanced"), "「\(input)」は balanced にマッチするべき")
        }
    }

    func testDiaryStyleFeelingAwareKeywords() {
        let inputs = ["気持ちも", "感情を", "心の動き", "情緒", "ムードまで", "しっかり残したい"]
        for input in inputs {
            let result = classifier.classify(input, section: .diaryStyle)
            XCTAssertEqual(result, .enumMatched("feelingAware"), "「\(input)」は feelingAware にマッチするべき")
        }
    }

    // MARK: - Nullish

    func testNullishKeywords() {
        let inputs = ["おまかせ", "なんでもいい", "特にない", "決められない", "適当に", "任せる"]
        for input in inputs {
            for section in [OnboardingViewModel.OnboardingSection.persona, .distance, .diaryStyle, .customTraits] {
                let result = classifier.classify(input, section: section)
                XCTAssertEqual(result, .nullish, "「\(input)」(\(section)) は nullish になるべき")
            }
        }
    }

    // MARK: - 優先度

    func testCoolTakesPriorityOverPlayful() {
        // 「ツンデレ」は persona=cool / distance=playful 両方に含まれる
        // persona で聞かれたら cool が優先されるべき
        let result1 = classifier.classify("ツンデレな感じ", section: .persona)
        XCTAssertEqual(result1, .enumMatched("cool"))

        // distance で聞かれたら playful にマッチするはず
        let result2 = classifier.classify("ツンデレっぽく", section: .distance)
        XCTAssertEqual(result2, .enumMatched("playful"))
    }
}
