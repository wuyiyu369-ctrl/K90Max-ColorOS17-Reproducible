#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage40_fanperf_offline
src=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage36_native_integration
jar=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage40_services_patch/services.stage40.fanperf.jar
base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img
base_delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER
delivery=$work/delivery
avbtool=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

base_sha=42dec6dc5cfa8792bca04149c50e476e7f8d645d64b3fc0fc77f7b54dde2d703
super_size=13421772800
system_size=1061134336
system_original_size=1049554944
system_seek=256
system_count=259066
system_salt=e25ce9d868f66f3acadc4cd9388398d9
odm_size=1724530688
odm_seek=2615552
odm_count=421028

for tool in mkfs.erofs fsck.erofs dump.erofs getfattr setfattr secilc; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done
test -s "$jar"
test -s "$base"
test "$(stat -c%s "$base")" -eq "$super_size"
test "$(sha256sum "$base" | awk '{print $1}')" = "$base_sha"
test ! -e "$work"
test ! -e "$delivery"

mkdir -p "$work"/{out,system_lower,system_upper,system_work,system_merged,odm_lower,odm_upper,odm_work,odm_merged,verify_system,verify_odm,policy/{system,system_ext,product,vendor,odm}}

cleanup() {
  for mount_dir in \
    "$work/policy/odm" "$work/policy/vendor" "$work/policy/product" \
    "$work/policy/system_ext" "$work/policy/system" \
    "$work/verify_odm" "$work/verify_system" \
    "$work/odm_merged" "$work/odm_lower" \
    "$work/system_merged" "$work/system_lower"; do
    mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  done
}
trap cleanup EXIT

dd if="$base" of="$work/out/system.base.img" bs=4096 skip="$system_seek" count="$system_count" status=progress
dd if="$base" of="$work/out/odm.base.img" bs=4096 skip="$odm_seek" count="$odm_count" status=progress
test "$(stat -c%s "$work/out/system.base.img")" -eq "$system_size"
test "$(stat -c%s "$work/out/odm.base.img")" -eq "$odm_size"
fsck.erofs "$work/out/system.base.img" > "$work/out/fsck-system-base.log" 2>&1
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.log" 2>&1

# Rebuild system from the exact current Stage38 bytes and replace only the
# current-device services.jar. All existing SMS, camera and biometric patches
# in the other framework jars remain byte-identical.
mount -t erofs -o ro,loop "$work/out/system.base.img" "$work/system_lower"
setfattr -n security.selinux -v u:object_r:rootfs:s0 "$work/system_upper"
mount -t overlay overlay -o "lowerdir=$work/system_lower,upperdir=$work/system_upper,workdir=$work/system_work" "$work/system_merged"
install -m 0644 "$jar" "$work/system_merged/system/framework/services.jar"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/system_upper/system/framework/services.jar"

system_uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
system_label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
system_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$system_uuid" --preserve-mtime)
[[ -n "$system_label" ]] && system_args+=(-L "$system_label")
mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" "$work/system_merged" > "$work/out/mkfs-system.log" 2>&1
if (( $(stat -c%s "$work/out/system.raw.img") > system_original_size )); then
  rm -f "$work/out/system.raw.img"
  system_args=(-z lz4hc,12 -C 32768 -T 1791277125 -U "$system_uuid" --preserve-mtime)
  [[ -n "$system_label" ]] && system_args+=(-L "$system_label")
  mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" "$work/system_merged" > "$work/out/mkfs-system.log" 2>&1
fi
test "$(stat -c%s "$work/out/system.raw.img")" -le "$system_original_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_original_size" "$work/out/system.img"
python3 "$avbtool" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_size" --partition_name system --hash_algorithm sha256 \
  --salt "$system_salt" --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avbtool" verify_image --image "$work/out/system.img" > "$work/out/avb-system-verify.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.log" 2>&1
umount "$work/system_merged"
umount "$work/system_lower"

