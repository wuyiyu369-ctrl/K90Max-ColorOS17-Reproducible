#include <aidl/vendor/oplus/hardware/urcc/BnUrcc.h>

#include <android/log.h>
#include <dlfcn.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace urcc = aidl::vendor::oplus::hardware::urcc;

extern "C" binder_status_t AServiceManager_addService(
        AIBinder* binder, const char* instance);
extern "C" void ABinderProcess_setThreadPoolMaxThreadCount(uint32_t num_threads);
extern "C" void ABinderProcess_startThreadPool();
extern "C" void ABinderProcess_joinThreadPool();

namespace {

using HintFn = int64_t (*)(int64_t, int, int, int, const char*);
using ReleaseFn = void (*)(int64_t);

struct HintSelection {
    int id = 0x1081;
    int type = 1;
    int duration_ms = 3000;
    const char* reason = "generic";
};

#ifndef K90_OPAQUE_URCC_REQUEST
std::string lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

bool has_any(const std::string& text, std::initializer_list<const char*> needles) {
    for (const char* needle : needles) {
        if (text.find(needle) != std::string::npos) return true;
    }
    return false;
}

std::string summarize(const urcc::UrccRequestParcel& request) {
    std::string text = request.identity;
    text.push_back(' ');
    text += request.pkgName;
    for (const std::string& param : request.mParams) {
        text.push_back(' ');
        text += param;
    }
    for (const urcc::UrccRequestData& data : request.mUrccRequestData) {
        text.push_back(' ');
        text += data.desc;
        text.push_back(' ');
        text += data.res_Path;
        text.push_back(' ');
        text += data.res_Value;
    }
    return lower(text);
}

HintSelection select_hint(const urcc::UrccRequestParcel& request) {
    const std::string text = summarize(request);
    HintSelection result;
    const int64_t requested = request.duration;
    result.duration_ms = static_cast<int>(
            std::clamp<int64_t>(requested > 0 ? requested : 3000, 100, 5000));

    if (has_any(text, {"scroll", "fling", "touch", "animation", "rotation",
                       "sidebar", "input_method"})) {
        result.id = 0x1080;
        result.type = 1;  // Xiaomi map: MTK hint 900, bounded to 3 seconds.
        result.duration_ms = std::min(result.duration_ms, 3000);
        result.reason = "interactive";
    } else if (has_any(text, {"launcher_gpu", "vfx", "highlight", "foreground"})) {
        result.id = 0x11a0;
        result.type = 2;  // Xiaomi map: MTK hint 912, bounded to 2 seconds.
        result.duration_ms = std::min(result.duration_ms, 2000);
        result.reason = "ui-gpu";
    } else if (has_any(text, {"game", "hyperboost", "camera", "storage", "ufs",
                              "gpu", "ddr", "xpu", "benchmark", "antutu"})) {
        result.id = 0x1081;
        result.type = 4;  // Xiaomi map: MTK game-launch hint 54.
        result.duration_ms = std::min(result.duration_ms, 5000);
        result.reason = "heavy";
    } else if (has_any(text, {"launch", "screen_on", "unlock", "assistant",
                              "audio", "mtp", "video"})) {
        result.id = 0x1081;
        result.type = 1;  // Xiaomi map: MTK launch hint 21.
        result.duration_ms = std::min(result.duration_ms, 5000);
        result.reason = "launch";
    }
    return result;
}
#endif

class K90Urcc final : public urcc::BnUrcc {
public:
    K90Urcc() {
        library_ = dlopen("/vendor/lib64/libuniperf_client_vendor.so",
                          RTLD_NOW | RTLD_LOCAL);
        if (library_) {
            hint_ = reinterpret_cast<HintFn>(dlsym(library_, "UniperfHint"));
            release_ = reinterpret_cast<ReleaseFn>(dlsym(library_, "UniperfRelease"));
        }
        __android_log_print(hint_ ? ANDROID_LOG_INFO : ANDROID_LOG_ERROR,
                            "K90Urcc", "start uniperf=%s", hint_ ? "ready" : "missing");
    }

    ~K90Urcc() override {
        std::lock_guard<std::mutex> guard(lock_);
        if (release_) {
            for (const auto& [handle, vendor_handle] : handles_) {
                (void)handle;
                if (vendor_handle > 0) release_(vendor_handle);
            }
        }
        handles_.clear();
        if (library_) dlclose(library_);
    }

