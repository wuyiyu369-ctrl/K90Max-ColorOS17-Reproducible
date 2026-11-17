#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifdef __ANDROID__
#include <android/log.h>
#endif

/* C ABI checked against Prague libuniperf_client_vendor.so disassembly:
 * x0=int64 handle, w1=hint, w2=type, w3=duration, x4=const char*.
 * The library supplies pid/tid and allocates its own handle. Do not synthesize
 * Binder transactions or resource codes. Timed hints expire in the vendor HAL.
 */
typedef int64_t (*hint_fn)(int64_t, int, int, int, const char *);
typedef void (*release_fn)(int64_t);
static volatile sig_atomic_t running = 1;
static const char *tm = "/sys/class/thermal/thermal_message/";
static const char *fan = "/sys/devices/platform/odm/odm:xiaomi_fan/";
static void stop(int s) { (void)s; running = 0; }
static void log_line(const char *what, const char *pkg, long long value);

static int read_text(const char *base, const char *name, char *out, size_t n) {
    char path[512]; snprintf(path, sizeof(path), "%s%s", base, name);
    FILE *f = fopen(path, "re");
    if (!f) { *out = 0; return -1; }
    size_t got = fread(out, 1, n - 1, f); fclose(f); out[got] = 0;
    while (got && (out[got-1] == '\n' || out[got-1] == '\r')) out[--got] = 0;
    return got ? 0 : -1;
}
static int read_path(const char *path, char *out, size_t n) {
    FILE *f = fopen(path, "re");
    if (!f) { *out = 0; return -1; }
    size_t got = fread(out, 1, n - 1, f); fclose(f); out[got] = 0;
    while (got && (out[got-1] == '\n' || out[got-1] == '\r')) out[--got] = 0;
    return got ? 0 : -1;
}
static int number(const char *base, const char *name, int fallback) {
    char b[64], *end;
    if (read_text(base, name, b, sizeof(b))) return fallback;
    errno = 0; long v = strtol(b, &end, 10);
    if (errno || end == b || *end || v < -1000000 || v > 100000000) return fallback;
    return (int)v;
}
static void log_line(const char *what, const char *pkg, long long value);

