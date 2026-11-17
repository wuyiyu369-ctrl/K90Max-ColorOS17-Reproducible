#!/usr/bin/env bash
set -euo pipefail

work=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage43_services_repair_work
overlay=/root/k90_stage43_system_overlay
base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS/images/super.img
base_delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS
jar=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/device_policy_20261106/jar_repair/services_stage43_fixed.jar
delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR
avbtool=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

base_sha=03741d8f56443771417dc350f9ac483d8205b6452e976f38b641ea4fad8ba2f8
jar_sha=c960254b19956c7911880c27b313b073de46f9cbbaefa3f94e6475fb58fc95ac
super_size=13421772800
system_size=1061134336
system_original_size=1049554944
system_seek=256
system_count=259066
system_salt=e25ce9d868f66f3acadc4cd9388398d9

test -s "$work/out/system.base.img"
test "$(stat -c%s "$work/out/system.base.img")" -eq "$system_size"
test -s "$jar"
test "$(sha256sum "$jar" | awk '{print $1}')" = "$jar_sha"
test ! -e "$overlay"
mkdir -p "$overlay"/{lower,upper,work,merged,verify}

cleanup() {
  for mount_dir in "$overlay/verify" "$overlay/merged" "$overlay/lower"; do
    mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  done
}
trap cleanup EXIT

# Keep overlay upper/work on Linux ext4. DrvFS cannot represent overlayfs
# whiteouts/copy-up metadata reliably.
mount -t erofs -o ro,loop "$work/out/system.base.img" "$overlay/lower"
setfattr -n security.selinux -v u:object_r:rootfs:s0 "$overlay/upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"

cp -f "$jar" "$overlay/merged/system/framework/services.jar"
chmod 0644 "$overlay/merged/system/framework/services.jar"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$overlay/upper/system/framework/services.jar"
cmp -s "$jar" "$overlay/merged/system/framework/services.jar"

system_uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
system_label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
system_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$system_uuid" --preserve-mtime)
[[ -n "$system_label" ]] && system_args+=(-L "$system_label")
mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" "$overlay/merged" \
  > "$work/out/mkfs-system.log" 2>&1
if (( $(stat -c%s "$work/out/system.raw.img") > system_original_size )); then
  rm -f "$work/out/system.raw.img"
  system_args=(-z lz4hc,12 -C 32768 -T 1791277125 -U "$system_uuid" --preserve-mtime)
  [[ -n "$system_label" ]] && system_args+=(-L "$system_label")
  mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" "$overlay/merged" \
    > "$work/out/mkfs-system.log" 2>&1
fi
test "$(stat -c%s "$work/out/system.raw.img")" -le "$system_original_size"

cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_original_size" "$work/out/system.img"
python3 "$avbtool" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_size" --partition_name system --hash_algorithm sha256 \
  --salt "$system_salt" --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avbtool" verify_image --image "$work/out/system.img" \
  > "$work/out/avb-system-verify.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.log" 2>&1

umount "$overlay/merged"
umount "$overlay/lower"

mount -t erofs -o ro,loop "$work/out/system.img" "$overlay/verify"
cmp -s "$jar" "$overlay/verify/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/system/framework/services.jar" 2>/dev/null)" = \
  u:object_r:system_file:s0
umount "$overlay/verify"

cp --sparse=always "$base" "$delivery/images/super.img.building"
dd if="$work/out/system.img" of="$delivery/images/super.img.building" \
  bs=4096 seek="$system_seek" count="$system_count" conv=notrunc,fsync status=progress
test "$(stat -c%s "$delivery/images/super.img.building")" -eq "$super_size"
mv "$delivery/images/super.img.building" "$delivery/images/super.img"
test "$(dd if="$delivery/images/super.img" bs=4096 skip="$system_seek" \
  count="$system_count" status=none | sha256sum | awk '{print $1}')" = \
  "$(sha256sum "$work/out/system.img" | awk '{print $1}')"

cp "$base_delivery/FLASH_KEEP_DATA.ps1" "$delivery/"
cp "$base_delivery/START_UPDATE.cmd" "$delivery/" 2>/dev/null || true
cp -a "$base_delivery/platform-tools" "$delivery/"
sha256sum "$jar" "$work/out/system.img" "$delivery/images/super.img" \
  > "$delivery/SHA256SUMS.txt"

cat > "$delivery/STATUS.txt" <<EOF
OFFLINE_CHECKS_PASSED
BASE_STAGE41_SHA256=$base_sha
FIXED_SERVICES_JAR_SHA256=$jar_sha
ONLY_SYSTEM_EXTENT_CHANGED_FROM_STAGE41
ODM_AND_STAGE41_POLICY_UNCHANGED
DEVICE_BOOT_TEST_NOT_YET_RUN
EOF

cat > "$delivery/CHANGES_STAGE43.txt" <<'EOF'
Stage43 boot repair:
1. Replaced the corrupt Stage41 services.jar with a valid Stage38-based JAR.
2. Preserved all four original dex files and all original classes.
3. Replaced only classes4.dex with the audited Stage40 variant whose class set
   equals Stage38 plus K90ThermalBridge.
4. Preserved Stage41 ODM, fan/performance files and original precompiled policy.
5. This build does not wipe userdata or metadata.
EOF

echo "STAGE43_BUILD_DONE=$delivery"
