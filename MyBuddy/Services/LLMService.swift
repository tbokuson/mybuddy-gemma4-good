import Foundation
import UIKit
import Combine
import llama

private actor InferenceGate {
    func run<T>(_ operation: () throws -> T) rethrows -> T {
        try operation()
    }
}

// MARK: - Gemma 4 Prompt Formatting

/// Gemma 4 のプロンプトテンプレート
/// 参考: https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4
struct Gemma4PromptBuilder {
    /// シングルターンのプロンプトを構築（thinkingなし）
    static func buildSingleTurn(
        system: String,
        user: String,
        userPolicy: UserInputSanitizer.Policy = .promptUserText
    ) -> String {
        let safeUser = UserInputSanitizer.sanitize(user, policy: userPolicy)
        var prompt = "<|turn>system\n\(system)<turn|>\n"
        prompt += "<|turn>user\n\(safeUser)<turn|>\n"
        prompt += "<|turn>model\n"
        return prompt
    }

    /// マルチターンのプロンプトを構築（thinkingなし）
    /// - messages: (role: "user"|"model", content: String) のタプル配列
    /// - newUserMessage: 最新のユーザーメッセージ
    static func buildMultiTurn(
        system: String,
        history: [(role: String, content: String)],
        newUserMessage: String? = nil,
        historyPolicy: UserInputSanitizer.Policy = .promptHistory,
        newUserPolicy: UserInputSanitizer.Policy = .promptUserText
    ) -> String {
        var prompt = "<|turn>system\n\(system)<turn|>\n"

        for msg in history {
            let role = msg.role == "model" ? "model" : "user"
            let safeContent = UserInputSanitizer.sanitize(msg.content, policy: historyPolicy)
            prompt += "<|turn>\(role)\n\(safeContent)<turn|>\n"
        }

        if let newMsg = newUserMessage {
            let safeNewMessage = UserInputSanitizer.sanitize(newMsg, policy: newUserPolicy)
            prompt += "<|turn>user\n\(safeNewMessage)<turn|>\n"
        }

        prompt += "<|turn>model\n"
        return prompt
    }

    /// シングルターンのプロンプトを構築（thinking有効）
    /// 日記生成など、品質を優先し応答時間の許容度が高い場面で使用
    static func buildSingleTurnWithThinking(
        system: String,
        user: String,
        userPolicy: UserInputSanitizer.Policy = .diaryPipelineText
    ) -> String {
        let safeUser = UserInputSanitizer.sanitize(user, policy: userPolicy)
        var prompt = "<|turn>system\n<|think|>\n\(system)<turn|>\n"
        prompt += "<|turn>user\n\(safeUser)<turn|>\n"
        prompt += "<|turn>model\n"
        return prompt
    }

    /// 画像付きマルチターンプロンプトを構築
    /// <__media__> マーカーを最新のuserメッセージの先頭に挿入
    static func buildMultiTurnWithImage(
        system: String,
        history: [(role: String, content: String)],
        newUserMessage: String
    ) -> String {
        var prompt = "<|turn>system\n\(system)<turn|>\n"

        for msg in history {
            let role = msg.role == "model" ? "model" : "user"
            let safeContent = UserInputSanitizer.sanitize(msg.content, policy: .promptHistory)
            prompt += "<|turn>\(role)\n\(safeContent)<turn|>\n"
        }

        // 画像メッセージ: <__media__>マーカー + テキスト
        let safeUserMessage = UserInputSanitizer.sanitize(newUserMessage, policy: .imagePromptText)
        prompt += "<|turn>user\n<__media__>\n\(safeUserMessage)<turn|>\n"
        prompt += "<|turn>model\n"
        return prompt
    }
}

// MARK: - llama.cpp Implementation (Gemma 4 E2B)

extension LlamaCppService: LLMServiceProtocol {
    var backendDescription: String {
        "On-device Gemma 4"
    }

    var requiresLocalModelAssets: Bool {
        true
    }
}

private struct LoadedLlamaPointers: @unchecked Sendable {
    nonisolated(unsafe) let model: OpaquePointer
    nonisolated(unsafe) let context: OpaquePointer
}

private struct SendableRawPointer: @unchecked Sendable {
    nonisolated(unsafe) let value: UnsafeMutableRawPointer
}

@MainActor
final class LlamaCppService: ObservableObject {
    @Published var isLoaded = false
    @Published var isGenerating = false
    @Published var visionLoaded = false

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var visionCtxPtr: UnsafeMutableRawPointer?  // VisionContext*

    /// Gemma 4 E2B の GGUF ファイル名
    private static let modelFileName = "gemma-4-E2B-it-Q4_K_M.gguf"

    /// Documents 内探索用プレフィックス
    private static let documentFilePrefixes = ["gemma-4", "gemma4"]

    /// CPU only を強制する（環境変数による強制にも使う）
    private let forceCpu: Bool
    private let assetStore = ModelAssetStore()

    private var memoryWarningObserver: Any?

    /// KVキャッシュ再利用: 前回のプロンプトトークン列を保持
    /// 共通プレフィックスを検出し、差分のみをdecodeすることでprefillを高速化
    /// nonisolated(unsafe): 推論は常にDetached Taskで逐次実行されるため競合しない
    nonisolated(unsafe) private static var cachedTokens: [llama_token] = []
    /// 同一コンテキストへの同時decodeを防ぐための直列化ゲート
    private static let inferenceGate = InferenceGate()