# Rebuild ODM from the exact Stage38 image. The fan daemon is deliberately not
# started; system_server owns settings observation and the two fan node writes.
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$work/odm_lower"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$work/odm_upper"
mount -t overlay overlay -o "lowerdir=$work/odm_lower,upperdir=$work/odm_upper,workdir=$work/odm_work" "$work/odm_merged"
install -m 0755 "$src/performance/perf_bridge.sh" "$work/odm_merged/bin/k90_perf_bridge.sh"
install -m 0644 "$src/performance/game_profiles" "$work/odm_merged/etc/performance/game_profiles"
install -m 0644 "$src/performance/thermal_safe" "$work/odm_merged/etc/performance/thermal_safe"
install -m 0644 "$src/native_services.rc" "$work/odm_merged/etc/init/k90-native-services.rc"
# The previous image labeled only the files.  Android 17 then left the
# intermediate directory as `unlabeled`, so vendor_touch_init_shell could not
# search /odm/etc/performance even though game_profiles itself was labeled.
mkdir -p "$work/odm_upper/etc/performance"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$work/odm_upper/etc/performance"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$work/odm_upper/bin/k90_perf_bridge.sh"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$work/odm_upper/etc/performance/game_profiles" \
  "$work/odm_upper/etc/performance/thermal_safe" \
  "$work/odm_upper/etc/init/k90-native-services.rc"

policy="$work/odm_merged/etc/selinux/odm_sepolicy.cil"
grep -q 'system_server_202504 sysfs_therm' "$policy" || \
  printf '\n(allow system_server_202504 sysfs_therm (file (write append)))\n' >> "$policy"
grep -q 'system_server_202504 vendor_sysfs_xm_power' "$policy" || \
  printf '(allow system_server_202504 vendor_sysfs_xm_power (file (write append)))\n' >> "$policy"
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 "$work/odm_upper/etc/selinux/odm_sepolicy.cil"

grep -q 'foreground_app_name' "$work/odm_merged/bin/k90_perf_bridge.sh"
! grep -q 'dumpsys' "$work/odm_merged/bin/k90_perf_bridge.sh"
! grep -q '^service k90-fan-bridge' "$work/odm_merged/etc/init/k90-native-services.rc"
! grep -q '^    user root$' "$work/odm_merged/etc/init/k90-native-services.rc"
! grep -q '^com.android.launcher=' "$work/odm_merged/etc/performance/game_profiles"

odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime)
[[ -n "$odm_label" ]] && odm_args+=(-L "$odm_label")
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" "$work/odm_merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.log" 2>&1
umount "$work/odm_merged"
umount "$work/odm_lower"

# Read-back checks for payload and SELinux xattrs.
mount -t erofs -o ro,loop "$work/out/system.img" "$work/verify_system"
test "$(getfattr -n security.selinux --only-values "$work/verify_system" 2>/dev/null)" = u:object_r:rootfs:s0
cmp -s "$jar" "$work/verify_system/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values "$work/verify_system/system/framework/services.jar" 2>/dev/null)" = u:object_r:system_file:s0
umount "$work/verify_system"

mount -t erofs -o ro,loop "$work/out/odm.img" "$work/verify_odm"
test "$(getfattr -n security.selinux --only-values "$work/verify_odm" 2>/dev/null)" = u:object_r:vendor_file:s0
cmp -s "$src/performance/perf_bridge.sh" "$work/verify_odm/bin/k90_perf_bridge.sh"
cmp -s "$src/native_services.rc" "$work/verify_odm/etc/init/k90-native-services.rc"
grep -q 'system_server_202504 vendor_sysfs_xm_power' "$work/verify_odm/etc/selinux/odm_sepolicy.cil"
test "$(getfattr -n security.selinux --only-values "$work/verify_odm/bin/k90_perf_bridge.sh" 2>/dev/null)" = u:object_r:vendor_touch_init_shell_exec:s0
umount "$work/verify_odm"

# Compile the complete split policy twice: current baseline and candidate.
# Strict diagnostics must not gain any new line. Runtime compatibility is also
# checked separately, but never used to waive strict neverallow diagnostics.
mount -t erofs -o ro,loop,offset=$((256*4096)),sizelimit=$system_size "$base" "$work/policy/system"
mount -t erofs -o ro,loop,offset=$((259328*4096)),sizelimit=1087639552 "$base" "$work/policy/system_ext"
mount -t erofs -o ro,loop,offset=$((525056*4096)),sizelimit=152326144 "$base" "$work/policy/product"
mount -t erofs -o ro,loop,offset=$((2000640*4096)),sizelimit=2517786624 "$base" "$work/policy/vendor"
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$work/policy/odm"

vers=$(cat "$work/policy/vendor/etc/selinux/plat_sepolicy_vers.txt")
inputs=(
  "$work/policy/system/system/etc/selinux/plat_sepolicy.cil"
  "$work/policy/system/system/etc/selinux/mapping/$vers.cil"
)
for candidate in \
  "$work/policy/system/system/etc/selinux/mapping/$vers.compat.cil" \
  "$work/policy/system/system/etc/selinux/plat_sepolicy_genfs_202504.cil" \
  "$work/policy/system_ext/system_ext/etc/selinux/system_ext_sepolicy.cil" \
  "$work/policy/system_ext/system_ext/etc/selinux/mapping/$vers.cil" \
  "$work/policy/product/product/etc/selinux/product_sepolicy.cil" \
  "$work/policy/product/product/etc/selinux/mapping/$vers.cil" \
  "$work/policy/vendor/etc/selinux/plat_pub_versioned.cil" \
  "$work/policy/vendor/etc/selinux/vendor_sepolicy.cil"; do
  [[ -f "$candidate" ]] && inputs+=("$candidate")
