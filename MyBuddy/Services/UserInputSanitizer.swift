import Foundation

enum UserInputSanitizer {
    enum Policy {
        case chatMessage
        case promptHistory
        case promptUserText
        case imagePromptText
        case onboardingMessage
        case buddyName
        case nickname
        case customTraits
        case journalTitle
        case journalBody
        case diaryPipelineText

        var maxLength: Int {
            switch self {
            case .buddyName, .nickname:
                return 20
            case .journalTitle:
                return 40
            case .customTraits:
                return 240
            case .onboardingMessage:
                return 600
            case .chatMessage, .imagePromptText:
                return 1_200
            case .promptHistory:
                return 1_500
            case .promptUserText:
                return 8_000
            case .diaryPipelineText:
                return 8_000
            case .journalBody:
                return 12_000
            }
        }

        var allowsMultiline: Bool {
            switch self {
            case .journalBody, .diaryPipelineText, .promptHistory, .promptUserText:
                return true
            case .chatMessage, .imagePromptText, .onboardingMessage:
                return true
            case .buddyName, .nickname, .customTraits, .journalTitle:
                return false
            }
        }

        var preservesParagraphs: Bool {
            switch self {
            case .journalBody, .diaryPipelineText:
                return true
            default:
                return false
            }
        }
    }

    static func sanitize(_ text: String, policy: Policy) -> String {
        var sanitized = text.precomposedStringWithCanonicalMapping
        sanitized = removeControlTokens(from: sanitized)
        sanitized = removeInvisibleControls(from: sanitized, allowsMultiline: policy.allowsMultiline)
        sanitized = normalizeWhitespace(in: sanitized, policy: policy)
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = String(sanitized.prefix(policy.maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized
    }

    static func removeControlTokens(from text: String) -> String {
        var sanitized = text
        let controlTokens = [
            "<|turn>", "<turn|>",
            "<|think|>", "<think>", "</think>",
            "<|channel>", "<channel|>",
            "<|im_start|>", "<|im_end|>",
            "<|endoftext|>", "<|bos|>", "<|eos|>",
            "<|end_of_turn|>", "<|start_of_turn|>",
            "<__media__>",
            "<tool_call>", "</tool_call>",
            "<tool_response>", "</tool_response>",
            "<tool>", "</tool>"
        ]
        for token in controlTokens {
            sanitized = sanitized.replacingOccurrences(of: token, with: "")
        }

        let patterns = [
            "<\\|[^>\\n<]{0,64}>",
            "<[^>\\n<]{0,64}\\|>",
            "</?(?:tool_call|tool_response|tool|bos|eos|end_of_turn|start_of_turn|im_start|im_end)\\|?>",
            "<__media__>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: ""
                )
            }
        }
        return sanitized
    }

    private static func removeInvisibleControls(from text: String, allowsMultiline: Bool) -> String {
        String(text.unicodeScalars.compactMap { scalar -> Character? in
            if scalar.value == 10 || scalar.value == 9 {
                return allowsMultiline ? Character(scalar) : " "
            }
            if scalar.value == 13 {
                return allowsMultiline ? "\n" : " "
            }
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}").contains(scalar) {
                return nil
            }
            return Character(scalar)
        })
    }

    private static func normalizeWhitespace(in text: String, policy: Policy) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")

        if policy.allowsMultiline {
            normalized = normalized
                .components(separatedBy: "\n")
                .map { line in
                    line
                        .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: "\n")
            let maxBlankLines = policy.preservesParagraphs ? "\n\n" : "\n"
            let pattern = policy.preservesParagraphs ? "\\n{3,}" : "\\n{2,}"
            normalized = normalized.replacingOccurrences(of: pattern, with: maxBlankLines, options: .regularExpression)
        } else {
            normalized = normalized
                .replacingOccurrences(of: "[\\s\\n\\t]+", with: " ", options: .regularExpression)
        }
        return normalized
    }
}
