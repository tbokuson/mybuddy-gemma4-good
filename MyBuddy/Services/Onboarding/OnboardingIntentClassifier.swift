import Foundation

/// オンボーディング会話の意図分類結果
enum OnboardingIntent: Equatable {
    /// enum にマッチ（例: persona=cool）
    case enumMatched(String)
    /// 「おまかせ」系の無回答
    case nullish
    /// どの enum にもマッチしない・意味不明
    case unknown
}

/// オンボーディング会話の意図分類プロトコル
///
/// 将来より高性能な LLM で分類できるようになったら、
/// `LLMIntentClassifier` 等の実装に差し替え可能にするための抽象化。
protocol OnboardingIntentClassifier {
    func classify(_ text: String, section: OnboardingViewModel.OnboardingSection) -> OnboardingIntent
}

/// キーワード辞書ベースの意図分類器（現在の実装）
struct KeywordIntentClassifier: OnboardingIntentClassifier {

    func classify(_ text: String, section: OnboardingViewModel.OnboardingSection) -> OnboardingIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // nullish 判定は最優先（「おまかせ」「なし」等）
        if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.nullish) {
            return .nullish
        }

        switch section {
        case .persona:
            // cool を最優先（「ツンデレ」等は他の軸とも重複する）
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Persona.cool) {
                return .enumMatched(PersonaStyle.cool.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Persona.bright) {
                return .enumMatched(PersonaStyle.bright.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Persona.mellow) {
                return .enumMatched(PersonaStyle.mellow.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Persona.gentle) {
                return .enumMatched(PersonaStyle.gentle.rawValue)
            }
            return .unknown

        case .distance:
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Distance.frank) {
                return .enumMatched(ConversationDistance.frank.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Distance.supportive) {
                return .enumMatched(ConversationDistance.supportive.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Distance.playful) {
                return .enumMatched(ConversationDistance.playful.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.Distance.casual) {
                return .enumMatched(ConversationDistance.casual.rawValue)
            }
            return .unknown

        case .diaryStyle:
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.DiaryStyle.feelingAware) {
                return .enumMatched(MemoryPreference.feelingAware.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.DiaryStyle.compact) {
                return .enumMatched(MemoryPreference.compact.rawValue)
            }
            if OnboardingKeywords.containsAny(trimmed, keywords: OnboardingKeywords.DiaryStyle.balanced) {
                return .enumMatched(MemoryPreference.balanced.rawValue)
            }
            return .unknown

        case .customTraits, .done, .nickname:
            return .unknown
        }
    }
}
