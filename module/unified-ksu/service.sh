#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/vendor/k90max/module_state
LOG="$STATE/service.log"
mkdir -p "$STATE"
printf '%s\n' k90max_game_system_fix > "$STATE/.owner"
chown -R system:system "$STATE" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }
write_state(){ printf '%s\n' "$2" > "$STATE/$1" 2>/dev/null; }

# SettingsProvider is not guaranteed to be usable merely because
# sys.boot_completed is set. Never preserve an error string as a user's
# original value: that caused later brightness/game-exit restores to write
# garbage. Wait for the settings service, and validate every backup.
settings_ready=0
i=0
while [ "$i" -lt 180 ]; do
  if settings get system screen_brightness >/dev/null 2>&1; then
    settings_ready=1
    break
  fi
  sleep 1
  i=$((i + 1))
done

valid_setting(){
  value="$1"
  case "$value" in
    ''|null|*Failure*|*Error*|*Exception*|*transaction*) return 1 ;;
  esac
  return 0
}

save_original(){
  key="$1"
  file="$2"
  namespace="$3"
  [ -f "$file" ] && valid_setting "$(cat "$file" 2>/dev/null)" && return 0
  [ "$settings_ready" = 1 ] || return 0
  value="$(settings get "$namespace" "$key" 2>/dev/null)"
  if valid_setting "$value"; then
    printf '%s\n' "$value" > "$file"
  else
    rm -f "$file"
    log "settings backup skipped $namespace/$key value=$(printf '%s' "$value" | tr '\n' ' ')"
  fi
}

i=0
while [ "$i" -lt 180 ] && [ "$(getprop sys.boot_completed)" != 1 ]; do
  sleep 1; i=$((i + 1))
done
[ "$(getprop ro.boot.product.hardware.sku)" = prague ] || exit 0
[ "$(getprop ro.board.platform)" = mt6993 ] || exit 0

# The ROM bridge was shipped with an unnecessarily tight shell polling loop.
# Its immediate launch hint is already delivered by UAH/URCC, so the native
# thermal-table observer can use a lower-overhead interval.
# Keep this in vendor data rather than mounting or modifying ODM.
PERF_CONF=/data/vendor/k90max/perf.conf
PERF_MARK='# managed-by-k90max-game-system-fix'
if [ ! -e "$PERF_CONF" ] || grep -qF "$PERF_MARK" "$PERF_CONF" 2>/dev/null; then
  mkdir -p /data/vendor/k90max 2>/dev/null
  {
    echo "$PERF_MARK"
    # A short balanced launch scene plus task-profile placement hides launch
    # latency without keeping normal apps in the widest game table.
    # The shell observer itself used measurable CPU at a two-second interval.
    # Daily foreground responsiveness is now handled by settaskprofile, so the
    # native bridge can poll less often and use a balanced launch table.
    echo 'POLL_SEC=4'
    echo 'LAUNCH_BOOST_SEC=1'
    echo 'LAUNCH_SCENE=18'
    # Keep the phone unrestricted through normal game temperatures.  At 48C
    # return control to Xiaomi's vendor-auto thermal table; never disable the
    # hardware safety path.
    echo 'SAFE_TEMP_HARD=48000'
    echo 'SAFE_TEMP_COOL=44000'
  } > "$PERF_CONF" 2>/dev/null
  chown system:system "$PERF_CONF" 2>/dev/null
  chmod 0600 "$PERF_CONF" 2>/dev/null
  restorecon "$PERF_CONF" >/dev/null 2>&1
  log "ROM performance polling configured interval=4s launch=18/1s hard=48C"
else
  log "ROM performance polling preserved user-owned perf.conf"
fi

# The native bridge starts before this late-start module and logs its compiled
# defaults on the first boot loop.  It re-reads perf.conf while running, but a
# one-time init restart makes the intended 4s/balanced-launch/48C policy authoritative
# immediately and clears any launch scene inherited from the boot animation.
if [ "$(getprop init.svc.k90-performance-bridge)" = "running" ]; then
  setprop ctl.restart k90-performance-bridge 2>/dev/null
  sleep 2
  log "ROM performance bridge restarted after managed perf.conf"
