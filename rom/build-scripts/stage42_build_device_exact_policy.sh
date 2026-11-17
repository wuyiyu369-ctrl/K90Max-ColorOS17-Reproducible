#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage42_device_exact_policy
base_delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS
base=$base_delivery/images/super.img
delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage42_FANPERF_POLICY
policy_src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/device_policy_20261106/policy_device_exact_stage42.bin

base_sha=03741d8f56443771417dc350f9ac483d8205b6452e976f38b641ea4fad8ba2f8
policy_sha=4b7f722b51f13f09cbbf04ad4bfc89d7d7ebbbfd350ed090a0f8672710155fcd
plat_hash=4fa400e7d806246f05f38ea0f6d5e3f6516958bb410cfa4f2680fdc7df075e5b
system_ext_hash=eb5142bd423c210c1cc262894280ba9440f3960d484a4c3f552fa5f915e43989

super_size=13421772800
odm_size=1724530688
odm_seek=2615552
odm_count=421028

for tool in mkfs.erofs fsck.erofs getfattr setfattr; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

test -s "$base"
test -s "$policy_src"
test "$(stat -c%s "$base")" -eq "$super_size"
test "$(sha256sum "$base" | awk '{print $1}')" = "$base_sha"
test "$(sha256sum "$policy_src" | awk '{print $1}')" = "$policy_sha"
test ! -e "$work"
test ! -e "$delivery"

mkdir -p "$work"/{out,odm_lower,odm_upper,odm_work,odm_merged,verify_odm}
mkdir -p "$delivery/images"

cleanup() {
  for mount_dir in "$work/verify_odm" "$work/odm_merged" "$work/odm_lower"; do
    mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  done
}
trap cleanup EXIT

# Extract only the Stage41 ODM extent. System and every other logical
# partition remain byte-identical to the already booted Stage41 package.
dd if="$base" of="$work/out/odm.base.img" bs=4096 \
  skip="$odm_seek" count="$odm_count" status=progress
test "$(stat -c%s "$work/out/odm.base.img")" -eq "$odm_size"
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.log" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.base.img" "$work/odm_lower"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$work/odm_upper"
mount -t overlay overlay \
  -o "lowerdir=$work/odm_lower,upperdir=$work/odm_upper,workdir=$work/odm_work" \
  "$work/odm_merged"

# The binary was compiled on the current Android 17 phone using its own
# /system/bin/secilc and only its currently running system, system_ext,
# product, vendor and ODM CIL/mapping inputs.
install -m 0644 "$policy_src" \
  "$work/odm_merged/etc/selinux/precompiled_sepolicy"
printf '%s\n' "$plat_hash" > \
  "$work/odm_merged/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256"
printf '%s\n' "$system_ext_hash" > \
  "$work/odm_merged/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256"

setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$work/odm_upper/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$work/odm_upper/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256" \
  "$work/odm_upper/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256"

# Stage41's performance directory label is required for the native bridge.
test "$(getfattr -n security.selinux --only-values \
  "$work/odm_merged/etc/performance" 2>/dev/null)" = \
  u:object_r:vendor_configs_file:s0

odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime)
[[ -n "$odm_label" ]] && odm_args+=(-L "$odm_label")
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" "$work/odm_merged" \
  > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.log" 2>&1
umount "$work/odm_merged"
umount "$work/odm_lower"

# Read the rebuilt EROFS back and verify every policy byte, marker and xattr.
mount -t erofs -o ro,loop "$work/out/odm.img" "$work/verify_odm"
cmp -s "$policy_src" "$work/verify_odm/etc/selinux/precompiled_sepolicy"
test "$(cat "$work/verify_odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256")" = "$plat_hash"
test "$(cat "$work/verify_odm/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256")" = "$system_ext_hash"
test "$(getfattr -n security.selinux --only-values \
  "$work/verify_odm/etc/selinux/precompiled_sepolicy" 2>/dev/null)" = \
  u:object_r:sepolicy_file:s0
test "$(getfattr -n security.selinux --only-values \
  "$work/verify_odm/etc/performance" 2>/dev/null)" = \
  u:object_r:vendor_configs_file:s0
umount "$work/verify_odm"

# Copy the proven Stage41 super on D: and replace only its fixed ODM extent.
cp --sparse=always "$base" "$delivery/images/super.img.building"
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=4096 \
  seek="$odm_seek" count="$odm_count" conv=notrunc,fsync status=progress
test "$(stat -c%s "$delivery/images/super.img.building")" -eq "$super_size"
mv "$delivery/images/super.img.building" "$delivery/images/super.img"

test "$(dd if="$delivery/images/super.img" bs=4096 skip="$odm_seek" \
  count="$odm_count" status=none | sha256sum | awk '{print $1}')" = \
  "$(sha256sum "$work/out/odm.img" | awk '{print $1}')"

cp "$base_delivery/FLASH_KEEP_DATA.ps1" "$delivery/"
cp "$base_delivery/START_UPDATE.cmd" "$delivery/" 2>/dev/null || true
cp -a "$base_delivery/platform-tools" "$delivery/"
sha256sum "$work/out/odm.img" "$policy_src" \
  "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"

cat > "$delivery/STATUS.txt" <<EOF
OFFLINE_CHECKS_PASSED
BASE_STAGE41_SHA256=$base_sha
DEVICE_EXACT_POLICY_SHA256=$policy_sha
PLAT_POLICY_MARKER=$plat_hash
SYSTEM_EXT_POLICY_MARKER=$system_ext_hash
ONLY_ODM_EXTENT_CHANGED_FROM_STAGE41
DEVICE_BOOT_AND_FUNCTION_TESTS_NOT_YET_RUN
DO_NOT_DISTRIBUTE_BEFORE_LIVE_TEST
EOF

cat > "$delivery/CHANGES_STAGE42.txt" <<'EOF'
Stage42 device-exact SELinux integration:
1. Uses the current phone's actual Android 17 platform, system_ext, product,
   vendor and ODM policy inputs with the same 202504 mappings.
2. The phone's own /system/bin/secilc generated the precompiled policy using
   Android init's official split-policy arguments.
3. Updates ODM's platform and system_ext hash markers so init selects the
   matching precompiled policy instead of the stale Stage41 binary.
4. Preserves Stage41's /odm/etc/performance directory label and payload.
5. Changes only the ODM extent inside the Stage41 super image.

Offline checks do not prove boot, fan rotation or scheduling behavior.
Keep-data live validation is mandatory before distribution.
EOF

echo "STAGE42_OFFLINE_BUILD_DONE=$delivery"
