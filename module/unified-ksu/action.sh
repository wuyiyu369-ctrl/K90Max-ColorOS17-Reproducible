#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/vendor/k90max/module_state
echo "=== Legacy module compatibility ==="
if [ -s "$MODDIR/compat/disabled_by_upgrade" ]; then
  echo "Conflicting modules disabled by this update:"
  sed 's/^/- /' "$MODDIR/compat/disabled_by_upgrade"
else
  echo "No conflicting legacy module was migrated"
fi
echo
echo "=== Performance backend ownership ==="
echo "ROM bridge: $(getprop init.svc.k90-performance-bridge) pid=$(getprop init.svc_debug_pid.k90-performance-bridge)"
if [ -f /odm/bin/k90_perf_bridge.sh ]; then
  echo "sconfig owner: ROM native bridge (module does not start a second writer)"
else
  echo "sconfig owner: module fallback bridge"
fi
echo
echo "===== K90 Max 游戏与系统桥 ====="
echo "设备: $(getprop ro.boot.product.hardware.sku) / $(getprop ro.board.platform)"
echo "性能桥: $(cat "$STATE/bridge_status" 2>/dev/null || echo missing)"
bridge_pid="$(cat "$STATE/bridge_pid" 2>/dev/null)"
if [ "$(cat "$STATE/bridge_status" 2>/dev/null)" = hybrid-native-sconfig ]; then
  echo "性能桥进程: ROM 管 CPU/GPU 场景，模块管刷新率/触控"
elif [ -n "$bridge_pid" ] && kill -0 "$bridge_pid" 2>/dev/null; then
  echo "性能桥进程: PID=$bridge_pid（存活）"
else
  echo "性能桥进程: 没有存活进程（状态文件不能单独作为成功证据）"
fi
echo "桥文件: $MODDIR/bin/perf_bridge"
echo "ODM 原生桥: $(ls /odm/bin/k90_perf_bridge.sh 2>/dev/null || echo unavailable)"
echo "模块版本: $(grep '^version=' "$MODDIR/module.prop" | cut -d= -f2-)"
echo "刷新率设置: peak=$(settings get system peak_refresh_rate) min=$(settings get system min_refresh_rate)"
echo "刷新率策略: $(cat "$STATE/refresh_profile" 2>/dev/null || echo unavailable)（日常 60-120，游戏 120）"
echo "当前显示模式:"
dumpsys display 2>/dev/null | grep -m1 -E 'mActiveModeId|renderFrameRate'
echo "触控上报档位: $(cat "$STATE/touch_rate" 2>/dev/null) (游戏=240，日常=120)"
echo "动态策略: $(cat "$STATE/policy_profile" 2>/dev/null) (game/daily/thermal)"
echo "性能场景: $(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null)"
echo "任务调度通道: /system/bin/settaskprofile（不直接写 cgroup，不关闭 SELinux）"
echo "当前调度记录: $(tail -1 "$STATE/perf.log" 2>/dev/null || echo unavailable)"
echo "CPU上限: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null)/$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2>/dev/null)/$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq 2>/dev/null)"
gpu_raw="$(cat /sys/kernel/ged/hal/current_freqency 2>/dev/null)"
gpu_khz="$(printf '%s\n' "$gpu_raw" | awk '{ if (NF >= 2) print $2; else print $1 }')"
echo "GPU频率: ${gpu_khz:-unavailable} kHz (GED原始值: ${gpu_raw:-unavailable})"
echo "DDR频率: $(cat /sys/class/devfreq/mtk-dvfsrc-devfreq/cur_freq 2>/dev/null)"
echo "OPPO性能服务: IPerformance=$(service check vendor.oplus.hardware.performance.IPerformance/default 2>/dev/null) IUrcc=$(service check vendor.oplus.hardware.urcc.IUrcc/default 2>/dev/null)"
echo "温度: $(cat /sys/class/thermal/thermal_message/board_sensor_temp 2>/dev/null) mC"
echo "飞行模式: $(settings get global airplane_mode_on)"
echo "双击亮屏: $(settings get secure double_tap_to_wake)"
echo "侧滑震动: $(settings get secure gesture_side_back_vibrate_enable)"
echo "注视不熄屏: adaptive_sleep=$(settings get secure adaptive_sleep) smart_screen_off=$(settings get secure oplus_customize_smart_screen_off)"
echo "自动亮度: $(settings get system screen_brightness_mode) (1=开，0=关)"
echo "当前亮度: $(settings get system screen_brightness)"
echo "自动亮度偏移: $(settings get system screen_auto_brightness_adj)（正常范围 -1.0～1.0）"
echo "自动亮度配置: ROM 原文件 + 一次性 K90 光感基线校准（不覆盖系统分区）"
echo "亮度配置 SHA-256: $(sha256sum /system_ext/etc/display_brightness_config_common.xml 2>/dev/null | awk '{print $1}')"
if grep -qE '/data/adb/(modules|metamodule)|KSU' /proc/1/mountinfo 2>/dev/null; then
  echo "分区覆盖检查: 警告，检测到第三方模块挂载（不一定来自本模块）"
