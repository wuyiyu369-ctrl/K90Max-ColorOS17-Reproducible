#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/vendor/k90max/module_state

# Re-enable only modules disabled by this installer. Anything disabled before
# installation was not recorded and remains untouched.
COMPAT_RECORD="$MODDIR/compat/disabled_by_upgrade"
if [ -f "$COMPAT_RECORD" ]; then
  while IFS= read -r old_id; do
    case "$old_id" in
      k90max_fix_ksu|k90max_radio_registration_fix|Eclipse|extreme_gt|scene_resurgence|Device_Guise)
        rm -f "/data/adb/modules/$old_id/disable" \
              "/data/adb/modules_update/$old_id/disable" 2>/dev/null
        ;;
    esac
  done < "$COMPAT_RECORD"
fi
peak="$(cat "$STATE/orig_peak" 2>/dev/null)"
min="$(cat "$STATE/orig_min" 2>/dev/null)"
game_speed="$(cat "$STATE/orig_game_speed" 2>/dev/null)"
haptic="$(cat "$STATE/orig_haptic" 2>/dev/null)"
haptic_intensity="$(cat "$STATE/orig_haptic_intensity" 2>/dev/null)"
auto_brightness_adj="$(cat "$STATE/orig_auto_brightness_adj" 2>/dev/null)"
side="$(cat "$STATE/orig_side_haptic" 2>/dev/null)"
adaptive="$(cat "$STATE/orig_adaptive_sleep" 2>/dev/null)"
smart_off="$(cat "$STATE/orig_smart_screen_off" 2>/dev/null)"
ambient="$(cat "$STATE/orig_ambient_color" 2>/dev/null)"
antidizzy_enable="$(cat "$STATE/orig_antidizzy_enable" 2>/dev/null)"
antidizzy_force_off="$(cat "$STATE/orig_antidizzy_force_off" 2>/dev/null)"
antidizzy_mode="$(cat "$STATE/orig_antidizzy_mode" 2>/dev/null)"
fp_quick_launch="$(cat "$STATE/orig_fp_quick_launch" 2>/dev/null)"
fp_quick_launch_off="$(cat "$STATE/orig_fp_quick_launch_off" 2>/dev/null)"
[ -n "$peak" ] && [ "$peak" != null ] && settings put system peak_refresh_rate "$peak"
[ -n "$min" ] && [ "$min" != null ] && settings put system min_refresh_rate "$min"
[ -n "$game_speed" ] && [ "$game_speed" != null ] && settings put global game_speed_up_switch "$game_speed"
[ -n "$haptic" ] && [ "$haptic" != null ] && settings put system haptic_feedback_enabled "$haptic"
[ -n "$haptic_intensity" ] && [ "$haptic_intensity" != null ] && settings put system haptic_feedback_intensity "$haptic_intensity"
[ -n "$auto_brightness_adj" ] && [ "$auto_brightness_adj" != null ] && settings put system screen_auto_brightness_adj "$auto_brightness_adj"
[ -n "$side" ] && [ "$side" != null ] && settings put secure gesture_side_back_vibrate_enable "$side"
[ -n "$adaptive" ] && [ "$adaptive" != null ] && settings put secure adaptive_sleep "$adaptive"
[ -n "$smart_off" ] && [ "$smart_off" != null ] && settings put secure oplus_customize_smart_screen_off "$smart_off"
[ -n "$ambient" ] && [ "$ambient" != null ] && settings put system setting_enable_color_temperature_regulation "$ambient"
[ -n "$antidizzy_enable" ] && [ "$antidizzy_enable" != null ] && settings put secure oplus_customize_antidizzy_enable "$antidizzy_enable"
[ -n "$antidizzy_force_off" ] && [ "$antidizzy_force_off" != null ] && settings put secure oplus_customize_antidizzy_force_off "$antidizzy_force_off"
[ -n "$antidizzy_mode" ] && [ "$antidizzy_mode" != null ] && settings put secure oplus_customize_antidizzy_mode "$antidizzy_mode"
[ -n "$fp_quick_launch" ] && [ "$fp_quick_launch" != null ] && settings put secure oplus_fingerprint_quick_launch_switch "$fp_quick_launch"
[ -n "$fp_quick_launch_off" ] && [ "$fp_quick_launch_off" != null ] && settings put secure quick_launch_switch_when_fingerprint_is_turned_off "$fp_quick_launch_off"
if [ -w /sys/class/thermal/thermal_message/sconfig ]; then
  echo 0 > /sys/class/thermal/thermal_message/sconfig
  sleep 1
  echo -1 > /sys/class/thermal/thermal_message/sconfig
fi

for node in /sys/class/power_supply/bms/fastcharge_mode /sys/class/power_supply/battery/fastcharge_mode; do
  [ -w "$node" ] && echo 0 > "$node"
done

PERF_CONF=/data/vendor/k90max/perf.conf
if grep -qF '# managed-by-k90max-game-system-fix' "$PERF_CONF" 2>/dev/null; then
  rm -f "$PERF_CONF"
fi

VRR_TARGET=/data/system/oplus_vrr_config.json
VRR_MARKER=/data/system/.k90max_vrr_override
if [ -e "$VRR_MARKER" ]; then
  if [ "$(cat "$STATE/orig_oplus_vrr_present" 2>/dev/null)" = 1 ] &&
     [ -s "$STATE/orig_oplus_vrr_config.json" ]; then
    cp "$STATE/orig_oplus_vrr_config.json" "$VRR_TARGET" 2>/dev/null
    chown system:system "$VRR_TARGET" 2>/dev/null
    chmod 0600 "$VRR_TARGET" 2>/dev/null
    restorecon "$VRR_TARGET" >/dev/null 2>&1
  else
    rm -f "$VRR_TARGET"
  fi
  rm -f "$VRR_MARKER"
fi
service call vendor.xiaomi.hw.touchfeature.ITouchFeature/default \
  9 i32 0 i32 1011 i32 135 >/dev/null 2>&1
if [ "$(cat "$STATE/.owner" 2>/dev/null)" = k90max_game_system_fix ]; then
  rm -rf "$STATE"
fi
exit 0
