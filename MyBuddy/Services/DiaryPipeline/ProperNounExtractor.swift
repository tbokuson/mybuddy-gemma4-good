import Foundation

/// 会話テキストから固有名詞候補を正規表現ベースで抽出するユーティリティ。
///
/// 2 文字以上の「連続した」漢字・カタカナ・英数字塊を固有名詞候補とみなす。
/// 異なるスクリプトをまたぐ塊 (例: "ナイショ話" = カタカナ+漢字) は分割して扱うため、
/// 3 つのスクリプト別パターンを交互に適用する。
///
/// VerifyStage の品質ガード（固有名詞カバレッジ判定）で使用する。
/// LLM出力に固有名詞リストを含めると、本文と同一のLLM呼出から生成されるため
/// カバレッジが常に100%になり品質ガードがバイパスされる。
/// そのため固有名詞はLLMとは独立に、正規表現ベースで会話ログから抽出する。
enum ProperNounExtractor {
    /// テキストから固有名詞候補を抽出する（重複排除済み）。
    static func extract(from text: String) -> [String] {
        let pattern = "[\\p{Han}]{2,}|[\\p{Katakana}]{2,}|[A-Za-z0-9]{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let token = String(text[r])
            if seen.insert(token).inserted {
                result.append(token)
            }
        }
        return result
    }

    /// 複数テキストから固有名詞候補をまとめて抽出する（重複排除済み）。
    static func extract(from texts: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for text in texts {
            for noun in extract(from: text) {
                if seen.insert(noun).inserted {
                    result.append(noun)
                }
            }
        }
        return result
    }
}
