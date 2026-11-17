/*
 * SPDX-FileCopyrightText: 2025 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include "stage64_performance.h"

#include <android-base/logging.h>

extern "C" binder_status_t AServiceManager_addService(
        AIBinder* binder, const char* instance);
extern "C" void ABinderProcess_setThreadPoolMaxThreadCount(uint32_t num_threads);
extern "C" void ABinderProcess_joinThreadPool();

using ::aidl::vendor::oplus::hardware::performance::Performance;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    std::shared_ptr<Performance> performance = ndk::SharedRefBase::make<Performance>();

    const std::string instance = std::string() + Performance::descriptor + "/default";
    binder_status_t status =
            AServiceManager_addService(performance->asBinder().get(), instance.c_str());
    CHECK_EQ(status, STATUS_OK);

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // should not reach
}