else
  echo "分区覆盖检查: 无 KernelSU/metamodule 分区挂载"
fi
echo "实时环境光/目标/实际背光:"
dumpsys display 2>/dev/null | grep -E -m4 'realTimeLux=|finalLux=|mFinalLux=|Display Brightness=' | sed 's/^[[:space:]]*/  /'
echo "环境色自适应: $(settings get system setting_enable_color_temperature_regulation)"
echo "晕动舒缓: enable=$(settings get secure oplus_customize_antidizzy_enable) force_off=$(settings get secure oplus_customize_antidizzy_force_off) mode=$(settings get secure oplus_customize_antidizzy_mode)"
echo "指纹快启: $(settings get secure oplus_fingerprint_quick_launch_switch)"
echo "生物识别传感器:"
dumpsys biometric 2>/dev/null | grep -E 'ID\(|CurrentSession' | sed 's/^[[:space:]]*/  /'
echo "指纹加密认证计数:"
dumpsys fingerprint 2>/dev/null | grep -m1 'acceptCrypto' | sed 's/^[[:space:]]*/  /'
echo "指纹服务: $(getprop init.svc.vendor.fingerprint-default 2>/dev/null || echo unavailable)"
echo "设备名称: model=$(getprop ro.product.model) market=$(getprop ro.product.marketname)"
echo "定位模式: $(settings get secure location_mode)"
echo "最近定位质量:"
dumpsys location 2>/dev/null | grep -m1 -E 'last location=Location\[(gps|network)' | sed 's/^[[:space:]]*/  /'
echo "色彩模式: secure=$(settings get secure oplus_customize_color_mode) system=$(settings get system oplus_last_color_mode)"
echo "SurfaceFlinger色彩空间: $(dumpsys SurfaceFlinger 2>/dev/null | grep -im1 'current color mode:' | sed 's/^[[:space:]]*//')"
echo "ColorOS色彩控制器: $(dumpsys color_display 2>/dev/null | grep -m1 'colorMode=' | sed 's/^[[:space:]]*//')"
echo "MTK PQ最近映射: $(logcat -d -t 400 -s OplusFeatureColorMode 2>/dev/null | grep 'K90 color logical=' | tail -1 | sed 's/^[[:space:]]*//')"
echo "色彩写入者: ROM system_server（模块不启动第二个PQ写入器）"
echo "物理分辨率: $(wm size | sed -n 's/Physical size: //p')"
echo "Swap: $(grep -E '^Swap(Total|Free)' /proc/meminfo | tr '\n' ' ')"
echo "AI 后端: $(ls /odm/lib64/libaiboost.so 2>/dev/null && echo present || echo unavailable)"
echo "查找手机安全后端: $(service check vendor.oplus.hardware.cryptoeng.ICryptoeng/default 2>/dev/null || echo unavailable)"
echo "Android安全硬件: keymint=$(service check android.hardware.security.keymint.IKeyMintDevice/default 2>/dev/null) strongbox=$(service check android.hardware.security.keymint.IKeyMintDevice/strongbox 2>/dev/null) eSE=$(service check android.hardware.secure_element.ISecureElement/eSE1 2>/dev/null)"
echo "--- 设置备份校验 ---"
for f in orig_peak orig_min orig_game_speed orig_ambient_color; do
  value="$(cat "$STATE/$f" 2>/dev/null)"
  case "$value" in
    ''|*Failure*|*Error*|*Exception*|*transaction*) echo "$f=INVALID($value)" ;;
    *) echo "$f=${value:-unset}" ;;
  esac
done
echo "--- 最近服务日志 ---"
tail -20 "$STATE/service.log" 2>/dev/null
echo "--- 最近性能日志 ---"
if [ -f /data/vendor/k90max/stage37_perf.log ]; then
  tail -20 /data/vendor/k90max/stage37_perf.log 2>/dev/null
else
  tail -20 "$STATE/perf.log" 2>/dev/null
fi
echo "说明: 当前 ColorOS 策略把 165/144 请求夹到 120Hz；模块使用实测可达的 120Hz。"
echo "说明: 指纹快启若仍不弹出，需要框架映射小米 HAL 的触摸事件，设置开关本身不能伪造触摸。"
echo "说明: 支付软件未调用加密指纹时，需要复现错误码；本模块不绕过应用安全校验或伪造 TEE。"
echo "说明: 钱包/查找手机需要本机 MiTEE/KeyMint/eSE 到 OPPO CryptoEng 的原生协议桥，纯脚本不能伪造。"
