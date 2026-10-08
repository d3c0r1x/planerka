#include <jni.h>
#include <llama.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
std::mutex engine_mutex;
std::atomic<bool> cancel_requested{false};
llama_model * loaded_model = nullptr;
std::string loaded_path;

std::string from_java(JNIEnv * env, jstring value) {
    if (value == nullptr) return {};
    const char * chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

std::string apply_template(const llama_model * model, const std::string & prompt) {
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (tmpl == nullptr) return prompt;
    const llama_chat_message messages[] = {
        {"system", "Ты локальный помощник приложения Планёрка. Отвечай кратко и по-русски. Не показывай ход рассуждений. Выводи только готовый ответ."},
        {"user", prompt.c_str()},
    };
    const int32_t required = llama_chat_apply_template(tmpl, messages, 2, true, nullptr, 0);
    if (required <= 0) return prompt;
    std::vector<char> formatted(static_cast<size_t>(required) + 1);
    const int32_t written = llama_chat_apply_template(
        tmpl, messages, 2, true, formatted.data(), static_cast<int32_t>(formatted.size()));
    if (written <= 0) return prompt;
    return std::string(formatted.data(), static_cast<size_t>(written));
}

llama_model * model_for_path(const std::string & path) {
    if (loaded_model != nullptr && loaded_path == path) return loaded_model;
    if (loaded_model != nullptr) {
        llama_model_free(loaded_model);
        loaded_model = nullptr;
        loaded_path.clear();
    }
    auto params = llama_model_default_params();
    params.n_gpu_layers = 0;
    loaded_model = llama_model_load_from_file(path.c_str(), params);
    if (loaded_model != nullptr) loaded_path = path;
    return loaded_model;
}
}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_planerka_mobile_LocalAiNative_generate(
    JNIEnv * env, jobject, jstring model_path, jstring user_prompt, jint max_tokens) {
    std::lock_guard<std::mutex> lock(engine_mutex);
    cancel_requested.store(false);
    const std::string path = from_java(env, model_path);
    const std::string input = from_java(env, user_prompt);
    if (path.empty() || input.empty()) return nullptr;

    llama_backend_init();
    llama_model * model = model_for_path(path);
    if (model == nullptr) {
        const std::string error = "Не удалось открыть проверенную локальную модель.";
        return env->NewStringUTF(error.c_str());
    }

    const std::string formatted = apply_template(model, input + "\n/no_think");
    const llama_vocab * vocab = llama_model_get_vocab(model);
    const int32_t needed = -llama_tokenize(vocab, formatted.c_str(),
        static_cast<int32_t>(formatted.size()), nullptr, 0, true, true);
    if (needed <= 0 || needed > 2048) {
        const std::string error = "Запрос слишком длинный для локального режима.";
        return env->NewStringUTF(error.c_str());
    }
    std::vector<llama_token> tokens(static_cast<size_t>(needed));
    const int32_t token_count = llama_tokenize(vocab, formatted.c_str(),
        static_cast<int32_t>(formatted.size()), tokens.data(), needed, true, true);
    if (token_count <= 0) return env->NewStringUTF("Не удалось разобрать запрос.");

    auto context_params = llama_context_default_params();
    const auto trained_context = static_cast<uint32_t>(
        llama_model_n_ctx_train(model));
    // Qwen3-0.6B is trained for 32K tokens. A personal planning prompt and
    // short recommendation do not need that cache; cap it to keep memory and
    // startup time practical on 8 GB phones and emulators.
    context_params.n_ctx = std::min<uint32_t>(2048, trained_context);
    context_params.n_batch = 256;
    context_params.n_ubatch = 128;
    const auto available_threads = static_cast<int32_t>(
        std::thread::hardware_concurrency());
    context_params.n_threads = std::clamp(available_threads, 2, 4);
    context_params.n_threads_batch = context_params.n_threads;
    llama_context * context = llama_init_from_model(model, context_params);
    if (context == nullptr) return env->NewStringUTF("Недостаточно памяти для локального ответа.");

    llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    llama_batch batch = llama_batch_get_one(tokens.data(), token_count);
    std::string output;
    if (llama_decode(context, batch) == 0) {
        const int limit = std::clamp(static_cast<int>(max_tokens), 1, 512);
        for (int i = 0; i < limit && !cancel_requested.load(); ++i) {
            llama_token token = llama_sampler_sample(sampler, context, -1);
            llama_sampler_accept(sampler, token);
            if (llama_vocab_is_eog(vocab, token)) break;
            char piece[256];
            const int32_t size = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
            if (size > 0) output.append(piece, static_cast<size_t>(size));
            batch = llama_batch_get_one(&token, 1);
            if (llama_decode(context, batch) != 0) break;
        }
    }
    llama_sampler_free(sampler);
    llama_free(context);
    return env->NewStringUTF(output.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_planerka_mobile_LocalAiNative_loadModel(JNIEnv * env, jobject, jstring model_path) {
    std::lock_guard<std::mutex> lock(engine_mutex);
    llama_backend_init();
    return model_for_path(from_java(env, model_path)) != nullptr ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_planerka_mobile_LocalAiNative_unload(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(engine_mutex);
    if (loaded_model != nullptr) {
        llama_model_free(loaded_model);
        loaded_model = nullptr;
        loaded_path.clear();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_planerka_mobile_LocalAiNative_cancel(JNIEnv *, jobject) {
    cancel_requested.store(true);
}
