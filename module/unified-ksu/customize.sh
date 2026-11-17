#!/system/bin/sh
# Keep the distributed module script/property-only. A systemless partition
# overlay adds a detectable mount layer and is outside this module's safety
# contract; framework fixes must use a separately reviewed implementation.
SKIPMOUNT=true
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# KernelSU variants do not all materialize SKIPMOUNT into the module marker.
# Create it explicitly so this module can never become a partition overlay.
touch "$MODPATH/skip_mount" || abort "! Cannot create skip_mount safety marker"

# Validate the target before touching compatibility markers on other modules.
early_sku="$(getprop ro.boot.product.hardware.sku)"
early_platform="$(getprop ro.board.platform)"
if [ "$early_sku" != "prague" ] || [ "$early_platform" != "mt6993" ]; then
  abort "! Unsupported device: ${early_sku:-unknown}/${early_platform:-unknown}; expected prague/mt6993"
fi

# The standard KernelSU/Magisk installer removes MODPATH before extracting this
# ZIP, so same-id updates cannot retain files omitted by the new release.
# Older releases with different ids are preserved but disabled when they write
# the same runtime controls as this unified module.
COMPAT_DIR="$MODPATH/compat"
COMPAT_RECORD="$COMPAT_DIR/disabled_by_upgrade"
mkdir -p "$COMPAT_DIR"
: > "$COMPAT_RECORD"

disable_conflicting_module(){
  old_id="$1"
  old_path="/data/adb/modules/$old_id"
  update_path="/data/adb/modules_update/$old_id"

  if [ -d "$old_path" ]; then
    if [ ! -e "$old_path/disable" ] && [ ! -e "$old_path/remove" ]; then
      touch "$old_path/disable" || abort "! Cannot disable conflicting module: $old_id"
      echo "$old_id" >> "$COMPAT_RECORD"
      ui_print "- Disabled conflicting old module: $old_id"
    else
      ui_print "- Old module already disabled: $old_id"
    fi
  fi

  if [ -d "$update_path" ] && [ ! -e "$update_path/disable" ]; then
    touch "$update_path/disable" || abort "! Cannot disable queued conflicting module: $old_id"
  fi
}

for conflict_id in \
  k90max_fix_ksu \
  k90max_radio_registration_fix \
  Eclipse \
  extreme_gt \
  scene_resurgence \
  Device_Guise; do
  disable_conflicting_module "$conflict_id"
done

if [ ! -s "$COMPAT_RECORD" ]; then
  rm -f "$COMPAT_RECORD"
fi

# Some Windows-based module packers stored binary and config names with a
# literal backslash instead of a directory separator. Repair that layout before
# validating/installing it; otherwise service.sh can install successfully and
# still be unable to launch the performance bridge.
for legacy_name in 'bin\perf_bridge' 'config\game_profiles' 'config\thermal_safe'; do
  legacy_path="$MODPATH/$legacy_name"
  [ -f "$legacy_path" ] || continue
  dir_name="${legacy_name%%\\*}"
  file_name="${legacy_name#*\\}"
  mkdir -p "$MODPATH/$dir_name"
  mv -f "$legacy_path" "$MODPATH/$dir_name/$file_name"
done

sku="$(getprop ro.boot.product.hardware.sku)"
platform="$(getprop ro.board.platform)"
if [ "$sku" != "prague" ] || [ "$platform" != "mt6993" ]; then
  abort "! 设备不匹配：仅支持 K90 Max (prague/MT6993)，当前为 ${sku:-unknown}/${platform:-unknown}"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/uninstall.sh" "$MODPATH/bin/perf_bridge"; do
  [ -f "$f" ] || abort "! 模块文件缺失：${f#$MODPATH/}"
  set_perm "$f" 0 0 0755
done

ui_print "- 设备校验通过：prague / MT6993"
ui_print "- 性能：检测到 ROM 原生桥时由其独占 sconfig，模块不启动第二个写入器"
ui_print "- 调度：使用系统 settaskprofile 和前台主线程 nice，不直写 cgroup、不关闭 SELinux"
ui_print "- 显示：保留用户刷新率设置；状态页区分 ColorOS 逻辑模式与物理模式"
ui_print "- 自动亮度：首次对 K90 光感做 -0.18 温和校准，之后交还系统自学习"
ui_print "- 触控：同步双击亮屏到 Xiaomi TouchFeature；不替换触控 HAL"
ui_print "- 网络：飞行模式开启时强制关闭蜂窝数据和 Wi-Fi"
ui_print "- 充电：只在低温、低电量且协议已认证时请求 fastcharge_mode，不伪造瓦数"
ui_print "- 震动：恢复系统触感与侧滑返回反馈，不替换振动 HAL"
ui_print "- 晕动舒缓：启用 ColorOS 原生 AntiDizzy 与真实加速度计/陀螺仪链路"
ui_print "- 指纹快启：保持原生入口和开关；不伪造厂商触摸事件"
ui_print "- 定位：记录 GNSS/NLP 状态，不覆盖其他设备的校准或 AGPS 配置"
ui_print "- 色彩：沿用 ROM 已验证的 OplusFeatureColorMode -> MTK PQ 原生桥，模块不重复写入"
ui_print "- 虚拟内存：保留已工作的 Xiaomi zram；不强启冲突的 ColorOS NAND swap"
ui_print "- 未伪装修复：钱包/查找 CryptoEng 仍需镜像级原生协议桥"
ui_print "- 状态/日志只保存在模块目录，不写 /data/local/tmp 或 /sdcard"
ui_print "- 安装后请重启；在管理器点“操作”查看状态"
