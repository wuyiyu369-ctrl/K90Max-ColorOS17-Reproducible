#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage33_native_build
inputs=/root/k90_stage33_merge/images
product_base="$inputs/product31.img"
odm_base="$inputs/odm31.img"
aod_apk=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage33_aod_overlay/dist/K90MaxAodNativeOverlay.apk
charge_root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/build_v1747
product_size=152326144
odm_size=1724530688
product_uuid=29e54278-57e6-5163-a8c7-a9585e142b84
odm_uuid=576c9ac6-61bb-5f15-bf93-63b0e7accd12

[[ "$work" == /root/k90_stage33_native_build ]]
for file in "$product_base" "$odm_base" "$aod_apk"; do
  test -f "$file"
done
for file in \
  "$charge_root/script/charge_daemon.sh" \
  "$charge_root/script/charge_ctl.sh" \
  "$charge_root/bin/vendor.oplus.hardware.charger-V11-service"; do
  test -f "$file"
done
test "$(stat -c%s "$product_base")" -eq "$product_size"
test "$(stat -c%s "$odm_base")" -eq "$odm_size"
test "$(blkid -o value -s UUID "$product_base")" = "$product_uuid"
test "$(blkid -o value -s UUID "$odm_base")" = "$odm_uuid"

cleanup() {
  for part in product odm; do
    mountpoint -q "$work/$part/merged" && umount "$work/$part/merged" || true
    mountpoint -q "$work/$part/lower" && umount "$work/$part/lower" || true
    mountpoint -q "$work/verify_$part" && umount "$work/verify_$part" || true
  done
}
trap cleanup EXIT
cleanup
rm -rf -- "$work"
mkdir -p "$work"/{product,odm}/{lower,upper,overlay_work,merged} "$work"/{out,logs,verify_product,verify_odm}

# mkfs.erofs serializes the overlay upper root as the rebuilt partition root.
# Preserve the partition root labels explicitly; losing either label prevents
# init from reaching Android userspace (the Stage33 early-boot failure).
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/product/upper"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$work/odm/upper"

prepare_overlay() {
  local part=$1
  local image=$2
  local root="$work/$part"
  mount -t erofs -o ro,loop "$image" "$root/lower"
  mount -t overlay overlay -o "lowerdir=$root/lower,upperdir=$root/upper,workdir=$root/overlay_work" "$root/merged"
}

prepare_overlay product "$product_base"
prepare_overlay odm "$odm_base"

# A distinct package name avoids collision with the vendor overlay that owns
# Prague's power_profile resource.
install -o 0 -g 0 -m 0644 "$aod_apk" \
  "$work/product/merged/overlay/K90MaxAodNativeOverlay.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$work/product/upper/overlay/K90MaxAodNativeOverlay.apk"
touch -d '2026-11-05 12:30:00 UTC' \
  "$work/product/upper/overlay/K90MaxAodNativeOverlay.apk"

# Persist the user-requested native defaults without KSU, LSPosed, an APK, or
# a resident daemon. These one-shot commands run only after Android completed
# booting, when SettingsProvider and PackageManager are available.
product_rc_rel=etc/init/k90-native-settings.rc
product_rc="$work/product/merged/$product_rc_rel"
install -d -o 0 -g 0 -m 0755 "$(dirname "$product_rc")"
cat > "$product_rc" <<'EOF'
on property:sys.boot_completed=1
    exec_background -- /system/bin/settings put global oplus_battery_agent_debug_force_entry 1
    exec_background -- /system/bin/settings put global stay_on_while_plugged_in 0
    exec_background -- /system/bin/settings delete system brightness_drag_point
    exec_background -- /system/bin/settings delete system screen_auto_brightness_adj
    exec_background -- /system/bin/pm enable --user 0 com.android.camera/com.android.camera.OneShotImageCapture
    exec_background -- /system/bin/pm disable --user 0 com.android.camera/com.xiaomi.camera.IntentImageCapture
EOF
chown 0:0 "$product_rc"
chmod 0644 "$product_rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$work/product/upper/$product_rc_rel"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$work/product/upper/etc/init"
touch -d '2026-11-05 12:30:00 UTC' "$work/product/upper/$product_rc_rel"