fi

# Do not leave stale process identifiers or an old "running" status after a
# reboot. The final bridge start below replaces these values atomically.
rm -f "$STATE/bridge_pid"
write_state bridge_status exited

# Save only once. Files live in the module-owned vendor-data state directory.
save_original peak_refresh_rate "$STATE/orig_peak" system
save_original min_refresh_rate "$STATE/orig_min" system
save_original game_speed_up_switch "$STATE/orig_game_speed" global
save_original wifi_on "$STATE/orig_wifi" global
save_original mobile_data "$STATE/orig_mobile" global
save_original haptic_feedback_enabled "$STATE/orig_haptic" system
save_original haptic_feedback_intensity "$STATE/orig_haptic_intensity" system
save_original screen_auto_brightness_adj "$STATE/orig_auto_brightness_adj" system
save_original gesture_side_back_vibrate_enable "$STATE/orig_side_haptic" secure
save_original adaptive_sleep "$STATE/orig_adaptive_sleep" secure
save_original oplus_customize_smart_screen_off "$STATE/orig_smart_screen_off" secure
save_original setting_enable_color_temperature_regulation "$STATE/orig_ambient_color" system
save_original oplus_customize_antidizzy_enable "$STATE/orig_antidizzy_enable" secure
save_original oplus_customize_antidizzy_force_off "$STATE/orig_antidizzy_force_off" secure
save_original oplus_customize_antidizzy_mode "$STATE/orig_antidizzy_mode" secure
save_original oplus_fingerprint_quick_launch_switch "$STATE/orig_fp_quick_launch" secure
save_original quick_launch_switch_when_fingerprint_is_turned_off "$STATE/orig_fp_quick_launch_off" secure

# Xiaomi touch mode 14 is double-tap-to-wake. ColorOS settings alone do not
# notify this HAL on the port.
settings put secure wake_gesture_enabled 1 2>/dev/null
settings put secure double_tap_to_wake 1 2>/dev/null
settings put system oplus_screen_off_gesture_state 1 2>/dev/null
service call vendor.xiaomi.hw.touchfeature.ITouchFeature/default 9 i32 0 i32 14 i32 1 >/dev/null 2>&1

# Preserve the real Xiaomi vibrator HAL; only enable ColorOS feedback paths.
settings put system haptic_feedback_enabled 1 2>/dev/null
settings put secure gesture_side_back_vibrate_enable 1 2>/dev/null
settings put system input_method_key_vibration 1 2>/dev/null
settings put system haptic_feedback_intensity 2 2>/dev/null

# Android's public auto-brightness adjustment is a normalized float in
# [-1.0, 1.0]. This port can accidentally store the raw slider/backlight value
# (for example 3475.0) in the same key. OplusAutomaticBrightnessController then
# treats it as a huge user preference and keeps the panel far too bright even
# when the ALS path itself is alive. Repair only impossible/out-of-range values;
# preserve legitimate user learning and never continuously force brightness.
auto_adj="$(settings get system screen_auto_brightness_adj 2>/dev/null)"
if valid_setting "$auto_adj"; then
  if awk -v v="$auto_adj" 'BEGIN { exit !((v + 0) > 1.0 || (v + 0) < -1.0) }' 2>/dev/null; then
    settings put system screen_auto_brightness_adj 0.0 >/dev/null 2>&1
    cmd display reset-brightness-configuration >/dev/null 2>&1
    log "auto-brightness repaired invalid_adjustment=$auto_adj new=0.0"
  else
    log "auto-brightness preserved adjustment=$auto_adj"
  fi
fi

