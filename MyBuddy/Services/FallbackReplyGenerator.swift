import Foundation

/// ペルソナ専用のフォールバック返答プールを事前生成するサービス。
///
/// ランタイムで LLM 応答が壊れた（空・テンプレ漏洩・言語化拒否など）場合に使う文を、
/// オンボーディング完了時に前もって決定的に作っておく。
/// 固定文は小型モデルに言い換えさせるより、人格・距離感・方言から直接組み立てた方が
/// 一貫性と再現性が高いため、ここでは LLM を使わない。
/// 生成済みプールは `BuddyProfile.fallbackReplies` に保存される。
@MainActor
struct FallbackReplyGenerator {
    static let targetCount: Int = 3

    let llmService: any LLMServiceProtocol

    /// バディの人格に合わせて `targetCount` 件生成する。
    func generate(displayName: String, seed: BuddySeed) async -> [String] {
        _ = llmService
        let composer = PersonaLineComposer(displayName: displayName, seed: seed)
        return Array(composer.fallbackReplies().prefix(Self.targetCount))
    }
}