# Native charging integration.  This is deliberately post-boot and fail-open:
# it exposes the already tested telemetry/AI-battery entry and starts the
# charger bridge only after Android is fully up.  The bridge/daemon retain
# Xiaomi JEITA, PD-authentication, connector-temperature and current limits;
# no boot-critical service or permanent thermal bypass is introduced.
charge_bin_rel=bin/vendor.oplus.hardware.charger-V11-service
charge_daemon_rel=bin/k90-charge-daemon.sh
charge_ctl_rel=bin/k90-charge-ctl.sh
charge_conf_rel=etc/k90/charge-scheduler.conf
charge_launcher_rel=bin/k90-native-charge-launcher.sh
charge_bin="$work/product/merged/$charge_bin_rel"
charge_daemon="$work/product/merged/$charge_daemon_rel"
charge_ctl="$work/product/merged/$charge_ctl_rel"
charge_conf="$work/product/merged/$charge_conf_rel"
charge_launcher="$work/product/merged/$charge_launcher_rel"
install -d -o 0 -g 0 -m 0755 "$(dirname "$charge_bin")" "$(dirname "$charge_conf")"
install -o 0 -g 0 -m 0755 "$charge_root/bin/vendor.oplus.hardware.charger-V11-service" "$charge_bin"
install -o 0 -g 0 -m 0755 "$charge_root/script/charge_daemon.sh" "$charge_daemon"
install -o 0 -g 0 -m 0755 "$charge_root/script/charge_ctl.sh" "$charge_ctl"
cat > "$charge_conf" <<'EOF'
# Native K90 defaults.  Aggressive is bounded by the daemon's hardware checks.
ENABLE=1
MODE=aggressive
SCHEDULE=0
START_TIME=00:00
END_TIME=23:59
HYSTERESIS=2
POLL_SEC=5
EOF
cat > "$charge_launcher" <<'EOF'
#!/system/bin/sh
# Fail-open native charging launcher.  It never runs before boot completion.
sleep 15
service list 2>/dev/null | grep -q 'vendor.xiaomi.hardware.micharge.IMiCharge/default:' || exit 0
mkdir -p /data/adb/k90max 2>/dev/null
if [ ! -f /data/adb/k90max/charge-scheduler.conf ]; then
  cp /product/etc/k90/charge-scheduler.conf /data/adb/k90max/charge-scheduler.conf 2>/dev/null
fi
/product/bin/vendor.oplus.hardware.charger-V11-service >/data/local/tmp/k90-icharger.log 2>&1 &
sleep 5
/system/bin/sh /product/bin/k90-charge-daemon.sh >/data/local/tmp/k90-charge-daemon.log 2>&1 &
exit 0
EOF
chmod 0755 "$charge_launcher"
chown 0:0 "$charge_conf"
chmod 0644 "$charge_conf"
for f in "$charge_bin" "$charge_daemon" "$charge_ctl" "$charge_launcher"; do
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$f"
done
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/product/upper/bin"
# install -d above copies /product/bin into the upper layer and otherwise
# changes the stock 0751 root:shell directory to 0755 root:root.  Restore the
# exact Stage31 directory metadata; changing this parent is an early-boot risk.
chown 0:2000 "$work/product/upper/bin"
chmod 0751 "$work/product/upper/bin"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/product/upper/etc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/product/upper/etc/k90"

# A separate post-boot launcher keeps charger failures out of the boot path.
# It uses the module's delayed start rule and starts the telemetry daemon only
# if the vendor Xiaomi MiCharge service is present.
charge_rc_rel=etc/init/k90-native-charge.rc
charge_rc="$work/product/merged/$charge_rc_rel"
cat > "$charge_rc" <<'EOF'
on property:sys.boot_completed=1
    exec_background -- /system/bin/sh /product/bin/k90-native-charge-launcher.sh
EOF
chown 0:0 "$charge_rc"
chmod 0644 "$charge_rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$charge_rc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/product/upper/etc/init"
touch -d '2026-11-05 14:00:00 UTC' "$charge_rc" "$charge_bin" "$charge_daemon" "$charge_ctl" "$charge_conf"

rc_rel=etc/init/k90-power-permissions.rc
rc_upper="$work/odm/upper/$rc_rel"
mkdir -p "$(dirname "$rc_upper")"
# mkdir -p creates fresh upper-layer parents without the labels carried by the
# Stage31 EROFS tree.  init traverses both directories while importing ODM rc
# files, so preserve their stock vendor_configs_file metadata explicitly.
chown 0:0 "$work/odm/upper/etc" "$work/odm/upper/etc/init"
chmod 0755 "$work/odm/upper/etc" "$work/odm/upper/etc/init"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$work/odm/upper/etc" "$work/odm/upper/etc/init"
cp -a "$work/odm/lower/$rc_rel" "$rc_upper"
if ! grep -q 'init.svc.vendor.mtkpower-service.mediatek=running' "$rc_upper"; then
  printf '%s\n' \
    '' \
    'on property:init.svc.vendor.mtkpower-service.mediatek=running' \
    '    chown system system /proc/powerhal_cpu_ctrl/perfserv_freq' \
    '    chmod 0660 /proc/powerhal_cpu_ctrl/perfserv_freq' >> "$rc_upper"