# PMB110's stock curve reaches roughly 25% brightness at only 128 lux, while
# K90 Max's tcs3720 reports much higher indoor lux values. Apply one mild
# baseline offset on first install/upgrade, then leave Android's user-learning
# path fully authoritative. Never overwrite a value the user has already
# adjusted and never poll or force panel brightness.
AUTO_CAL_MARK="$STATE/auto_brightness_curve_calibrated_v2"
auto_mode="$(settings get system screen_brightness_mode 2>/dev/null)"
auto_adj="$(settings get system screen_auto_brightness_adj 2>/dev/null)"
if [ "$auto_mode" = 1 ] && [ ! -f "$AUTO_CAL_MARK" ]; then
  case "$auto_adj" in
    0|0.0|0.00|0.000)
      cmd display reset-brightness-configuration >/dev/null 2>&1
      settings put system screen_auto_brightness_adj -0.18 >/dev/null 2>&1
      printf '%s\n' '-0.18' > "$AUTO_CAL_MARK"
      log "auto-brightness baseline calibrated sensor=tcs3720 offset=-0.18 owner=android-learning"
      ;;
    -0.18|-0.180|-0.1800)
      printf '%s\n' '-0.18' > "$AUTO_CAL_MARK"
      log "auto-brightness baseline marker adopted existing_adjustment=-0.18"
      ;;
    *)
      log "auto-brightness baseline skipped existing_adjustment=$auto_adj"
      ;;
  esac
fi

# Stage80+ already contains the native ColorOS -> MTK PQ bridge in
# OplusFeatureColorMode.  Runtime evidence shows logical 10 maps to MTK 0 and
# logical 12 maps to MTK 6, followed by a real PQ parameter reload.  Do not
# start a second KSU color writer: it would race the system_server observer.
log "color owner=ROM OplusFeatureColorMode -> MTK PQ; module writer disabled"

# These are the exact keys consumed by ColorOS 17. The attention service is
# present on this build; enabling both avoids the Settings UI and framework
# disagreeing about "keep screen on while looking".
settings put secure adaptive_sleep 1 2>/dev/null
settings put secure oplus_customize_smart_screen_off 1 2>/dev/null

# Environment color adaptation is observed by OplusFeatureColorMode. Do not
# hard-code a CCT or RGB value; the real ALS/color sensor remains authoritative.
settings put system setting_enable_color_temperature_regulation 1 2>/dev/null

# Motion-cue rendering is implemented by OplusFeatureAntiDizzy on this build.
# Keep the real accelerometer/gyro path; these keys only enable its consumer.
settings put secure oplus_customize_antidizzy_force_off 0 2>/dev/null
settings put secure oplus_customize_antidizzy_mode 2 2>/dev/null
settings put secure oplus_customize_antidizzy_enable 1 2>/dev/null

# Keep ColorOS fingerprint quick launch enabled. The Xiaomi HAL still reports
# vendor acquired codes that ColorOS may not translate; this does not fake a
# touch-down event and is intentionally limited to the supported settings path.
settings put secure oplus_fingerprint_quick_launch_switch 1 2>/dev/null
settings put secure quick_launch_switch_when_fingerprint_is_turned_off 1 2>/dev/null

# Leave swappiness and page-cluster at the vendor values. Forcing swappiness
# from 100 to zero is a substantial global memory-policy change and is not part
# of the verified foreground performance fix.

log "boot wait=${i}s peak=$(cat "$STATE/orig_peak") min=$(cat "$STATE/orig_min")"

# Airplane-mode enforcement. Remember the states at the transition and restore
# them when airplane mode exits. No state is written outside this module.
(
  last_air=-1
  while :; do
    air="$(settings get global airplane_mode_on 2>/dev/null)"
    if [ "$air" != "$last_air" ]; then
      if [ "$air" = 1 ]; then
        settings get global wifi_on > "$STATE/air_wifi"
        settings get global mobile_data > "$STATE/air_mobile"
        svc data disable >/dev/null 2>&1
        svc wifi disable >/dev/null 2>&1
        cmd connectivity airplane-mode enable >/dev/null 2>&1
        log "airplane enforce: data=off wifi=off"
      elif [ "$last_air" = 1 ]; then
        [ "$(cat "$STATE/air_mobile" 2>/dev/null)" = 1 ] && svc data enable >/dev/null 2>&1
        [ "$(cat "$STATE/air_wifi" 2>/dev/null)" = 1 ] && svc wifi enable >/dev/null 2>&1
        log "airplane exit: restored previous radios"
      fi
      last_air="$air"
    elif [ "$air" = 1 ]; then
      # Guard against the broken vendor stack bringing data back by itself.
      svc data disable >/dev/null 2>&1
      svc wifi disable >/dev/null 2>&1
    fi
    sleep 5
  done
) &

