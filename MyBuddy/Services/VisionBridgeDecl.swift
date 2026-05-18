import Foundation

// Swift declarations for C functions in VisionBridge.cpp
// Using @_silgen_name to directly link to C symbols without a bridging header
// nonisolated: these are pure C functions, not actor-isolated

@_silgen_name("vision_context_create")
nonisolated func vision_context_create(
    _ mmproj_path: UnsafePointer<CChar>?,
    _ llama_model_ptr: UnsafeRawPointer?,
    _ n_threads: Int32,
    _ use_gpu: Bool
) -> UnsafeMutableRawPointer?

@_silgen_name("vision_context_free")
nonisolated func vision_context_free(
    _ ctx: UnsafeMutableRawPointer?
)

@_silgen_name("vision_context_supports_vision")
nonisolated func vision_context_supports_vision(
    _ ctx: UnsafeMutableRawPointer?
) -> Bool

@_silgen_name("normalize_gemma_prompt_with_template")
nonisolated func normalize_gemma_prompt_with_template(
    _ llama_model_ptr: UnsafeRawPointer?,
    _ prompt: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("bridge_free_string")
nonisolated func bridge_free_string(
    _ ptr: UnsafeMutablePointer<CChar>?
)

@_silgen_name("vision_generate")
nonisolated func vision_generate(
    _ ctx: UnsafeMutableRawPointer?,
    _ llama_ctx_ptr: UnsafeMutableRawPointer?,
    _ llama_model_ptr: UnsafeRawPointer?,
    _ prompt: UnsafePointer<CChar>?,
    _ image_data: UnsafePointer<UInt8>?,
    _ image_len: Int,
    _ output_buf: UnsafeMutablePointer<CChar>?,
    _ output_buf_size: Int32,
    _ max_tokens: Int32,
    _ temperature: Float,
    _ top_k: Int32,
    _ top_p: Float,
    _ min_p: Float,
    _ repeat_penalty: Float,
    _ repeat_last_n: Int32,
    _ seed: UInt32
) -> Int32
