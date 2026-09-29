#include <jni.h>

#include <algorithm>
#include <fstream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

#if NOTES_NEEDLE_ARM64
#include "needle.h"
#endif

namespace {

std::mutex g_mutex;
bool g_loaded = false;
bool g_initialized = false;
std::string g_model_path;

std::string jstringToUtf8(JNIEnv* env, jstring value) {
    if (value == nullptr) return {};
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return {};
    std::string out(chars);
    env->ReleaseStringUTFChars(value, chars);
    return out;
}

jstring utf8ToJstring(JNIEnv* env, const std::string& value) {
    return env->NewStringUTF(value.c_str());
}

void throwRuntime(JNIEnv* env, const std::string& message) {
    jclass clazz = env->FindClass("java/lang/IllegalStateException");
    if (clazz != nullptr) {
        env->ThrowNew(clazz, message.c_str());
    }
}

#if NOTES_NEEDLE_ARM64
std::string lastNeedleError(const std::string& fallback) {
    const char* detail = needle_last_error();
    if (detail != nullptr && detail[0] != '\0') return std::string(detail);
    return fallback;
}

std::vector<unsigned char> readFile(const std::string& path) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) throw std::runtime_error("Impossibile aprire il modello Needle.");
    const auto size = stream.tellg();
    if (size <= 0) throw std::runtime_error("Modello Needle vuoto.");
    stream.seekg(0, std::ios::beg);
    std::vector<unsigned char> bytes(static_cast<size_t>(size));
    if (!stream.read(reinterpret_cast<char*>(bytes.data()), size)) {
        throw std::runtime_error("Lettura del modello Needle non riuscita.");
    }
    return bytes;
}
#endif

}  // namespace

extern "C"
JNIEXPORT jboolean JNICALL
Java_it_notes_ecosystem_notes_1ecosistema_NeedleNative_nativeSupported(
    JNIEnv*,
    jobject
) {
#if NOTES_NEEDLE_ARM64
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
}

extern "C"
JNIEXPORT jint JNICALL
Java_it_notes_ecosystem_notes_1ecosistema_NeedleNative_nativeLoad(
    JNIEnv* env,
    jobject,
    jstring modelPath,
    jstring systemPrompt,
    jstring toolsJson
) {
#if NOTES_NEEDLE_ARM64
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        const std::string path = jstringToUtf8(env, modelPath);
        const std::string system = jstringToUtf8(env, systemPrompt);
        const std::string tools = jstringToUtf8(env, toolsJson);
        if (path.empty()) throw std::runtime_error("Percorso modello Needle mancante.");
        if (tools.empty()) throw std::runtime_error("Schema strumenti Needle mancante.");

        if (!g_loaded || g_model_path != path) {
            const auto weights = readFile(path);
            const int loaded = needle_load(
                weights.data(),
                static_cast<unsigned long long>(weights.size())
            );
            if (loaded < 0) {
                throw std::runtime_error(
                    lastNeedleError("needle_load non riuscito.")
                );
            }
            g_loaded = true;
            g_initialized = false;
            g_model_path = path;
        }

        const int prefixTokens = needle_init(
            system.c_str(),
            tools.c_str(),
            nullptr
        );
        if (prefixTokens < 0) {
            throw std::runtime_error(
                lastNeedleError("needle_init non riuscito.")
            );
        }
        g_initialized = true;
        return prefixTokens;
    } catch (const std::exception& error) {
        throwRuntime(env, error.what());
        return -1;
    }
#else
    throwRuntime(env, "Needle 3 locale richiede Android ARM64.");
    return -1;
#endif
}

extern "C"
JNIEXPORT jstring JNICALL
Java_it_notes_ecosystem_notes_1ecosistema_NeedleNative_nativeComplete(
    JNIEnv* env,
    jobject,
    jstring input,
    jint maxNewTokens
) {
#if NOTES_NEEDLE_ARM64
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_loaded || !g_initialized) {
        throwRuntime(env, "Needle non inizializzato.");
        return nullptr;
    }

    const std::string prompt = jstringToUtf8(env, input);
    const int boundedTokens = std::clamp(static_cast<int>(maxNewTokens), 16, 768);
    std::vector<char> output(65536, '\0');

    const int code = needle_complete(
        prompt.c_str(),
        boundedTokens,
        output.data(),
        static_cast<int>(output.size())
    );
    if (code < 0) {
        throwRuntime(
            env,
            lastNeedleError("needle_complete non riuscito.")
        );
        return nullptr;
    }
    return utf8ToJstring(env, std::string(output.data()));
#else
    throwRuntime(env, "Needle 3 locale richiede Android ARM64.");
    return nullptr;
#endif
}

extern "C"
JNIEXPORT void JNICALL
Java_it_notes_ecosystem_notes_1ecosistema_NeedleNative_nativeReset(
    JNIEnv*,
    jobject
) {
#if NOTES_NEEDLE_ARM64
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_loaded && g_initialized) needle_reset();
#endif
}

extern "C"
JNIEXPORT jstring JNICALL
Java_it_notes_ecosystem_notes_1ecosistema_NeedleNative_nativeLastError(
    JNIEnv* env,
    jobject
) {
#if NOTES_NEEDLE_ARM64
    std::lock_guard<std::mutex> lock(g_mutex);
    return utf8ToJstring(env, lastNeedleError(""));
#else
    return utf8ToJstring(env, "Needle 3 locale richiede Android ARM64.");
#endif
}