    ndk::ScopedAStatus urccInit() override {
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc", "urccInit");
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccResCtlRequest(
            const urcc::UrccRequestParcel& request, int32_t* result) override {
        *result = acquire(request, false);
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccResCtlRelease(int32_t handle, int32_t* result) override {
        std::lock_guard<std::mutex> guard(lock_);
        auto it = handles_.find(handle);
        if (it != handles_.end()) {
            if (release_ && it->second > 0) release_(it->second);
            handles_.erase(it);
            *result = 0;
        } else {
            // Release is idempotent in the compatibility layer.
            *result = 0;
        }
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "release handle=%d active=%zu", handle, handles_.size());
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccResStateRequest(
            const urcc::UrccRequestParcel& request,
            std::vector<urcc::UrccRequestData>* result) override {
#ifdef K90_OPAQUE_URCC_REQUEST
        // The shipping ColorOS parcelable has a private in-memory layout even
        // though its stable AIDL hash matches the published interface. The
        // platform wire library has already decoded the request; do not inspect
        // it again through headers generated from the public declaration.
        (void)request;
        result->clear();
#else
        // Preserve the caller's resource identities. Values are deliberately
        // not fabricated; the translated UniPerf request is observable in logcat.
        *result = request.mUrccRequestData;
#endif
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccResListeningRegister(
            const urcc::UrccRequestParcel& request,
            const std::shared_ptr<urcc::IUrccCallback>& callback,
            int32_t* result) override {
        (void)callback;
        *result = acquire(request, false);
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccResListeningUnRegister(
            int32_t handle, int32_t* result) override {
        return urccResCtlRelease(handle, result);
    }

    ndk::ScopedAStatus urccPropertyGet(
            const std::string& name, std::string* result) override {
        if (name == "vendor.oplus.hardware.urcc.backend") {
            *result = hint_ ? "xiaomi-uniperf" : "unavailable";
        } else {
            result->clear();
        }
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccPropertySet(
            const std::string& name, const std::string& value,
            int32_t* result) override {
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "property-set name=%s value=%s",
                            name.c_str(), value.c_str());
        *result = 0;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccThermalListeningRegister(
            const std::vector<int32_t>& types,
            const std::shared_ptr<urcc::IUrccCallback>& callback,
            int32_t* result) override {
        (void)types;
        (void)callback;
        *result = next_handle_.fetch_add(1);
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccThermalListeningUnRegister(
            int32_t handle, int32_t* result) override {
        (void)handle;
        *result = 0;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus uahNotifyExt(
            int32_t src, int32_t type, const std::vector<int32_t>& args,
            int32_t* result) override {
        const int duration = args.empty() ? 1000 :
                std::clamp(args.back(), 100, 3000);
        const int64_t vendor_handle = hint_ ?
                hint_(0, 0x1080, 1, duration, "uahNotifyExt") : 0;
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "notify src=%d type=%d args=%zu vendor=%lld",
                            src, type, args.size(),
                            static_cast<long long>(vendor_handle));
        *result = vendor_handle > 0 ? 0 : -1;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus setRelatedSysInfo(
            int32_t cmd, const std::vector<uint8_t>& info,
            int32_t* result) override {
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "related-info cmd=%d bytes=%zu", cmd, info.size());
        *result = 0;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus urccRuleCtl(
            int32_t rule_id, int32_t status,
            const std::vector<urcc::UrccRequestData>& rule_data,
            int32_t* result) override {
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "rule id=%d status=%d data=%zu",
                            rule_id, status, rule_data.size());
        *result = 0;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus uahResCtlRequestBypass(
            const urcc::UrccRequestParcel& request) override {
        (void)acquire(request, true);
        return ndk::ScopedAStatus::ok();
    }

private:
    int32_t acquire(const urcc::UrccRequestParcel& request, bool one_way) {
#ifdef K90_OPAQUE_URCC_REQUEST
        (void)request;
        const HintSelection selected{0x1081, 1, 3000, "uah-generic"};
        const int64_t vendor_handle = hint_ ?
                hint_(0, selected.id, selected.type, selected.duration_ms,
                      "coloros-uah") : 0;
        const int32_t handle = next_handle_.fetch_add(1);
        // Opaque ColorOS requests are always translated to a bounded 3-second
        // UniPerf hint. UniPerf expires these handles itself. Keeping them in
        // handles_ made late client releases call UniperfRelease on an already
        // expired handle and allowed unreleased ColorOS handles to accumulate.
        (void)one_way;
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "request handle=%d vendor=%lld id=0x%x type=%d "
                            "dur=%d reason=%s opaque=1 auto-expire=1",
                            handle, static_cast<long long>(vendor_handle),
                            selected.id, selected.type, selected.duration_ms,
                            selected.reason);
        return vendor_handle > 0 ? handle : -1;
#else
        const HintSelection selected = select_hint(request);
        const std::string package = request.pkgName.empty() ?
                request.identity : request.pkgName;
        const int64_t vendor_handle = hint_ ?
                hint_(0, selected.id, selected.type, selected.duration_ms,
                      package.empty() ? "unknown" : package.c_str()) : 0;
        const int32_t handle = next_handle_.fetch_add(1);
        if (!one_way && vendor_handle > 0) {
            std::lock_guard<std::mutex> guard(lock_);
            handles_[handle] = vendor_handle;
        }
        __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                            "request handle=%d vendor=%lld id=0x%x type=%d dur=%d "
                            "reason=%s identity=%s pkg=%s resources=%zu",
                            handle, static_cast<long long>(vendor_handle),
                            selected.id, selected.type, selected.duration_ms,
                            selected.reason, request.identity.c_str(),
                            request.pkgName.c_str(),
                            request.mUrccRequestData.size());
        return vendor_handle > 0 ? handle : -1;
#endif
    }

    void* library_ = nullptr;
    HintFn hint_ = nullptr;
    ReleaseFn release_ = nullptr;
    std::mutex lock_;
    std::unordered_map<int32_t, int64_t> handles_;
    std::atomic<int32_t> next_handle_{1};
};

}  // namespace

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(4);
    ABinderProcess_startThreadPool();
    std::shared_ptr<K90Urcc> service = ndk::SharedRefBase::make<K90Urcc>();
    const std::string instance =
            std::string(urcc::IUrcc::descriptor) + "/default";
    const binder_status_t status =
            AServiceManager_addService(service->asBinder().get(), instance.c_str());
    if (status != STATUS_OK) {
        __android_log_print(ANDROID_LOG_FATAL, "K90Urcc",
                            "registration failed status=%d", status);
        return 1;
    }
    __android_log_print(ANDROID_LOG_INFO, "K90Urcc",
                        "registered %s", instance.c_str());
    ABinderProcess_joinThreadPool();
    return 0;
}
