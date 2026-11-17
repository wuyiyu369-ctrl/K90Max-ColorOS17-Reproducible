#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <android/log.h>
#include <pthread.h>

/* These stable NDK entry points are exported by libbinder_ndk but the NDK
 * sysroot does not ship binder_manager.h/binder_process.h. */
extern binder_status_t AServiceManager_addService(AIBinder *binder,
                                                   const char *instance);
extern void ABinderProcess_setThreadPoolMaxThreadCount(uint32_t numThreads);
extern void ABinderProcess_startThreadPool(void);
extern void ABinderProcess_joinThreadPool(void);
extern void AIBinder_markVintfStability(AIBinder *binder);
#endif

static int raw_to_pwm(int raw) {
    if (raw <= 0) return 0;
    /*
     * ColorOS/Ace fan UI exposes eight discrete levels.  The old bridge
     * incorrectly treated the value as a 0..20 scale, so the UI's maximum
     * value (8) only produced PWM 40.  Keep this table explicit so that UI
     * levels, Binder readback and the Xiaomi driver's 0..99 duty scale cannot
     * silently drift apart.
     */
    static const int pwm_by_level[] = { 0, 12, 25, 37, 50, 62, 74, 87, 99 };
    if (raw >= 8) return 99;
    return pwm_by_level[raw];
}

static int effective_pwm(int main_switch, int raw) {
    return main_switch == 1 ? raw_to_pwm(raw) : 0;
}

static int self_test(void) {
    if (raw_to_pwm(-8) != 0) return 1;
    if (raw_to_pwm(0) != 0) return 2;
    if (raw_to_pwm(1) != 12) return 3;
    if (raw_to_pwm(2) != 25) return 4;
    if (raw_to_pwm(3) != 37) return 5;
    if (raw_to_pwm(4) != 50) return 6;
    if (raw_to_pwm(5) != 62) return 7;
    if (raw_to_pwm(6) != 74) return 8;
    if (raw_to_pwm(7) != 87) return 9;
    if (raw_to_pwm(8) != 99) return 10;
    if (raw_to_pwm(99) != 99) return 11;
    if (effective_pwm(0, 8) != 0) return 12;
    if (effective_pwm(1, 8) != 99) return 13;
    puts("misc fan mapping self-test passed (13 cases)");
    return 0;
}

#ifdef __ANDROID__
static const char *fan_root = "/sys/devices/platform/odm/odm:xiaomi_fan/";
static const char *heartbeat = "/data/vendor/k90max/misc_fan_active";

enum {
    NODE_FAN_SWITCH = 0x191,
    NODE_FAN_SPEED = 0x193,
    NODE_FAN_BATCH = 0x194,
    NODE_FAN_SELF_CHECK = 0x195,
};

typedef struct {
    pthread_mutex_t lock;
    int main_switch;
    int raw_speed;
} FanState;

static FanState state = { PTHREAD_MUTEX_INITIALIZER, 0, 0 };

static void log_result(const char *operation, int node, int value, int result) {
    __android_log_print(result == 0 ? ANDROID_LOG_INFO : ANDROID_LOG_ERROR,
                        "K90MiscFan", "%s node=0x%x value=%d result=%d errno=%d",
                        operation, node, value, result, result ? errno : 0);
}

static int write_node(const char *name, int value) {
    char path[256];
    char text[24];
    snprintf(path, sizeof(path), "%s%s", fan_root, name);
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    int length = snprintf(text, sizeof(text), "%d", value);
    ssize_t done = write(fd, text, (size_t)length);
    int saved = errno;
    close(fd);
    errno = saved;
    return done == length ? 0 : -1;
}

static int apply_locked(void) {
    int pwm = effective_pwm(state.main_switch, state.raw_speed);
    if (write_node("target_level", 0) || write_node("pwm_duty", pwm)) {
        log_result("apply-failed", NODE_FAN_SPEED, pwm, -1);
        return 1;
    }
    log_result("apply", NODE_FAN_SPEED, pwm, 0);
    return 0;
}

static void *heartbeat_thread(void *unused) {
    (void)unused;
    for (;;) {
        int fd = open(heartbeat, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0640);
        if (fd >= 0) {
            char text[32];
            int length = snprintf(text, sizeof(text), "%lld\n", (long long)time(NULL));
            (void)write(fd, text, (size_t)length);
            close(fd);
        }
        sleep(1);
    }
    return NULL;
}

static bool read_string_alloc(void *opaque, int32_t length, char **buffer) {
    char **result = opaque;
    if (length < 0) {
        *result = NULL;
        *buffer = NULL;
        return true;
    }
    *result = calloc((size_t)length, 1);
    *buffer = *result;
    return *buffer != NULL;
}

static binder_status_t write_status(AParcel *out) {
    AStatus *status = AStatus_newOk();
    if (!status) return STATUS_NO_MEMORY;
    binder_status_t result = AParcel_writeStatusHeader(out, status);
    AStatus_delete(status);
    return result;
}

static binder_status_t reply_int(AParcel *out, int32_t value) {
    binder_status_t result = write_status(out);
    return result == STATUS_OK ? AParcel_writeInt32(out, value) : result;
}

