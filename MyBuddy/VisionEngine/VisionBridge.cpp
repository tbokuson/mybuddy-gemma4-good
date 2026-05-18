#include "VisionBridge.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include "llama.h"

#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>

struct VisionContext {
    mtmd_context * mtmd_ctx;
};

VisionContext * vision_context_create(const char * mmproj_path,
                                      const void * llama_model_ptr,
                                      int n_threads, bool use_gpu) {
    if (!mmproj_path || !llama_model_ptr) return nullptr;

    auto * model = (const llama_model *)llama_model_ptr;

    mtmd_context_params params = mtmd_context_params_default();
    params.use_gpu = use_gpu;
    params.n_threads = n_threads;
    params.print_timings = true;
    params.warmup = true;

    auto * mtmd_ctx = mtmd_init_from_file(mmproj_path, model, params);
    if (!mtmd_ctx) return nullptr;

    auto * ctx = new VisionContext();
    ctx->mtmd_ctx = mtmd_ctx;
    return ctx;
}

void vision_context_free(VisionContext * ctx) {
    if (ctx) {
        if (ctx->mtmd_ctx) mtmd_free(ctx->mtmd_ctx);
        delete ctx;
    }
}

bool vision_context_supports_vision(VisionContext * ctx) {
    return ctx && ctx->mtmd_ctx && mtmd_support_vision(ctx->mtmd_ctx);
}

char * normalize_gemma_prompt_with_template(const void * llama_model_ptr,
                                            const char * prompt) {
    if (!llama_model_ptr || !prompt) return nullptr;

    const auto * model = (const llama_model *)llama_model_ptr;
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (!tmpl) return nullptr;

    const std::string source(prompt);
    const std::string open_turn = "<|turn>";
    const std::string close_turn = "<turn|>";

    if (source.find(open_turn) != 0) {
        return nullptr;
    }

    struct ParsedMessage {
        std::string role;
        std::string content;
    };

    std::vector<ParsedMessage> parsed;
    size_t pos = 0;
    bool add_generation_prompt = false;

    while (pos < source.size()) {
        if (source.compare(pos, open_turn.size(), open_turn) != 0) {
            return nullptr;
        }
        pos += open_turn.size();

        const size_t newline = source.find('\n', pos);
        if (newline == std::string::npos) {
            return nullptr;
        }

        std::string role = source.substr(pos, newline - pos);
        pos = newline + 1;

        const size_t close = source.find(close_turn, pos);
        if (close == std::string::npos) {
            if (role == "model") {
                add_generation_prompt = true;
                break;
            }
            return nullptr;
        }

        std::string content = source.substr(pos, close - pos);
        pos = close + close_turn.size();
        if (pos < source.size() && source[pos] == '\n') {
            pos += 1;
        }

        if (role == "model") {
            role = "assistant";
        }
        if (role == "system" && content.rfind("<|think|>", 0) == 0) {
            const size_t token_len = std::strlen("<|think|>");
            if (content.size() > token_len && content[token_len] != '\n') {
                content.insert(token_len, "\n");
            }
        }

        parsed.push_back({role, content});
    }

    if (parsed.empty()) {
        return nullptr;
    }

    std::vector<llama_chat_message> messages;
    messages.reserve(parsed.size());
    for (const auto & msg : parsed) {
        messages.push_back({msg.role.c_str(), msg.content.c_str()});
    }

    const int32_t required = llama_chat_apply_template(
        tmpl,
        messages.data(),
        messages.size(),
        add_generation_prompt,
        nullptr,
        0
    );
    if (required <= 0) {
        return nullptr;
    }

    auto * out = (char *) std::malloc((size_t) required + 1);
    if (!out) {
        return nullptr;
    }

    const int32_t written = llama_chat_apply_template(
        tmpl,
        messages.data(),
        messages.size(),
        add_generation_prompt,
        out,
        required + 1
    );
    if (written <= 0) {
        std::free(out);
        return nullptr;
    }

    out[written] = '\0';
    return out;
}

