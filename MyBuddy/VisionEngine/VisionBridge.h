#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle for vision context (wraps mtmd_context)
typedef struct VisionContext VisionContext;

// Initialize vision context from mmproj GGUF file
// llama_model_ptr: the loaded llama_model* (cast to void*)
// Returns NULL on failure
VisionContext * vision_context_create(const char * mmproj_path,
                                      const void * llama_model_ptr,
                                      int n_threads, bool use_gpu);

// Free vision context
void vision_context_free(VisionContext * ctx);

// Check if the loaded model supports vision input
bool vision_context_supports_vision(VisionContext * ctx);

// Normalize a manually constructed Gemma prompt with the model's built-in
// chat template. Returns a newly allocated UTF-8 string on success, or NULL
// when normalization is not possible. Caller must free it with bridge_free_string().
char * normalize_gemma_prompt_with_template(const void * llama_model_ptr,
                                            const char * prompt);

void bridge_free_string(char * ptr);

// Run multimodal inference (image + text -> generated text)
//
// prompt: Gemma4-formatted prompt, must contain <__media__> where image goes
// image_data/image_len: raw image bytes (JPEG, PNG, etc.)
// llama_ctx_ptr: the llama_context* (cast to void*)
// llama_model_ptr: the llama_model* (cast to void*)
// output_buf/output_buf_size: buffer for null-terminated generated text
// max_tokens: maximum tokens to generate
//
// Returns 0 on success, negative on failure
int32_t vision_generate(VisionContext * ctx,
                        void * llama_ctx_ptr,
                        const void * llama_model_ptr,
                        const char * prompt,
                        const unsigned char * image_data, size_t image_len,
                        char * output_buf, int32_t output_buf_size,
                        int32_t max_tokens,
                        float temperature,
                        int32_t top_k,
                        float top_p,
                        float min_p,
                        float repeat_penalty,
                        int32_t repeat_last_n,
                        uint32_t seed);

#ifdef __cplusplus
}
#endif
