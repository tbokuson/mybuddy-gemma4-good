import Foundation

enum LLMOutputSanitizer {
    /// ユーザー入力から Gemma 4 の制御トークンを除去し、プロンプトインジェクションを防ぐ
    static func sanitizeInput(_ text: String) -> String {
        UserInputSanitizer.sanitize(text, policy: .promptUserText)
    }

    static func cleanup(_ response: String, resolvedLanguage: ResolvedAppLanguage = AppLanguageMode.currentResolved) -> String {
        var cleaned = response

        // thinking ブロック `<think>...</think>` を丸ごと除去（DOTALL）
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: []) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        // 開き/閉じ単独で漏れた場合も拾う
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "")

        if let regex = try? NSRegularExpression(pattern: "<\\|channel>thought[\\s\\S]*?<channel\\|>", options: []) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        cleaned = cleaned.replacingOccurrences(of: "<turn|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|channel>thought", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<channel|>", with: "")
        // 制御トークン除去
        cleaned = cleaned.replacingOccurrences(of: "<|im_start|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|im_end|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|endoftext|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")

        if let regex = try? NSRegularExpression(
            pattern: "<unused\\d+>|<pad>|<unk>|<mask>|<eos>|\\[multimodal\\]",
            options: []
        ) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Gemma 4 特殊トークン除去
        // <|...> 形式と <token|> 形式の両方をキャッチ
        if let regex = try? NSRegularExpression(
            pattern: "<\\|[^>]*>|</?(?:tool_call|tool_response|tool|bos|eos|end_of_turn|start_of_turn|im_start|im_end)\\|?>",
            options: []
        ) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        if let regex = try? NSRegularExpression(
            pattern: "^\\s*\\[\\d{1,2}(:\\d{0,2})?\\]?\\s*(?=\\S|$)",
            options: .anchorsMatchLines
        ) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        let trimmedForCheck = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let partialTimestamp = try? NSRegularExpression(pattern: "^\\[\\d{0,2}:?\\d{0,2}\\]?$", options: []),
           partialTimestamp.firstMatch(
               in: trimmedForCheck,
               range: NSRange(trimmedForCheck.startIndex..., in: trimmedForCheck)
           ) != nil {
            cleaned = ""
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "---" && trimmed != "___" && trimmed != "***"
            }
            .joined(separator: "\n")

        // 多言語学習の副作用で「went」「maybe」「huh」等の単発英単語が
        // 日本語文中に紛れ込む事故への対策。英語モードでは正しい本文なので保持する。
        if resolvedLanguage == .japanese,
           let stray = try? NSRegularExpression(pattern: "\\b[A-Za-z]{2,}\\b", options: []) {
            cleaned = stray.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
            // 除去後に残る「  」「 。」「 、」を整える
            cleaned = cleaned.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: " ([。、！？])", with: "$1", options: .regularExpression)
        }

        cleaned = stripOuterQuotes(in: cleaned)
        cleaned = stripDanglingQuotes(in: cleaned)

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsOnlyPunctuationOrSymbols(cleaned) {
            return ""
        }
        let sentencePattern = try! NSRegularExpression(pattern: "[^。！？]+[。！？]", options: [])
        let matches = sentencePattern.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        if matches.count > 10 {
            let endRange = matches[9].range
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: endRange.location + endRange.length)
            cleaned = String(cleaned[..<endIndex])
        }

        return cleaned
    }

    private static func containsOnlyPunctuationOrSymbols(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.unicodeScalars.contains { scalar in
            scalar.properties.isAlphabetic
                || scalar.properties.numericType != nil
                || (0x3040...0x30FF).contains(Int(scalar.value))
                || (0x3400...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func stripOuterQuotes(in text: String) -> String {
        let pairs: [(Character, Character)] = [("「", "」"), ("『", "』"), ("\"", "\"")]
        var current = text

        for (open, close) in pairs {
            if current.first == open && current.last == close && current.count >= 2 {
                current = String(current.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return current
    }

    private static func stripDanglingQuotes(in text: String) -> String {
        var current = text
        let danglingPairs: [(open: Character, close: Character)] = [("「", "」"), ("『", "』")]

        for pair in danglingPairs {
            if current.last == pair.close && !current.contains(pair.open) {
                current.removeLast()
                current = current.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if current.first == pair.open && !current.contains(pair.close) {
                current.removeFirst()
                current = current.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while current.last == pair.close && current.filter({ $0 == pair.close }).count > current.filter({ $0 == pair.open }).count {
                current.removeLast()
                current = current.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if current.last == "\"" && !current.dropLast().contains("\"") {
            current.removeLast()
            current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if current.first == "\"" && !current.dropFirst().contains("\"") {
            current.removeFirst()
            current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return current
    }
}