void bridge_free_string(char * ptr) {
    std::free(ptr);
}

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
                        uint32_t seed) {
    if (!ctx || !ctx->mtmd_ctx || !llama_ctx_ptr || !llama_model_ptr || !prompt) return -1;
    if (!image_data || image_len == 0) return -1;
    if (!output_buf || output_buf_size <= 0) return -1;

    auto * lctx  = (llama_context *)llama_ctx_ptr;
    auto * model = (const llama_model *)llama_model_ptr;

    // Clear KV cache
    auto * memory = llama_get_memory(lctx);
    llama_memory_clear(memory, true);

    // Create bitmap from image data (JPEG/PNG bytes)
    auto * bitmap = mtmd_helper_bitmap_init_from_buf(ctx->mtmd_ctx, image_data, image_len);
    if (!bitmap) return -2;

    // Tokenize: prompt with <__media__> marker + image bitmap
    auto * chunks = mtmd_input_chunks_init();
    if (!chunks) {
        mtmd_bitmap_free(bitmap);
        return -3;
    }

    mtmd_input_text text;
    text.text          = prompt;
    text.add_special   = true;
    text.parse_special = true;

    const mtmd_bitmap * bitmap_ptr = bitmap;
    int32_t tok_result = mtmd_tokenize(ctx->mtmd_ctx, chunks, &text, &bitmap_ptr, 1);
    mtmd_bitmap_free(bitmap);

    if (tok_result != 0) {
        mtmd_input_chunks_free(chunks);
        return -4;
    }

    // Evaluate all chunks (text + image embeddings)
    llama_pos new_n_past = 0;
    int32_t eval_result = mtmd_helper_eval_chunks(
        ctx->mtmd_ctx, lctx, chunks, 0, 0, 512, true, &new_n_past);
    mtmd_input_chunks_free(chunks);

    if (eval_result != 0) return -5;

    // Sample tokens
    auto * vocab = llama_model_get_vocab(model);

    auto * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(repeat_last_n, repeat_penalty, 0.0f, 0.0f));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    if (min_p > 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(min_p, 1));
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));

    int32_t n_cur = new_n_past;
    int32_t output_pos = 0;

    for (int32_t i = 0; i < max_tokens; i++) {
        auto new_token = llama_sampler_sample(sampler, lctx, -1);

        // Stop on end-of-generation
        if (llama_vocab_is_eog(vocab, new_token)) break;

        // Convert token to text
        char buf[256];
        int32_t len = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
        if (len > 0) {
            buf[len] = 0;

            // Stop on Gemma turn marker
            if (strstr(buf, "<turn|>")) {
                // Write partial text before marker if any
                const char * marker = strstr(buf, "<turn|>");
                int32_t before_len = (int32_t)(marker - buf);
                if (before_len > 0 && output_pos + before_len < output_buf_size - 1) {
                    memcpy(output_buf + output_pos, buf, before_len);
                    output_pos += before_len;
                }
                break;
            }

            // Append to output buffer
            int32_t to_copy = len;
            if (output_pos + to_copy >= output_buf_size - 1) {
                to_copy = output_buf_size - 1 - output_pos;
            }
            if (to_copy > 0) {
                memcpy(output_buf + output_pos, buf, to_copy);
                output_pos += to_copy;
            }
        }

        // Decode next token
        llama_batch next_batch = llama_batch_init(1, 0, 1);
        next_batch.token[0]    = new_token;
        next_batch.pos[0]      = n_cur;
        next_batch.n_seq_id[0] = 1;
        next_batch.seq_id[0][0] = 0;
        next_batch.logits[0]   = 1;
        next_batch.n_tokens    = 1;

        int32_t dec_result = llama_decode(lctx, next_batch);
        llama_batch_free(next_batch);
        if (dec_result != 0) break;

        n_cur++;
    }

    llama_sampler_free(sampler);
    output_buf[output_pos] = 0;  // null-terminate

    return 0;
}