# Fast-charge request. This never bypasses JEITA, charger authentication,
# connector temperature, current, voltage or battery protection. Above 80%
# or 42C it immediately returns fastcharge_mode to 0.
(
  while :; do
    online="$(cat /sys/class/power_supply/usb/online 2>/dev/null)"
    cap="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
    temp="$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
    auth="$(cat /sys/class/power_supply/usb/pd_authentication 2>/dev/null)"
    qct="$(cat /sys/class/power_supply/usb/quick_charge_type 2>/dev/null)"
    case "$cap:$temp:$qct" in *[!0-9:]*) safe=0 ;; *) safe=1 ;; esac
    enable=0
    if [ "$online" = 1 ] && [ "$safe" = 1 ] && [ "$cap" -lt 80 ] && [ "$temp" -lt 420 ]; then
      if [ "$auth" = 1 ]; then
        enable=1
      elif [ -n "$qct" ] && [ "$qct" -gt 0 ] 2>/dev/null; then
        enable=1
      fi
    fi
    for node in /sys/class/power_supply/bms/fastcharge_mode /sys/class/power_supply/battery/fastcharge_mode; do
      [ -w "$node" ] && echo "$enable" > "$node" 2>/dev/null
    done
    sleep 5
  done
) &

# Re-assert touch mode after framework restarts, without restarting services.
(
  while :; do
    sleep 120
    [ "$(settings get secure double_tap_to_wake 2>/dev/null)" = 1 ] && \
      service call vendor.xiaomi.hw.touchfeature.ITouchFeature/default 9 i32 0 i32 14 i32 1 >/dev/null 2>&1
  done
) &

bridge="$MODDIR/bin/perf_bridge"
if [ -f "$bridge" ]; then
  chmod 0755 "$bridge" 2>/dev/null
  # The bridge itself is the durable supervisor. If this shell was killed
  # during the long SettingsProvider wait, an already-running bridge remains
  # authoritative instead of being duplicated by a second service launch.
  old_pid="$(cat "$STATE/bridge_pid" 2>/dev/null)"
  case "$old_pid" in
    ''|*[!0-9]*) old_pid="" ;;
  esac
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null && \
      grep -q 'perf_bridge' "/proc/$old_pid/cmdline" 2>/dev/null; then
    log "perf bridge already alive pid=$old_pid"
    exit 0
  fi
  nohup sh "$bridge" >> "$LOG" 2>&1 &
  bridge_pid=$!
  sleep 1
  if kill -0 "$bridge_pid" 2>/dev/null; then
    echo "$bridge_pid" > "$STATE/bridge_pid"
    if [ -f /odm/bin/k90_perf_bridge.sh ] && \
       [ "$(getprop init.svc.k90-performance-bridge)" = "running" ]; then
      write_state bridge_status hybrid-native-sconfig
      log "perf display helper alive pid=$bridge_pid; sconfig owner=rom-native"
    else
      write_state bridge_status running
      log "perf bridge alive pid=$bridge_pid path=$bridge"
    fi
  else
    rm -f "$STATE/bridge_pid"
    write_state bridge_status exited
    log "perf bridge failed to stay alive pid=$bridge_pid path=$bridge"
  fi
else
  rm -f "$STATE/bridge_pid"
  write_state bridge_status missing
  log "perf bridge missing: $bridge"
fi