    private struct PromptTrimResult {
        let tokens: [llama_token]
        let beforeCount: Int
        let afterCount: Int
        let trimmed: Bool
        let headKept: Int
        let tailKept: Int
        let budget: Int
    }

    init(forceCpu: Bool = false) {
        self.forceCpu = forceCpu
        #if DEBUG
        print("[LLM] init: model=\(Self.modelFileName), forceCpu=\(forceCpu)")
        #endif

        // メモリ警告: Vision を解放
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleMemoryPressure()
            }
        }
    }

    func loadModel() async throws {
        if isLoaded { return }

        try ensureRequiredAssetsAvailable()

        guard let modelPath = findModelPath() else {
            throw missingAssetsError(fallbackAssetNames: [Self.modelFileName])
        }

        #if DEBUG
        print("[LLM] モデルをロード開始")
        #endif
        let forceCpu = self.forceCpu

        // バックグラウンドでモデルをロード
        let loadedPointers = try await Task.detached(priority: .userInitiated) {
            // llama.cpp バックエンドを初期化
            llama_backend_init()

            // デバイスメモリとモデルサイズからGPU設定を決定
            let physicalMemGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
            let modelSizeGB = Double(fileSize) / (1024 * 1024 * 1024)

            // iOSアプリが使えるメモリはphysicalMemoryの約50-60%
            // GPU全レイヤー積載にはモデルサイズ分のMetal確保が必要
            // 中途半端なGPUオフロードは転送バッファで逆にメモリを圧迫するため、
            // 全GPU or CPU onlyの二択にする
            let gpuLayers: Int32
            // `forceCpu=true` または環境変数 `LLM_FORCE_CPU=1` で CPU only を強制。
            let envForceCpu = ProcessInfo.processInfo.environment["LLM_FORCE_CPU"] == "1"
            if forceCpu || envForceCpu {
                gpuLayers = 0
                #if DEBUG
                print("[LLM] CPU only を強制 (forceCpu=\(forceCpu), env=\(envForceCpu))")
                #endif
            } else if physicalMemGB >= 14.0 && modelSizeGB < physicalMemGB * 0.3 {
                gpuLayers = 99  // RAM 16GB 端末（OS 報告 ~15GB）以上: 全レイヤー GPU
            } else {
                gpuLayers = 0   // RAM 16GB 未満: CPU only（8GB 端末はメモリ不足リスクあり）
            }

            #if DEBUG
            print("[LLM] デバイス: RAM=\(String(format: "%.1f", physicalMemGB))GB, モデル=\(String(format: "%.1f", modelSizeGB))GB (\(fileSize / 1_000_000)MB), gpu_layers=\(gpuLayers)")
            #endif

            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = gpuLayers

            #if DEBUG
            print("[LLM] モデル読み込み開始: \(modelPath)")
            #endif
            guard let model = llama_model_load_from_file(modelPath, modelParams) else {
                throw LLMError.failedToLoadModel
            }
            #if DEBUG
            print("[LLM] モデル読み込み完了")
            #endif

            // Apple Silicon Performance Cores を活用（E-coreは推論に向かないため P-core数に近い値を使う）
            // M5 Pro: 12P+4E=16 → nThreads=6 が実測で最速帯
            let nThreads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))

            // コンテキストサイズ候補（大→小の順に試行）
            // KVキャッシュF16でもn_ctx=2048で~150MBなのでメモリは問題なし
            // n_ctx=n_batchとなり、プロンプトがn_batchを超えるとクラッシュするため
            // 余裕を持ったサイズから試行する
            let ctxCandidates: [UInt32] = [4096, 3072, 2048, 1024, 512]

            // 段階的にフォールバック
            var createdContext: OpaquePointer? = nil
            for nCtx in ctxCandidates {
                var ctxParams = llama_context_default_params()
                ctxParams.n_ctx = nCtx
                // n_batch / n_ubatch は 512 固定。
                // - 512 超にすると compute buffer が肥大化して実機がフリーズ
                // - 一方 llama_decode に 512 超のバッチを渡すと内部 ubatch 分割で
                //   `GGML_ASSERT(n_outputs_prev + n_outputs <= n_outputs_all)` 発火
                // → 解決策はバッチサイズを 512 に揃え、prefill 側でチャンク分割すること
                ctxParams.n_batch = 512
                ctxParams.n_ubatch = 512
                ctxParams.n_threads = nThreads
                ctxParams.n_threads_batch = nThreads
                // KVキャッシュ: F16(デフォルト)を使用
                // Note: V cache量子化にはFlash Attentionが必要だが、
                // Gemma 4のdk512ではMetalのthreadgroupメモリ上限を超えるため使用不可
                ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED

                #if DEBUG
                print("[LLM] コンテキスト作成試行: n_ctx=\(nCtx)")
                #endif
                if let ctx = llama_init_from_model(model, ctxParams) {
                    #if DEBUG
                    print("[LLM] コンテキスト作成成功: n_ctx=\(nCtx)")
                    #endif
                    createdContext = ctx
                    break
                }
                #if DEBUG
                print("[LLM] コンテキスト作成失敗: n_ctx=\(nCtx)")
                #endif
            }

            // GPUありで全て失敗した場合、CPU onlyで再試行
            if createdContext == nil && gpuLayers > 0 {
                #if DEBUG
                print("[LLM] GPU有効で全て失敗。CPU onlyで再ロード")
                #endif
                llama_model_free(model)

                var cpuParams = llama_model_default_params()
                cpuParams.n_gpu_layers = 0
                guard let cpuModel = llama_model_load_from_file(modelPath, cpuParams) else {
                    throw LLMError.modelTooLargeForDevice(
                        modelSizeMB: Int(fileSize / 1_000_000),
                        deviceMemoryGB: physicalMemGB
                    )
                }

                var ctxParams = llama_context_default_params()
                ctxParams.n_ctx = 512
                ctxParams.n_batch = 512
                ctxParams.n_ubatch = 512
                ctxParams.n_threads = nThreads
                ctxParams.n_threads_batch = nThreads
                // KVキャッシュ: F16(デフォルト)を使用
                // Gemma 4 は dk=512 が Metal threadgroup 上限を超え Flash Attention が無効。
                // llama.cpp b8660+ で V cache 量子化には Flash Attention が必須のため、
                // CPU-only フォールバック経路でも Q4_0 KV は使用できず F16 を維持する。
                ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED

                if let ctx = llama_init_from_model(cpuModel, ctxParams) {
                    #if DEBUG
                    print("[LLM] CPU only + n_ctx=512 で成功")
                    #endif
                    return LoadedLlamaPointers(model: cpuModel, context: ctx)
                }

                llama_model_free(cpuModel)
                throw LLMError.modelTooLargeForDevice(
                    modelSizeMB: Int(fileSize / 1_000_000),
                    deviceMemoryGB: physicalMemGB
                )
            }

            guard let context = createdContext else {
                llama_model_free(model)
                throw LLMError.modelTooLargeForDevice(
                    modelSizeMB: Int(fileSize / 1_000_000),
                    deviceMemoryGB: physicalMemGB
                )
            }

            return LoadedLlamaPointers(model: model, context: context)
        }.value

        self.model = loadedPointers.model
        self.context = loadedPointers.context
        self.isLoaded = true
        #if DEBUG
        print("[LLM] モデルのロード完了")
        #endif
    }

    /// モデルを解放する。
    func unloadModel() {
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let mdl = model {
            llama_model_free(mdl)
            model = nil
        }
        LlamaCppService.cachedTokens.removeAll(keepingCapacity: false)
        isLoaded = false
        #if DEBUG
        print("[LLM] エンジンを unload しました")
        #endif
    }

    func generate(
        prompt: String,
        maxTokens: Int = 256,
        samplingProfile: LLMSamplingProfile = .chat,
        probeTag: String? = nil
    ) async throws -> String {
        guard let model = model, let context = context else {
            throw LLMError.modelNotLoaded
        }
        let pointers = LoadedLlamaPointers(model: model, context: context)

        try Task.checkCancellation()

        isGenerating = true
        defer { isGenerating = false }

        let inferenceTask = Task.detached(priority: .userInitiated) {
            try await Self.inferenceGate.run {
                try Self.runInference(
                    model: pointers.model,
                    context: pointers.context,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    samplingProfile: samplingProfile,
                    probeTag: probeTag
                )
            }
        }

        // 親 Task のキャンセルを detached Task に伝播する
        return try await withTaskCancellationHandler {
            try await inferenceTask.value
        } onCancel: {
            inferenceTask.cancel()
        }
    }

    func generate(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat) async throws -> String {
        try await generate(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile, probeTag: nil)
    }

    func generateStream(
        prompt: String,
        maxTokens: Int = 256,
        samplingProfile: LLMSamplingProfile = .chat,
        probeTag: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        guard let model = model, let context = context else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMError.modelNotLoaded)
            }
        }
        let pointers = LoadedLlamaPointers(model: model, context: context)

        return AsyncThrowingStream<String, Error> { continuation in
            let worker = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: LLMError.modelNotLoaded)
                    return
                }

                do {
                    try await Self.inferenceGate.run {
                        try Self.runInferenceStreaming(
                            model: pointers.model,
                            context: pointers.context,
                            prompt: prompt,
                            maxTokens: maxTokens,
                            samplingProfile: samplingProfile,
                            probeTag: probeTag
                        ) { piece in
                            continuation.yield(piece)
                        }
                    }
                    continuation.finish()
                } catch {
                    if let probeTag {
                        ProbeLogger.log(ProbeChannel.llm, "task=\(probeTag) error=\(error)")
                    }
                    continuation.finish(throwing: error)
                }

                await MainActor.run {
                    self.isGenerating = false
                }
            }
            // ストリームが消費側でキャンセルされたら推論タスクもキャンセル
            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    func generateStream(prompt: String, maxTokens: Int = 256, samplingProfile: LLMSamplingProfile = .chat) -> AsyncThrowingStream<String, Error> {
        generateStream(prompt: prompt, maxTokens: maxTokens, samplingProfile: samplingProfile, probeTag: nil)
    }

    // MARK: - Vision (Multimodal)

    /// mmproj GGUFを読み込んでVisionを有効化（遅延ロード）
    func loadVision() async throws {
        guard !visionLoaded, let model = model else { return }

        guard let mmprojPath = findMmprojPath() else {
            throw missingAssetsError(fallbackAssetNames: ["mmproj-F16.gguf"])
        }

        #if DEBUG
        print("[Vision] mmproj読み込み開始: \(mmprojPath)")
        #endif
        let nThreads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))

        let modelPtr = SendableRawPointer(value: UnsafeMutableRawPointer(model))
        let visCtx = try await Task.detached(priority: .userInitiated) {
            guard let ctx = vision_context_create(
                mmprojPath,
                modelPtr.value,
                nThreads,
                true  // use_gpu
            ) else {
                throw LLMError.failedToLoadVision
            }
            return SendableRawPointer(value: ctx)
        }.value

        self.visionCtxPtr = visCtx.value
        self.visionLoaded = true
        #if DEBUG
        print("[Vision] mmproj読み込み完了")
        #endif
    }

    /// Visionコンテキストを解放してメモリを回復
    func unloadVision() {
        guard visionLoaded, let visCtx = visionCtxPtr else { return }
        #if DEBUG
        print("[Vision] メモリ警告によりVisionをアンロード")
        #endif
        vision_context_free(visCtx)
        visionCtxPtr = nil
        visionLoaded = false
    }

    func releaseBackgroundResources() {
        unloadVision()
    }

    func handleMemoryPressure() {
        unloadVision()
        guard !isGenerating else { return }
        unloadModel()
    }

    /// 画像付きプロンプトで推論（マルチモーダル）
    func generateWithImage(
        prompt: String,
        imageData: Data,
        maxTokens: Int = 256,
        samplingProfile: LLMSamplingProfile = .chat,
        probeTag: String? = nil
    ) async throws -> String {
        guard let model = model, let context = context, let visCtx = visionCtxPtr else {
            throw LLMError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        let modelPtr = SendableRawPointer(value: UnsafeMutableRawPointer(model))
        let ctxPtr = SendableRawPointer(value: UnsafeMutableRawPointer(context))
        let visCtxPtr = SendableRawPointer(value: visCtx)

        if let probeTag {
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) backend=vision n_ctx=\(llama_n_ctx(context)) \(ProbeLogger.samplingSummary(profile: samplingProfile, maxTokens: maxTokens))"
            )
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) prompt.original", text: prompt)
        }

        return try await Task.detached(priority: .userInitiated) {
            try await Self.inferenceGate.run {
                var outputBuf = [CChar](repeating: 0, count: 8192)
                let result = imageData.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> Int32 in
                    guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    return vision_generate(
                        visCtxPtr.value,
                        ctxPtr.value,
                        modelPtr.value,
                        prompt,
                        ptr,
                        rawBuf.count,
                        &outputBuf,
                        Int32(outputBuf.count),
                        Int32(maxTokens),
                        samplingProfile.temperature,
                        samplingProfile.topK,
                        samplingProfile.topP,
                        samplingProfile.minP,
                        samplingProfile.repeatPenalty,
                        samplingProfile.repeatLastN,
                        samplingProfile.seed ?? UInt32.random(in: 0...UInt32.max)
                    )
                }

                guard result == 0 else {
                    throw LLMError.visionInferenceFailed(result)
                }

                // Vision 推論は C++ 側で独自に KV キャッシュを操作するため、
                // Swift 側の cachedTokens と実際の KV キャッシュ内容が乖離する。
                // 次回テキスト推論が誤った KV キャッシュを再利用しないようクリアする。
                Self.cachedTokens.removeAll(keepingCapacity: true)

                let response = String(cString: outputBuf)
                if let probeTag {
                    ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) output.raw", text: response)
                }
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.value
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

    // MARK: - Private

    private func ensureRequiredAssetsAvailable() throws {
        guard let manifest = ModelDeliveryManifest.loadFromBundle() else { return }

        let report = assetStore.availabilityReport(for: manifest)
        guard report.isReady else {
            throw LLMError.modelSetupRequired(report.setupRequirement)
        }
    }

    private func missingAssetsError(fallbackAssetNames: [String]) -> LLMError {
        if let manifest = ModelDeliveryManifest.loadFromBundle() {
            let report = assetStore.availabilityReport(for: manifest)
            return .modelSetupRequired(report.setupRequirement)
        }

        let requirement = ModelSetupRequirement(
            assetNames: fallbackAssetNames,
            totalBytes: 0,
            requiredFreeSpaceBytes: 0,
            downloadConfigured: false,
            missingAssetNames: fallbackAssetNames,
            invalidAssetNames: []
        )
        return .modelSetupRequired(requirement)
    }

    private func findMmprojPath() -> String? {
        assetStore.preferredURL(forFileNamed: "mmproj-F16.gguf")?.path
    }

    /// Gemma 4 E2B のモデルファイルを Application Support → Bundle → Documents の順で探す。
    private func findModelPath() -> String? {
        if let preferredURL = assetStore.preferredURL(forFileNamed: Self.modelFileName) {
            return preferredURL.path
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: docs.path) {
            for prefix in Self.documentFilePrefixes {
                if let match = contents.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(".gguf") }) {
                    return docs.appendingPathComponent(match).path
                }
            }
        }
        return nil
    }

    /// prefill を n_batch 以下のチャンクに分割して順次 decode する。
    /// llama_decode に n_ubatch (=512) を超えるバッチを渡すと、内部 ubatch 分割で
    /// `GGML_ASSERT(n_outputs_prev + n_outputs <= n_outputs_all)` が発火するため、
    /// 必ず ≤ n_batch のサイズで投入し、最後のチャンクの末尾だけに logits=1 を立てる。
    private nonisolated static func prefillTokensChunked(
        context: OpaquePointer,
        tokens: [llama_token],
        startPos: Int
    ) throws {
        guard !tokens.isEmpty else { return }
        let nBatch = max(1, Int(llama_n_batch(context)))
        var offset = 0
        while offset < tokens.count {
            guard !Task.isCancelled else { throw CancellationError() }
            let end = min(offset + nBatch, tokens.count)
            let chunkLen = end - offset
            var batch = llama_batch_init(Int32(chunkLen), 0, 1)
            defer { llama_batch_free(batch) }
            for i in 0..<chunkLen {
                let absIdx = offset + i
                batch.token[i] = tokens[absIdx]
                batch.pos[i] = Int32(startPos + absIdx)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = 0
                let isLastOfAll = absIdx == (tokens.count - 1)
                batch.logits[i] = isLastOfAll ? 1 : 0
                batch.n_tokens += 1
            }
            guard llama_decode(context, batch) == 0 else { throw LLMError.decodeFailed }
            offset = end
        }
    }

    private nonisolated static func normalizePromptForModel(
        model: OpaquePointer,
        prompt: String
    ) -> String {
        let modelPtr = UnsafeRawPointer(model)
        guard let normalizedPtr = normalize_gemma_prompt_with_template(modelPtr, prompt) else {
            return prompt
        }
        defer { bridge_free_string(normalizedPtr) }
        return String(cString: normalizedPtr)
    }

    private nonisolated static func trimPromptTokens(
        _ tokens: [llama_token],
        contextSize: Int,
        maxTokens: Int
    ) -> PromptTrimResult {
        let budget = max(contextSize - maxTokens, contextSize / 2)
        guard tokens.count > budget else {
            return PromptTrimResult(
                tokens: tokens,
                beforeCount: tokens.count,
                afterCount: tokens.count,
                trimmed: false,
                headKept: tokens.count,
                tailKept: 0,
                budget: budget
            )
        }

        // 先頭の system 指示を残しつつ、最新履歴と generation prompt を優先する。
        let headCount = min(max(192, budget / 5), budget / 2)
        let tailCount = max(0, budget - headCount)

        if headCount + tailCount >= tokens.count {
            return PromptTrimResult(
                tokens: tokens,
                beforeCount: tokens.count,
                afterCount: tokens.count,
                trimmed: false,
                headKept: tokens.count,
                tailKept: 0,
                budget: budget
            )
        }

        let trimmedTokens = Array(tokens.prefix(headCount)) + Array(tokens.suffix(tailCount))
        return PromptTrimResult(
            tokens: trimmedTokens,
            beforeCount: tokens.count,
            afterCount: trimmedTokens.count,
            trimmed: true,
            headKept: headCount,
            tailKept: tailCount,
            budget: budget
        )
    }

    private nonisolated static func logPromptProbe(
        tag: String,
        prompt: String,
        normalizedPrompt: String,
        context: OpaquePointer,
        maxTokens: Int,
        samplingProfile: LLMSamplingProfile
    ) {
        ProbeLogger.log(
            ProbeChannel.llm,
            "task=\(tag) backend=llama.swift n_ctx=\(llama_n_ctx(context)) n_batch=\(llama_n_batch(context)) prompt_chars=\(prompt.count) normalized_chars=\(normalizedPrompt.count) \(ProbeLogger.samplingSummary(profile: samplingProfile, maxTokens: maxTokens))"
        )
        ProbeLogger.block(ProbeChannel.llm, title: "task=\(tag) prompt.original", text: prompt)
        if normalizedPrompt != prompt {
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(tag) prompt.normalized", text: normalizedPrompt)
        }
    }

    private nonisolated static func logTokenProbe(
        tag: String,
        trimResult: PromptTrimResult
    ) {
        ProbeLogger.log(
            ProbeChannel.llm,
            "task=\(tag) prompt_tokens_before_trim=\(trimResult.beforeCount) prompt_tokens_after_trim=\(trimResult.afterCount) trimmed=\(trimResult.trimmed) head_kept=\(trimResult.headKept) tail_kept=\(trimResult.tailKept) budget=\(trimResult.budget)"
        )
    }

    /// プロファイル値を反映した sampler chain を構築
    /// 順序: penalties → top_k → top_p → min_p → temperature → dist（llama.cpp推奨順序）
    private nonisolated static func makeSampler(profile: LLMSamplingProfile) -> UnsafeMutablePointer<llama_sampler> {
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(profile.repeatLastN, profile.repeatPenalty, 0.0, 0.0))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(profile.topK))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(profile.topP, 1))
        if profile.minP > 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p(profile.minP, 1))
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(profile.temperature))
        let seed = profile.seed ?? UInt32.random(in: 0...UInt32.max)
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed))
        return sampler
    }

    /// ストリーミング推論（KVキャッシュ再利用対応）
    /// 前回のプロンプトと共通プレフィックスがあれば、差分のみをprefillする
    private nonisolated static func runInferenceStreaming(
        model: OpaquePointer,
        context: OpaquePointer,
        prompt: String,
        maxTokens: Int,
        samplingProfile: LLMSamplingProfile,
        probeTag: String?,
        onToken: (String) -> Void
    ) throws {
        let vocab = llama_model_get_vocab(model)
        let normalizedPrompt = normalizePromptForModel(model: model, prompt: prompt)
        if let probeTag {
            logPromptProbe(
                tag: probeTag,
                prompt: prompt,
                normalizedPrompt: normalizedPrompt,
                context: context,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile
            )
        }

        // トークナイズ
        let promptCStr = normalizedPrompt.cString(using: .utf8)!
        var tokens = [llama_token](repeating: 0, count: promptCStr.count + 64)
        let nTokens = llama_tokenize(
            vocab, promptCStr, Int32(promptCStr.count),
            &tokens, Int32(tokens.count), true, true
        )
        guard nTokens > 0 else { throw LLMError.tokenizationFailed }

        let nCtx = Int(llama_n_ctx(context))
        let trimResult = trimPromptTokens(Array(tokens.prefix(Int(nTokens))), contextSize: nCtx, maxTokens: maxTokens)
        tokens = trimResult.tokens
        if let probeTag {
            logTokenProbe(tag: probeTag, trimResult: trimResult)
        }

        // KVキャッシュ再利用: 前回のトークンとの共通プレフィックスを検出
        let memory = llama_get_memory(context)
        let previousTokens = cachedTokens
        var commonPrefixLen = 0
        for i in 0..<min(previousTokens.count, tokens.count) {
            if previousTokens[i] == tokens[i] {
                commonPrefixLen = i + 1
            } else {
                break
            }
        }

        // 共通プレフィックスが十分長い場合のみKVキャッシュを再利用
        // 短すぎる場合は全クリアの方が安全（前回の生成トークンがKVキャッシュに残っているため、
        // seq_rmで中途半端に削除するとllama_decodeでクラッシュする）
        let minPrefixForReuse = 16
        if let probeTag {
            let reused = commonPrefixLen >= minPrefixForReuse && commonPrefixLen < tokens.count
            let newPrefill = reused ? max(0, tokens.count - commonPrefixLen) : tokens.count
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) kv_reuse common_prefix=\(commonPrefixLen) reused=\(reused) new_prefill=\(newPrefill)"
            )
        }
        if commonPrefixLen >= minPrefixForReuse && commonPrefixLen < tokens.count {
            // 共通プレフィックスがある → 差分のみdecode
            // 分岐点以降のKVキャッシュを削除
            llama_memory_seq_rm(memory, 0, Int32(commonPrefixLen), -1)
            let newTokens = Array(tokens[commonPrefixLen...])
            #if DEBUG
            print("[LLM] KVキャッシュ再利用: \(commonPrefixLen)トークン共通, \(newTokens.count)トークンのみprefill")
            #endif
            try prefillTokensChunked(context: context, tokens: newTokens, startPos: commonPrefixLen)
        } else {
            // 共通プレフィックスが短い/なし → 全クリアして全トークンdecode
            llama_memory_clear(memory, true)
            if commonPrefixLen > 0 {
                #if DEBUG
                print("[LLM] KVキャッシュ全クリア（共通\(commonPrefixLen)トークンは再利用に不十分）: \(tokens.count)トークンをprefill")
                #endif
            } else {
                #if DEBUG
                print("[LLM] KVキャッシュ全クリア: \(tokens.count)トークンをprefill")
                #endif
            }
            try prefillTokensChunked(context: context, tokens: tokens, startPos: 0)
        }

        // 今回のプロンプトトークンをキャッシュに保存
        cachedTokens = tokens

        // サンプリング設定（プロファイル別。値は GEMMA4_SETTING.md Preset B 準拠）
        let sampler = makeSampler(profile: samplingProfile)
        defer { llama_sampler_free(sampler) }

        var nCur = tokens.count
        var rawOutput = ""
        // マルチバイト UTF-8 文字が複数 token に跨がった場合の保留バッファ
        var pendingBytesStream: [UInt8] = []

        for _ in 0..<maxTokens {
            guard !Task.isCancelled else { throw CancellationError() }
            let newToken = llama_sampler_sample(sampler, context, -1)

            if llama_vocab_is_eog(vocab, newToken) { break }

            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, newToken, &buf, Int32(buf.count), 0, true)
            if len > 0 {
                for i in 0..<Int(len) {
                    pendingBytesStream.append(UInt8(bitPattern: buf[i]))
                }
                let (validBytes, remaining) = Self.splitValidUTF8Prefix(pendingBytesStream)
                pendingBytesStream = remaining
                if !validBytes.isEmpty, let piece = String(bytes: validBytes, encoding: .utf8) {
                    if piece.contains("<turn|>") {
                        let cleaned = piece.replacingOccurrences(of: "<turn|>", with: "")
                        if !cleaned.isEmpty {
                            rawOutput += cleaned
                            onToken(cleaned)
                        }
                        break
                    }
                    rawOutput += piece
                    onToken(piece)
                }
            }

            var nextBatch = llama_batch_init(1, 0, 1)
            nextBatch.token[0] = newToken
            nextBatch.pos[0] = Int32(nCur)
            nextBatch.n_seq_id[0] = 1
            nextBatch.seq_id[0]![0] = 0
            nextBatch.logits[0] = 1
            nextBatch.n_tokens = 1
            let decodeResult = llama_decode(context, nextBatch)
            llama_batch_free(nextBatch)

            guard decodeResult == 0 else { break }
            nCur += 1
        }

        if let probeTag {
            ProbeLogger.block(
                ProbeChannel.llm,
                title: "task=\(probeTag) output.raw",
                text: rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// 非ストリーミング推論（KVキャッシュ再利用対応）
    private nonisolated static func runInference(
        model: OpaquePointer,
        context: OpaquePointer,
        prompt: String,
        maxTokens: Int,
        samplingProfile: LLMSamplingProfile,
        probeTag: String?
    ) throws -> String {
        let vocab = llama_model_get_vocab(model)
        let normalizedPrompt = normalizePromptForModel(model: model, prompt: prompt)
        if let probeTag {
            logPromptProbe(
                tag: probeTag,
                prompt: prompt,
                normalizedPrompt: normalizedPrompt,
                context: context,
                maxTokens: maxTokens,
                samplingProfile: samplingProfile
            )
        }

        let promptCStr = normalizedPrompt.cString(using: .utf8)!
        var tokens = [llama_token](repeating: 0, count: promptCStr.count + 64)
        let nTokens = llama_tokenize(
            vocab, promptCStr, Int32(promptCStr.count),
            &tokens, Int32(tokens.count), true, true
        )
        guard nTokens > 0 else { throw LLMError.tokenizationFailed }

        let nCtx = Int(llama_n_ctx(context))
        let allTokens = Array(tokens.prefix(Int(nTokens)))
        let trimResult = trimPromptTokens(allTokens, contextSize: nCtx, maxTokens: maxTokens)
        tokens = trimResult.tokens
        if let probeTag {
            logTokenProbe(tag: probeTag, trimResult: trimResult)
        }
        if trimResult.trimmed {
            #if DEBUG
            print("[LLM] プロンプト切り詰め: \(nTokens) → \(tokens.count) tokens (n_ctx=\(nCtx), head+tail保持)")
            #endif
        }

        // KVキャッシュ再利用
        let memory = llama_get_memory(context)
        let previousTokens = cachedTokens
        var commonPrefixLen = 0
        for i in 0..<min(previousTokens.count, tokens.count) {
            if previousTokens[i] == tokens[i] {
                commonPrefixLen = i + 1
            } else {
                break
            }
        }

        // 共通プレフィックスが十分長い場合のみKVキャッシュを再利用
        let minPrefixForReuse = 16
        if let probeTag {
            let reused = commonPrefixLen >= minPrefixForReuse && commonPrefixLen < tokens.count
            let newPrefill = reused ? max(0, tokens.count - commonPrefixLen) : tokens.count
            ProbeLogger.log(
                ProbeChannel.llm,
                "task=\(probeTag) kv_reuse common_prefix=\(commonPrefixLen) reused=\(reused) new_prefill=\(newPrefill)"
            )
        }
        if commonPrefixLen >= minPrefixForReuse && commonPrefixLen < tokens.count {
            llama_memory_seq_rm(memory, 0, Int32(commonPrefixLen), -1)
            let newTokens = Array(tokens[commonPrefixLen...])
            #if DEBUG
            print("[LLM] KVキャッシュ再利用: \(commonPrefixLen)共通, \(newTokens.count)のみprefill")
            #endif
            try prefillTokensChunked(context: context, tokens: newTokens, startPos: commonPrefixLen)
        } else {
            llama_memory_clear(memory, true)
            if commonPrefixLen > 0 {
                #if DEBUG
                print("[LLM] KVキャッシュ全クリア（共通\(commonPrefixLen)トークンは再利用に不十分）: \(tokens.count)トークンをprefill")
                #endif
            } else {
                #if DEBUG
                print("[LLM] KVキャッシュ全クリア: \(tokens.count)トークンをprefill")
                #endif
            }
            try prefillTokensChunked(context: context, tokens: tokens, startPos: 0)
        }

        cachedTokens = tokens

        // サンプリング設定（プロファイル別。値は GEMMA4_SETTING.md Preset B 準拠）
        let sampler = makeSampler(profile: samplingProfile)
        defer { llama_sampler_free(sampler) }

        var output = ""
        var nCur = tokens.count
        // マルチバイト UTF-8 文字が複数 token に跨がった場合の保留バッファ
        var pendingBytes: [UInt8] = []

        for _ in 0..<maxTokens {
            guard !Task.isCancelled else { throw CancellationError() }
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Gemma 4: <turn|> や EOG トークンで停止
            if llama_vocab_is_eog(vocab, newToken) {
                break
            }

            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, newToken, &buf, Int32(buf.count), 0, true)
            if len > 0 {
                for i in 0..<Int(len) {
                    pendingBytes.append(UInt8(bitPattern: buf[i]))
                }
                let (validBytes, remaining) = Self.splitValidUTF8Prefix(pendingBytes)
                pendingBytes = remaining
                if !validBytes.isEmpty, let piece = String(bytes: validBytes, encoding: .utf8) {
                    // <turn|> が出力に含まれたら停止
                    if piece.contains("<turn|>") {
                        let cleaned = piece.replacingOccurrences(of: "<turn|>", with: "")
                        if !cleaned.isEmpty { output += cleaned }
                        break
                    }
                    output += piece
                }
            }

            // 次のトークンをデコード
            var nextBatch = llama_batch_init(1, 0, 1)
            nextBatch.token[0] = newToken
            nextBatch.pos[0] = Int32(nCur)
            nextBatch.n_seq_id[0] = 1
            nextBatch.seq_id[0]![0] = 0
            nextBatch.logits[0] = 1
            nextBatch.n_tokens = 1
            let decodeResult = llama_decode(context, nextBatch)
            llama_batch_free(nextBatch)

            guard decodeResult == 0 else { break }
            nCur += 1
        }

        let finalOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let probeTag {
            ProbeLogger.block(ProbeChannel.llm, title: "task=\(probeTag) output.raw", text: finalOutput)
        }
        return finalOutput
    }

    /// UTF-8 バイト列を「完全な先頭プレフィックス」と「残り不完全バイト」に分ける。
    ///
    /// llama.cpp の `llama_token_to_piece` は token ごとに UTF-8 バイトを返すが、
    /// マルチバイト文字（日本語等）は複数 token に分割されて返ることがある。
    /// 個別に `String(cString:)` で変換すると中間バイトが壊れ字（U+FFFD）になるため、
    /// バッファで累積してからこのヘルパーで安全なプレフィックスだけを切り出す。
    nonisolated static func splitValidUTF8Prefix(_ bytes: [UInt8]) -> (valid: [UInt8], remaining: [UInt8]) {
        if bytes.isEmpty { return ([], []) }
        // 末尾から最大 3 バイト（UTF-8 最長 4 バイトの先頭を捕捉するため）を遡り、
        // 「次の UTF-8 コードポイントの開始位置」を探す
        let minIndex = max(0, bytes.count - 4)
        var cutIndex = bytes.count
        for i in stride(from: bytes.count - 1, through: minIndex, by: -1) {
            let b = bytes[i]
            if b & 0x80 == 0 {
                // ASCII。これ自身を含めてここまで完全
                cutIndex = i + 1
                break
            } else if b & 0xC0 == 0x80 {
                // 継続バイト。先頭バイトをさらに遡る
                continue
            } else {
                // マルチバイトの先頭
                let expectedLen: Int
                if b & 0xE0 == 0xC0 { expectedLen = 2 }
                else if b & 0xF0 == 0xE0 { expectedLen = 3 }
                else if b & 0xF8 == 0xF0 { expectedLen = 4 }
                else { expectedLen = 1 }
                let haveBytes = bytes.count - i
                if haveBytes >= expectedLen {
                    cutIndex = i + expectedLen
                } else {
                    cutIndex = i // ここからは未完成 — 次 token 待ち
                }
                break
            }
        }
        if cutIndex >= bytes.count {
            return (bytes, [])
        }
        return (Array(bytes[0..<cutIndex]), Array(bytes[cutIndex...]))
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let visCtx = visionCtxPtr {
            vision_context_free(visCtx)
        }
        if let context = context {
            llama_free(context)
        }
        if let model = model {
            llama_model_free(model)
        }
        llama_backend_free()
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelSetupRequired(ModelSetupRequirement)
    case modelNotFound(String)
    case failedToLoadModel
    case failedToCreateContext
    case modelNotLoaded
    case tokenizationFailed
    case decodeFailed
    case failedToLoadVision
    case visionInferenceFailed(Int32)
    case modelTooLargeForDevice(modelSizeMB: Int, deviceMemoryGB: Double)

    var errorDescription: String? {
        switch self {
        case .modelSetupRequired(let requirement):
            let names = requirement.missingOrInvalidAssetNames
            if names.isEmpty {
                return "MyBuddyの準備が必要です"
            }
            return "MyBuddyの準備が必要です: \(names.joined(separator: "、"))"
        case .modelNotFound(let name):
            return "モデルファイルが見つかりません: \(name)"
        case .failedToLoadModel:
            return "モデルの読み込みに失敗しました"
        case .failedToCreateContext:
            return "コンテキストの作成に失敗しました"
        case .modelNotLoaded:
            return "モデルがまだ読み込まれていません"
        case .tokenizationFailed:
            return "トークナイズに失敗しました"
        case .decodeFailed:
            return "デコードに失敗しました"
        case .failedToLoadVision:
            return "Vision(mmproj)の読み込みに失敗しました"
        case .visionInferenceFailed(let code):
            return "画像推論に失敗しました (code: \(code))"
        case .modelTooLargeForDevice(let sizeMB, let memGB):
            return "メモリ不足: モデル(\(sizeMB)MB)がデバイス(\(String(format: "%.0f", memGB))GB RAM)に対して大きすぎます。より小さいモデルをお試しください"
        }
    }
}