static int write_num(const char *base, const char *name, int value) {
    char path[512], b[24]; snprintf(path, sizeof(path), "%s%s", base, name);
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        int e = errno; log_line("fan-node-open-failed", name, e);
        errno = e;
        return -1;
    }
    int n = snprintf(b, sizeof(b), "%d", value);
    ssize_t done = write(fd, b, n); int e = errno; close(fd); errno = e;
    if (done != n) log_line("fan-node-write-failed", name, e);
    return done == n ? 0 : -1;
}
static int misc_fan_service_active(void) {
    struct stat st;
    if (stat("/data/vendor/k90max/misc_fan_active", &st)) return 0;
    time_t now = time(NULL);
    return now >= st.st_mtime && now - st.st_mtime <= 3;
}
static int game_profile(const char *pkg) {
    FILE *f = fopen("/odm/etc/performance/game_profiles", "re");
    if (!f) return 0;
    char line[512]; int result = 0; size_t best = 0;
    while (fgets(line, sizeof(line), f)) {
        char *comment = strchr(line, '#'); if (comment) *comment = 0;
        char clean[512]; size_t j = 0;
        for (size_t i = 0; line[i] && j < sizeof(clean)-1; ++i)
            if (line[i] != ' ' && line[i] != '\t' && line[i] != '\r' && line[i] != '\n') clean[j++] = line[i];
        clean[j] = 0; char *eq = strchr(clean, '='); if (!eq) continue;
        *eq++ = 0; size_t len = strlen(clean); if (!len) continue;
        int wildcard = clean[len-1] == '*'; if (wildcard) clean[--len] = 0;
        if ((wildcard ? !strncmp(pkg, clean, len) : !strcmp(pkg, clean)) && len >= best) {
            result = atoi(eq); best = wildcard ? len : 100000;
        }
    }
    fclose(f); return result;
}
static int is_game(int scene) { return scene == 6 || scene == 18 || scene == 19 || scene == 20 || scene == 25; }
static int fan_level_duty(int level) {
    static const int level_to_duty[] = { 12, 25, 37, 50, 62, 74, 87, 99 };
    if (level >= 1 && level <= 8) return level_to_duty[level - 1];
    if (level <= 0) return 0;
    return level > 99 ? 99 : level;
}
static int fan_duty(int main, int mode, int custom, int game_switch, int charge_switch,
                    int gaming, int charging, int capacity, int awake, int temp) {
    if (main != 1) return 0;
    /* Explicit user modes must not be silently disabled because a vendor
     * sensor or screen-state node is missing or temporarily unreadable. */
    if (mode == 3) return fan_level_duty(custom);
    if (mode == 2) return 99;
    if (mode == 1) return 30;
    if (temp < 0 || temp > 100000) return 0;
    if (!awake && (!charging || capacity >= 100)) return 0;
    /* Smart mode: full charge stops the charge branch; active gaming remains. */
    if (gaming && game_switch) {
        return temp >= 52000 ? 90 : temp >= 47000 ? 70 : temp >= 42000 ? 50 : temp >= 37000 ? 30 : 0;
    }
    if (charging && capacity >= 0 && capacity < 100 && charge_switch)
        return temp >= 47000 ? 60 : temp >= 43000 ? 40 : temp >= 38000 ? 25 : 0;
    return 0;
}
static void log_line(const char *what, const char *pkg, long long value) {
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "K90NativeBridge", "%s pkg=%s result=%lld", what, pkg, value);
#endif
    FILE *f = fopen("/data/vendor/k90max/stage44_native.log", "ae");
    if (f && ftell(f) > 262144) { fclose(f); f = fopen("/data/vendor/k90max/stage44_native.log", "we"); }
    if (f) { fprintf(f, "%lld %s pkg=%s result=%lld\n", (long long)time(NULL), what, pkg, value); fclose(f); }
}
static void perf_snapshot(const char *pkg, int temp, long long handle) {
    char scene[32] = "?", c0[32] = "?", c4[32] = "?", c7[32] = "?";
    char m0[32] = "?", m4[32] = "?", m7[32] = "?", report[512];
    (void)read_text(tm, "sconfig", scene, sizeof(scene));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq", c0, sizeof(c0));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq", c4, sizeof(c4));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq", c7, sizeof(c7));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq", m0, sizeof(m0));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq", m4, sizeof(m4));
    (void)read_path("/sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq", m7, sizeof(m7));
    snprintf(report, sizeof(report),
             "fg=%s scene=%s cpu=p0:%s/%s,p4:%s/%s,p7:%s/%s temp=%d",
             pkg && *pkg ? pkg : "none", scene, c0, m0, c4, m4, c7, m7, temp);
    log_line("perf-status", report, handle);
}
static int self_test(void) {
    if (fan_duty(0,2,0,1,1,1,0,100,1,42000) != 0) return 1;
    if (fan_duty(1,0,30,1,1,0,1,100,1,44000) != 0) return 2;
    if (fan_duty(1,0,30,1,1,1,1,100,1,44000) != 50) return 3;
    if (fan_duty(1,3,200,0,0,0,0,50,1,40000) != 99) return 4;
    if (fan_duty(1,0,30,1,1,1,0,50,0,40000) != 0) return 5;
    if (fan_duty(1,0,30,1,1,0,1,50,0,44000) != 40) return 6;
    if (fan_duty(1,2,30,1,1,1,0,50,1,-1) != 99) return 7;
    if (fan_duty(1,2,30,1,1,1,0,50,0,-1) != 99) return 8;
    if (fan_duty(1,3,99,1,1,1,0,50,0,-1) != 99) return 9;
    if (fan_duty(1,3,1,1,1,0,0,50,1,-1) != 12) return 10;
    if (fan_duty(1,3,2,1,1,0,0,50,1,-1) != 25) return 11;
    if (fan_duty(1,3,7,1,1,0,0,50,1,-1) != 87) return 12;
    if (fan_duty(1,3,8,1,1,0,0,50,1,-1) != 99) return 13;
    puts("fan policy self-test passed (13 cases)"); return 0;
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    signal(SIGTERM, stop); signal(SIGINT, stop);
    void *lib = dlopen("/vendor/lib64/libuniperf_client_vendor.so", RTLD_NOW | RTLD_LOCAL);
    hint_fn hint = lib ? (hint_fn)dlsym(lib, "UniperfHint") : NULL;
    release_fn release = lib ? (release_fn)dlsym(lib, "UniperfRelease") : NULL;
    log_line(hint ? "uniperf-loaded" : "uniperf-unavailable", "", 0);
    int64_t handle = 0; int applied = -1, tick = 0;
    char previous[256] = "", pkg[256], screen[64], settings[160], status[32];
    while (running) {
        read_text(tm, "foreground_app_name", pkg, sizeof(pkg));
        read_text(tm, "screen_state", screen, sizeof(screen));
        int awake = !strcmp(screen,"1") || !strcmp(screen,"on") || !strcmp(screen,"ON") || !strcmp(screen,"Awake") || !strcmp(screen,"awake");
        int temp = number(tm, "board_sensor_temp", -1);
        int gaming = is_game(game_profile(pkg));
        if (!awake) { previous[0] = 0; if (handle > 0 && release) release(handle); handle = 0; }
        else if (strcmp(pkg, previous)) {
            if (handle > 0 && release) release(handle);
            handle = 0;
            /* Xiaomi mappings: 0x1081/type1=MTK21 5s; type4=MTK54 5s.
             * No boost at invalid/hot sensor readings; vendor thermal still wins.
             */
            if (*pkg && hint && temp >= 0 && temp < 45000) {
                handle = hint(0, 0x1081, gaming ? 4 : 1, 5000, pkg);
                log_line("launch-hint", pkg, handle);
            } else if (*pkg) log_line("launch-no-hint-temperature-or-service", pkg, temp);
            snprintf(previous, sizeof(previous), "%s", pkg);
            perf_snapshot(pkg, temp, handle);
        }
        if ((tick % 120) == 0) perf_snapshot(pkg, temp, handle);
        if ((tick++ % 8) == 0 && !misc_fan_service_active()) {
            int main = 0, mode = 0, custom = 30, game = 0, charge = 0, mic = 0;
            int valid_request = 0;
            int request_rc = read_text("/data/system/", "k90fan.request", settings, sizeof(settings));
            if (!request_rc) {
                /* Accept the older five-field mailbox and the six-field
                 * mailbox.  The later one is not a compatibility failure:
                 * a bridge must keep controlling the fan while system_server
                 * and ODM are upgraded independently. */
                int fields = sscanf(settings,"[%d, %d, %d, %d, %d, %d]",
                                     &main,&mode,&custom,&game,&charge,&mic);
                if (fields < 5) fields = sscanf(settings,"[%d, %d, %d, %d, %d]",
                                                &main,&mode,&custom,&game,&charge);
                if (fields == 5 || fields == 6) valid_request = 1;
                if (fields == 5) mic = 0;
                log_line(valid_request ? "fan-request-read" : "fan-request-invalid",
                         settings, fields);
            } else {
                log_line("fan-request-open-failed", "/data/system/k90fan.request", errno);
            }
            if (!valid_request && applied < 0) {
                struct timespec pause = {0, 250000000}; nanosleep(&pause, NULL); continue;
            }
            if (!valid_request) main = 0;
            /* Microphone mutual exclusion is a hardware-safe override. It is
             * kept separate from the mode because it must work even in manual
             * and custom modes. */
            if (mic == 1) main = 0;
            read_text("/sys/class/power_supply/battery/", "status", status, sizeof(status));
            int charging = !strcmp(status,"Charging") || !strcmp(status,"Full");
            int capacity = number("/sys/class/power_supply/battery/", "capacity", -1);
            int desired = fan_duty(main,mode,custom,game,charge,gaming,charging,capacity,awake,temp);
            long long request_hash = (long long)(main * 1000000000LL + mode * 10000000LL +
                                                custom * 10000LL + game * 100LL +
                                                charge * 10LL + mic);
            static long long logged_request = -1;
            if (request_hash != logged_request) {
                log_line("fan-request-applied", settings, request_hash);
                logged_request = request_hash;
            }
            if (desired != applied || number(fan, "pwm_duty", -1) != desired) {
                if (!write_num(fan, "target_level", 0) && !write_num(fan, "pwm_duty", desired)
                    && number(fan,"pwm_duty",-1) == desired) {
                    applied = desired; log_line("fan-applied", pkg, desired);
                    log_line("fan-speed-readback", pkg, number(fan,"real_speed",-1));
                } else {
                    log_line("fan-write-failed", pkg, errno);
                }
            }
        }
        struct timespec pause = {0, 250000000}; nanosleep(&pause, NULL);
    }
    if (handle > 0 && release) release(handle);
    if (applied >= 0) { write_num(fan,"target_level",0); write_num(fan,"pwm_duty",0); }
    if (lib) dlclose(lib);
    return 0;
}
