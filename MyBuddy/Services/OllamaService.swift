// OllamaService はシミュレータ・テスト専用バックエンド。
// 会話推論を外部サーバーへ委譲するコードは製品ビルドに含めないため、
// DEBUG ビルド限定でコンパイルする。
#if DEBUG

import Foundation
import Combine

struct OllamaConfiguration: Equatable {
    let baseURL: URL
    let model: String
    let keepAlive: String
}

@MainActor
final class OllamaService: ObservableObject, LLMServiceProtocol {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var visionLoaded = false

    let backendDescription: String
    let requiresLocalModelAssets = false

    private let configuration: OllamaConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let requestTimeout: TimeInterval = 90
    private let streamTurnTimeout: TimeInterval = 55

    init(
        configuration: OllamaConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.backendDescription = "Ollama \(configuration.model) @ \(configuration.baseURL.host ?? configuration.baseURL.absoluteString)"
    }

    func loadModel() async throws {
        guard !isLoaded else { return }

        _ = try await sendRequest(
            path: "/api/show",
            body: OllamaShowRequest(model: configuration.model),
            responseType: OllamaShowResponse.self
        )

        isLoaded = true
    }

    func generate(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat, probeTag: String? = nil) async throws -> String {
        try await ensureLoaded()

        isGenerating = true
        defer { isGenerating = false }

        if let probeTag {
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) backend=ollama model=\(configuration.model) \(ProbeLogger.samplingSummary(profile: samplingProfile, maxTokens: maxTokens))"
            )
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) prompt.original", text: prompt)
        }

        let response = try await sendRequest(
            path: "/api/generate",
            body: OllamaGenerateRequest(
                model: configuration.model,
                prompt: prompt,
                stream: false,
                raw: true,
                keepAlive: configuration.keepAlive,
                images: nil,
                options: OllamaGenerateOptions(maxTokens: maxTokens, profile: samplingProfile)
            ),
            responseType: OllamaGenerateResponse.self
        )

        let finalResponse = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let probeTag {
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) output.raw", text: finalResponse)
        }
        return finalResponse
    }

    func generate(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat) async throws -> String {
        try await generate(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile, probeTag: nil)
    }

    func generateStream(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat, probeTag: String? = nil) -> AsyncThrowingStream<String, Error> {
        // Ollamaストリーミングは停止するケースがあるため、
        // 非ストリーミング1発を疑似ストリームとして返しつつ、
        // ウォッチドッグで無応答時に確実に失敗終了させる。
        isGenerating = true

        return AsyncThrowingStream { continuation in
            var didFinish = false
            var watchdogTask: Task<Void, Never>?
            func finishOnce(yield text: String? = nil, error: Error? = nil) {
                guard !didFinish else { return }
                didFinish = true
                watchdogTask?.cancel()
                if let text, !text.isEmpty {
                    continuation.yield(text)
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }

            let worker = Task {
                defer {
                    Task { @MainActor in
                        self.isGenerating = false
                    }
                }
                do {
                    try Task.checkCancellation()
                    try await self.ensureLoaded()
                    try Task.checkCancellation()
                    let response = try await self.generateNonStreamingOnce(
                        prompt: prompt,
                        maxTokens: min(maxTokens, 256),
                        samplingProfile: samplingProfile,
                        probeTag: probeTag
                    )
                    try Task.checkCancellation()
                    finishOnce(yield: response)
                } catch is CancellationError {
                    finishOnce(error: CancellationError())
                } catch {
                    finishOnce(error: error)
                }
            }
            watchdogTask = Task {
                try? await Task.sleep(for: .seconds(streamTurnTimeout))
                guard !Task.isCancelled else { return }
                worker.cancel()
                finishOnce(error: OllamaError.api("応答がタイムアウトしました"))
            }
            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }

    func generateStream(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat) -> AsyncThrowingStream<String, Error> {
        generateStream(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile, probeTag: nil)
    }

    func loadVision() async throws {
        try await ensureLoaded()
        visionLoaded = true
    }

    func unloadVision() {
        visionLoaded = false
    }

    func generateWithImage(prompt: String, imageData: Data, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat, probeTag: String? = nil) async throws -> String {
        try await ensureLoaded()

        isGenerating = true
        defer { isGenerating = false }

        if let probeTag {
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) backend=ollama model=\(configuration.model) mode=image \(ProbeLogger.samplingSummary(profile: samplingProfile, maxTokens: maxTokens))"
            )
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) prompt.original", text: prompt)
        }

        let response = try await sendRequest(
            path: "/api/generate",
            body: OllamaGenerateRequest(
                model: configuration.model,
                prompt: prompt,
                stream: false,
                raw: true,
                keepAlive: configuration.keepAlive,
                images: [imageData.base64EncodedString()],
                options: OllamaGenerateOptions(maxTokens: maxTokens, profile: samplingProfile)
            ),
            responseType: OllamaGenerateResponse.self
        )

        visionLoaded = true
        let finalResponse = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let probeTag {
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) output.raw", text: finalResponse)
        }
        return finalResponse
    }

    func generateWithImage(prompt: String, imageData: Data, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat) async throws -> String {
        try await generateWithImage(
            prompt: prompt,
            imageData: imageData,
            maxTokens: maxTokens,
            samplingProfile: samplingProfile,
            probeTag: nil
        )
    }

    private func ensureLoaded() async throws {
        if !isLoaded {
            try await loadModel()
        }
    }

    private func sendRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        timeout: TimeInterval? = nil,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let request = try makeURLRequest(path: path, body: body, timeout: timeout)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        if let apiError = try? decoder.decode(OllamaAPIErrorResponse.self, from: data) {
            throw OllamaError.api(apiError.error)
        }

        return try decoder.decode(responseType, from: data)
    }

    private func makeURLRequest<RequestBody: Encodable>(
        path: String,
        body: RequestBody,
        timeout: TimeInterval?
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout ?? requestTimeout
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func generateNonStreamingOnce(
        prompt: String,
        maxTokens: Int,
        samplingProfile: LLMSamplingProfile,
        probeTag: String?
    ) async throws -> String {
        if let probeTag {
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) backend=ollama model=\(configuration.model) \(ProbeLogger.samplingSummary(profile: samplingProfile, maxTokens: maxTokens))"
            )
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) prompt.original", text: prompt)
        }

        let response = try await sendRequest(
            path: "/api/generate",
            body: OllamaGenerateRequest(
                model: configuration.model,
                prompt: prompt,
                stream: false,
                raw: true,
                keepAlive: configuration.keepAlive,
                images: nil,
                options: OllamaGenerateOptions(maxTokens: maxTokens, profile: samplingProfile)
            ),
            timeout: streamTurnTimeout,
            responseType: OllamaGenerateResponse.self
        )

        let finalResponse = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let probeTag {
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) output.raw", text: finalResponse)
        }
        return finalResponse
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaError.httpStatus(httpResponse.statusCode)
        }
    }
}

