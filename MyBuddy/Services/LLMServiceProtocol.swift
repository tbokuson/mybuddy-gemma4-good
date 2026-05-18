import Foundation

/// LLM 推論のサンプリング設定プロファイル。
///
/// - chat は多様性を少し盛る
/// - journal は事実忠実性のため低温・狭サンプリング
/// - extraction は決定性最優先で最低温
enum LLMSamplingProfile: Sendable {
    /// 会話応答（挨拶生成・通常応答）。多様性と人格の一貫性のバランス点
    case chat
    /// 制約が強い短文生成・言い換え。追従性と安定性を優先
    case guided
    /// 構造化抽出（オンボーディングのパラメータ抽出）。決定性重視
    case extraction
    /// 日記コンパイル。事実忠実性と一貫性を最優先
    case journal

    nonisolated var temperature: Float {
        switch self {
        case .chat: return 0.60
        case .guided: return 0.45
        case .extraction: return 0.20
        case .journal: return 0.45
        }
    }

    nonisolated var topK: Int32 {
        switch self {
        case .chat: return 30
        case .guided, .extraction, .journal: return 20
        }
    }

    nonisolated var topP: Float {
        switch self {
        case .chat: return 0.90
        case .guided: return 0.90
        case .extraction: return 0.85
        case .journal: return 0.85
        }
    }

    nonisolated var minP: Float {
        switch self {
        case .chat: return 0.05
        case .guided: return 0.05
        case .extraction: return 0.00
        case .journal: return 0.02
        }
    }

    nonisolated var repeatPenalty: Float {
        switch self {
        case .chat: return 1.10
        case .guided: return 1.05
        case .extraction: return 1.00
        case .journal: return 1.03
        }
    }

    nonisolated var repeatLastN: Int32 {
        switch self {
        case .chat: return 256
        case .guided: return 128
        case .extraction, .journal: return 64
        }
    }

    nonisolated var seed: UInt32? {
        switch self {
        case .chat:
            return nil
        case .guided:
            return 23
        case .extraction:
            return 17
        case .journal:
            return 29
        }
    }

    nonisolated var label: String {
        switch self {
        case .chat:
            return "chat"
        case .guided:
            return "guided"
        case .extraction:
            return "extraction"
        case .journal:
            return "journal"
        }
    }
}

@MainActor
protocol LLMServiceProtocol: AnyObject {
    var isLoaded: Bool { get }
    var isGenerating: Bool { get }
    var visionLoaded: Bool { get }
    var backendDescription: String { get }
    var requiresLocalModelAssets: Bool { get }

    func loadModel() async throws
    func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String
    func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error>
    func loadVision() async throws
    func unloadVision()
    func releaseBackgroundResources()
    func handleMemoryPressure()
    func generateWithImage(prompt: String, imageData: Data, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String
}

extension LLMServiceProtocol {
    /// 既定プロファイル(.chat)で呼び出すための便利オーバーロード
    func generate(prompt: String, maxTokens: Int) async throws -> String {
        try await generate(prompt: prompt, maxTokens: maxTokens, samplingProfile: .chat)
    }

    func generateStream(prompt: String, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        generateStream(prompt: prompt, maxTokens: maxTokens, samplingProfile: .chat)
    }

    func generateWithImage(prompt: String, imageData: Data, maxTokens: Int) async throws -> String {
        try await generateWithImage(prompt: prompt, imageData: imageData, maxTokens: maxTokens, samplingProfile: .chat)
    }

    func releaseBackgroundResources() {
        unloadVision()
    }

    func handleMemoryPressure() {
        unloadVision()
    }

    func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile, probeTag: String?) async throws -> String {
        if let llama = self as? LlamaCppService {
            return try await llama.generate(
                prompt: prompt,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #if DEBUG
        if let ollama = self as? OllamaService {
            return try await ollama.generate(
                prompt: prompt,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #endif
        return try await generate(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile)
    }

    func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile, probeTag: String?) -> AsyncThrowingStream<String, Error> {
        if let llama = self as? LlamaCppService {
            return llama.generateStream(
                prompt: prompt,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #if DEBUG
        if let ollama = self as? OllamaService {
            return ollama.generateStream(
                prompt: prompt,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #endif
        return generateStream(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile)
    }

    func generateWithImage(prompt: String, imageData: Data, maxTokens: Int, samplingProfile: LLMSamplingProfile, probeTag: String?) async throws -> String {
        if let llama = self as? LlamaCppService {
            return try await llama.generateWithImage(
                prompt: prompt,
                imageData: imageData,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #if DEBUG
        if let ollama = self as? OllamaService {
            return try await ollama.generateWithImage(
                prompt: prompt,
                imageData: imageData,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile,
                probeTag: probeTag
            )
        }
        #endif
        return try await generateWithImage(
            prompt: prompt,
            imageData: imageData,
            maxTokens: maxTokens,
            samplingProfile: samplingProfile
        )
    }
}

enum LLMServiceFactory {
    @MainActor
    static func makeFromEnvironment() -> any LLMServiceProtocol {
        #if DEBUG
        if AppEnvironment.usesOllamaBackend {
            return OllamaService(configuration: AppEnvironment.ollamaConfiguration)
        }
        #endif
        return LlamaCppService()
    }
}