static binder_status_t reply_bool(AParcel *out, bool value) {
    binder_status_t result = write_status(out);
    return result == STATUS_OK ? AParcel_writeBool(out, value) : result;
}

static binder_status_t reply_string(AParcel *out, const char *value) {
    binder_status_t result = write_status(out);
    if (result != STATUS_OK) return result;
    return AParcel_writeString(out, value, value ? (int32_t)strlen(value) : -1);
}

static void *on_create(void *args) { return args; }
static void on_destroy(void *user_data) { (void)user_data; }

static binder_status_t on_transact(AIBinder *binder, transaction_code_t code,
                                   const AParcel *in, AParcel *out) {
    (void)binder;
    int32_t device = 0, node = 0;
    binder_status_t result;

    switch (code) {
        case 1: /* initialize */
            return reply_int(out, 0);
        case 2: /* isMiscNodeSupport */
            if ((result = AParcel_readInt32(in, &device)) != STATUS_OK) return result;
            if ((result = AParcel_readInt32(in, &node)) != STATUS_OK) return result;
            (void)device;
            return reply_int(out, node == NODE_FAN_SWITCH || node == NODE_FAN_SPEED ||
                                      node == NODE_FAN_BATCH || node == NODE_FAN_SELF_CHECK
                                      ? 0 : 1);
        case 3: { /* miscReadNodeFile */
            char text[32];
            if ((result = AParcel_readInt32(in, &device)) != STATUS_OK) return result;
            if ((result = AParcel_readInt32(in, &node)) != STATUS_OK) return result;
            (void)device;
            pthread_mutex_lock(&state.lock);
            int value = node == NODE_FAN_SWITCH ? state.main_switch :
                        node == NODE_FAN_SPEED ? state.raw_speed : 0;
            pthread_mutex_unlock(&state.lock);
            snprintf(text, sizeof(text), "%d", value);
            return reply_string(out, text);
        }
        case 4: { /* miscWriteNodeFile */
            char *text = NULL;
            if ((result = AParcel_readInt32(in, &device)) != STATUS_OK) return result;
            if ((result = AParcel_readInt32(in, &node)) != STATUS_OK) return result;
            if ((result = AParcel_readString(in, &text, read_string_alloc)) != STATUS_OK)
                return result;
            (void)device;
            char *end = NULL;
            errno = 0;
            long parsed = text ? strtol(text, &end, 10) : 0;
            if (!text || errno || end == text || *end || parsed < -1000 || parsed > 1000) {
                free(text);
                return reply_int(out, 1);
            }
            pthread_mutex_lock(&state.lock);
            if (node == NODE_FAN_SWITCH) {
                state.main_switch = parsed == 1 ? 1 : 0;
                result = apply_locked();
            } else if (node == NODE_FAN_SPEED) {
                state.raw_speed = parsed < 0 ? 0 : parsed > 8 ? 8 : (int)parsed;
                result = apply_locked();
            } else if (node == NODE_FAN_BATCH || node == NODE_FAN_SELF_CHECK) {
                result = 0;
            } else {
                result = 1;
            }
            pthread_mutex_unlock(&state.lock);
            log_result("write", node, (int)parsed, result);
            free(text);
            return reply_int(out, result == 0 ? 0 : 1);
        }
        case 5: /* saveCalibrationData: unsupported, consume-free response */
            return reply_bool(out, false);
        case 0xfffffe:
            return reply_string(out, "a899a863d8a7e0b5ed35ced2275f2ba68aaad329");
        case 0xffffff:
            return reply_int(out, 1);
        default:
            return STATUS_UNKNOWN_TRANSACTION;
    }
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    mkdir("/data/vendor/k90max", 0770);
    pthread_t heartbeat_tid;
    if (pthread_create(&heartbeat_tid, NULL, heartbeat_thread, NULL) != 0) return 2;
    pthread_detach(heartbeat_tid);

    AIBinder_Class *clazz = AIBinder_Class_define(
            "vendor.oplus.hardware.misc.IOplusMisc", on_create, on_destroy, on_transact);
    if (!clazz) return 3;
    AIBinder *binder = AIBinder_new(clazz, &state);
    if (!binder) return 4;
    AIBinder_markVintfStability(binder);
    ABinderProcess_setThreadPoolMaxThreadCount(4);
    ABinderProcess_startThreadPool();
    binder_status_t status = AServiceManager_addService(
            binder, "vendor.oplus.hardware.misc.IOplusMisc/default");
    if (status != STATUS_OK) {
        __android_log_print(ANDROID_LOG_ERROR, "K90MiscFan",
                            "service registration failed: %d", status);
        AIBinder_decStrong(binder);
        return 5;
    }
    __android_log_print(ANDROID_LOG_INFO, "K90MiscFan", "service registered");
    ABinderProcess_joinThreadPool();
    AIBinder_decStrong(binder);
    unlink(heartbeat);
    return 0;
}
#else
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    fprintf(stderr, "host build only supports --self-test\n");
    return 64;
}
#endif