private struct OllamaShowRequest: Encodable {
    let model: String
}

private struct OllamaShowResponse: Decodable {
    let license: String?
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let raw: Bool
    let keepAlive: String
    let images: [String]?
    let options: OllamaGenerateOptions

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case raw
        case keepAlive = "keep_alive"
        case images
        case options
    }
}

private struct OllamaGenerateOptions: Encodable {
    let numPredict: Int
    let temperature: Float
    let topK: Int
    let topP: Float
    let minP: Float
    let repeatPenalty: Float
    let repeatLastN: Int

    init(maxTokens: Int, profile: LLMSamplingProfile) {
        self.numPredict = maxTokens
        self.temperature = profile.temperature
        self.topK = Int(profile.topK)
        self.topP = profile.topP
        self.minP = profile.minP
        self.repeatPenalty = profile.repeatPenalty
        self.repeatLastN = Int(profile.repeatLastN)
    }

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
        case repeatPenalty = "repeat_penalty"
        case repeatLastN = "repeat_last_n"
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
    let done: Bool
    let error: String?
}

private struct OllamaAPIErrorResponse: Decodable {
    let error: String
}

enum OllamaError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ollamaから不正なレスポンスを受け取りました"
        case .httpStatus(let status):
            return "Ollama HTTPエラー: \(status)"
        case .api(let message):
            return "Ollamaエラー: \(message)"
        }
    }
}

#endif