fi
chown 0:0 "$rc_upper"
chmod 0644 "$rc_upper"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$rc_upper"
touch -d '2026-11-05 12:30:00 UTC' "$rc_upper"

build_erofs() {
  local part=$1
  local uuid=$2
  local epoch=$3
  local extent_size=$4
  local tree="$work/$part/merged"
  local raw="$work/out/$part.raw.img" out="$work/out/$part.img"
  mkfs.erofs -z lz4hc,12 -C 65536 -T "$epoch" -U "$uuid" --preserve-mtime \
    "$raw" "$tree" > "$work/logs/mkfs-$part.log" 2>&1
  test "$(stat -c%s "$raw")" -le "$extent_size"
  cp --sparse=always "$raw" "$out"
  truncate -s "$extent_size" "$out"
  fsck.erofs "$out" > "$work/logs/fsck-$part.log" 2>&1
  test "$(blkid -o value -s UUID "$out")" = "$uuid"
}

build_erofs product "$product_uuid" 1791305925 "$product_size"
build_erofs odm "$odm_uuid" 1791306550 "$odm_size"

umount "$work/product/merged"
umount "$work/product/lower"
umount "$work/odm/merged"
umount "$work/odm/lower"
mount -t erofs -o ro,loop "$work/out/product.img" "$work/verify_product"
mount -t erofs -o ro,loop "$work/out/odm.img" "$work/verify_odm"

test "$(getfattr -n security.selinux --only-values "$work/verify_product" 2>/dev/null)" = \
  u:object_r:system_file:s0
test "$(getfattr -n security.selinux --only-values "$work/verify_odm" 2>/dev/null)" = \
  u:object_r:vendor_file:s0

test "$(sha256sum "$work/verify_product/overlay/K90MaxAodNativeOverlay.apk" | cut -d' ' -f1)" = \
  "$(sha256sum "$aod_apk" | cut -d' ' -f1)"
test "$(getfattr -n security.selinux --only-values "$work/verify_product/overlay/K90MaxAodNativeOverlay.apk" 2>/dev/null)" = \
  u:object_r:system_file:s0
grep -q 'oplus_battery_agent_debug_force_entry 1' \
  "$work/verify_product/$product_rc_rel"
grep -q 'OneShotImageCapture' "$work/verify_product/$product_rc_rel"
test "$(getfattr -n security.selinux --only-values "$work/verify_product/$product_rc_rel" 2>/dev/null)" = \
  u:object_r:system_file:s0
grep -q 'on property:init.svc.vendor.mtkpower-service.mediatek=running' \
  "$work/verify_odm/$rc_rel"
test "$(getfattr -n security.selinux --only-values "$work/verify_odm/$rc_rel" 2>/dev/null)" = \
  u:object_r:vendor_configs_file:s0
test "$(stat -c '%a:%u:%g' "$work/verify_product/bin")" = 751:0:2000
test "$(getfattr -n security.selinux --only-values "$work/verify_odm/etc" 2>/dev/null)" = \
  u:object_r:vendor_configs_file:s0
test "$(getfattr -n security.selinux --only-values "$work/verify_odm/etc/init" 2>/dev/null)" = \
  u:object_r:vendor_configs_file:s0
grep -q 'oplus_battery_agent_debug_force_entry 1' \
  "$work/verify_product/$product_rc_rel"
test -x "$work/verify_product/$charge_bin_rel"
test -x "$work/verify_product/$charge_daemon_rel"
test -x "$work/verify_product/$charge_ctl_rel"
test -x "$work/verify_product/$charge_launcher_rel"
grep -q '^MODE=aggressive$' "$work/verify_product/$charge_conf_rel"
grep -q 'vendor.xiaomi.hardware.micharge.IMiCharge/default' \
  "$work/verify_product/$charge_launcher_rel"

sha256sum "$work/out/product.img" "$work/out/odm.img" "$aod_apk" \
  > "$work/out/SHA256SUMS.txt"
echo STAGE33_NATIVE_PARTITIONS_OK