done

cp "$work/policy/odm/etc/selinux/odm_sepolicy.cil" "$work/out/odm-baseline.cil"
cp "$work/out/odm-baseline.cil" "$work/out/odm-candidate.cil"
grep -q 'system_server_202504 sysfs_therm' "$work/out/odm-candidate.cil" || \
  printf '\n(allow system_server_202504 sysfs_therm (file (write append)))\n' >> "$work/out/odm-candidate.cil"
grep -q 'system_server_202504 vendor_sysfs_xm_power' "$work/out/odm-candidate.cil" || \
  printf '(allow system_server_202504 vendor_sysfs_xm_power (file (write append)))\n' >> "$work/out/odm-candidate.cil"

set +e
secilc -m -M true -G -c 33 "${inputs[@]}" "$work/out/odm-baseline.cil" \
  -o "$work/out/policy-baseline.bin" -f /dev/null 2> "$work/out/secilc-baseline-strict.log"
baseline_status=$?
secilc -m -M true -G -c 33 "${inputs[@]}" "$work/out/odm-candidate.cil" \
  -o "$work/out/policy-candidate.bin" -f /dev/null 2> "$work/out/secilc-candidate-strict.log"
candidate_status=$?
set -e
test "$baseline_status" -eq "$candidate_status"
cmp -s "$work/out/secilc-baseline-strict.log" "$work/out/secilc-candidate-strict.log"

# Build final super by replacing only the fixed system and ODM extents.
mkdir -p "$delivery/images"
cp --sparse=always "$base" "$delivery/images/super.img.building"
dd if="$work/out/system.img" of="$delivery/images/super.img.building" bs=4096 seek="$system_seek" count="$system_count" conv=notrunc status=progress
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=4096 seek="$odm_seek" count="$odm_count" conv=notrunc,fsync status=progress
test "$(stat -c%s "$delivery/images/super.img.building")" -eq "$super_size"
mv "$delivery/images/super.img.building" "$delivery/images/super.img"

dd if="$delivery/images/super.img" of="$work/out/system.verify.img" bs=4096 skip="$system_seek" count="$system_count" status=none
dd if="$delivery/images/super.img" of="$work/out/odm.verify.img" bs=4096 skip="$odm_seek" count="$odm_count" status=none
cmp -s "$work/out/system.img" "$work/out/system.verify.img"
cmp -s "$work/out/odm.img" "$work/out/odm.verify.img"

cp "$base_delivery/FLASH_KEEP_DATA.ps1" "$delivery/"
cp "$base_delivery/START_UPDATE.cmd" "$delivery/" 2>/dev/null || true
cp -a "$base_delivery/platform-tools" "$delivery/"
sha256sum "$work/out/system.img" "$work/out/odm.img" "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"

cat > "$delivery/STATUS.txt" <<EOF
OFFLINE_CHECKS_PASSED
BASE_SHA256=$base_sha
STRICT_POLICY_BASELINE_STATUS=$baseline_status
STRICT_POLICY_CANDIDATE_STATUS=$candidate_status
DEVICE_BOOT_AND_FUNCTION_TESTS_NOT_YET_RUN
DO_NOT_DISTRIBUTE_BEFORE_LIVE_TEST
EOF

cat > "$delivery/CHANGES_STAGE40.txt" <<'EOF'
Stage40 offline candidate, no-root architecture:
1. system_server mirrors the real top-resumed package to Xiaomi's
   thermal_message/foreground_app_name.
2. ColorOS fan settings are observed by system_server and translated to the
   K90 fan nodes using the verified order target_level=0 then pwm_duty.
3. No k90 fan service runs as root. KSU and LSPosed are not dependencies.
4. The performance helper reads Xiaomi native nodes, does not call dumpsys,
   does not pin the launcher, and restores sconfig only after it owned a game
   scene. Xiaomi thermal safety remains enabled.

Offline checks do not prove boot, fan rotation, frequency behavior or power.
Close all modules and perform keep-data live validation before distribution.
EOF

echo "STAGE40_OFFLINE_BUILD_DONE=$delivery"
