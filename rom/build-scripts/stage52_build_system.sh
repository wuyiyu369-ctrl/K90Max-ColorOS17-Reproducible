#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage52_FAN_AOD_SIM
work=$root/02_Codex完整工作区/wo/stage52_work
overlay=/root/k90_stage49_overlay
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py
jar=$src/stage52_services.aligned.jar

system_offset=1048576
system_size=1049554944
system_partition_size=1061134336
system_end=$((system_offset + system_partition_size))

mkdir -p "$work/out" "$delivery/images" "$delivery/audit"
mkdir -p "$overlay"/{system_lower,system_upper,system_work,system_merged,verify}

cleanup() {
  for mount_name in verify system_merged system_lower; do
    mountpoint -q "$overlay/$mount_name" && umount "$overlay/$mount_name" || true
  done
}
trap cleanup EXIT

test -s "$base/images/super.img"
test -s "$jar"
grep -q '^STAGE49_SERVICES_BUILD_PASSED$' "$src/stage52_services_audit.txt"

if [[ ! -s "$work/out/system.base.img" ]]; then
  dd if="$base/images/super.img" of="$work/out/system.base.img" \
    bs=4096 skip=256 count=256239 status=progress
fi
test "$(stat -c%s "$work/out/system.base.img")" -eq "$system_size"
fsck.erofs "$work/out/system.base.img" > "$work/out/fsck-system-base.txt" 2>&1
if ! python3 "$avb" info_image --image "$work/out/system.base.img" \
  > "$work/out/avb-system-base.txt" 2>&1; then
  echo "BASE_EXTENT_HAS_NO_STANDALONE_AVB_METADATA" >> "$work/out/avb-system-base.txt"
fi

mount -t erofs -o ro,loop "$work/out/system.base.img" "$overlay/system_lower"
test "$(sha256sum "$overlay/system_lower/system/framework/services.jar" | cut -d' ' -f1)" = \
  291529e31adc298f6aa4ae0133fabef4f01bfebdbc23d20128d59feda27fee88

root_context=$(getfattr -n security.selinux --only-values "$overlay/system_lower" 2>/dev/null)
setfattr -n security.selinux -v "$root_context" "$overlay/system_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/system_lower,upperdir=$overlay/system_upper,workdir=$overlay/system_work" \
  "$overlay/system_merged"

cp "$jar" "$overlay/system_merged/system/framework/services.jar"
cp --attributes-only --preserve=all \
  "$overlay/system_lower/system/framework/services.jar" \
  "$overlay/system_upper/system/framework/services.jar"

uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
mkfs_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || mkfs_args+=(-L "$label")

mkfs.erofs "${mkfs_args[@]}" "$work/out/system.raw.img" "$overlay/system_merged" \
  > "$work/out/mkfs-system.log" 2>&1
actual=$(stat -c%s "$work/out/system.raw.img")
test "$actual" -le "$system_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_size" "$work/out/system.img"

python3 "$avb" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_partition_size" --partition_name system \
  --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
  --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$work/out/system.img" \
  > "$work/out/avb-system.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1

umount "$overlay/system_merged"
umount "$overlay/system_lower"
mount -t erofs -o ro,loop "$work/out/system.img" "$overlay/verify"
cmp "$jar" "$overlay/verify/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = "$root_context"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/system/framework/services.jar" 2>/dev/null)" = \
  u:object_r:system_file:s0
test "$(stat -c %u:%g:%a "$overlay/verify/system/framework/services.jar")" = \
  "$(stat -c %u:%g:%a "$overlay/system_upper/system/framework/services.jar")"
umount "$overlay/verify"

if [[ ! -s "$delivery/images/super.img" ]]; then
  cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
  dd if="$work/out/system.img" of="$delivery/images/super.img.building" \
    bs=1M seek=1 conv=notrunc,fsync status=progress
  mv "$delivery/images/super.img.building" "$delivery/images/super.img"
else
  # Stage52 already owns a complete candidate super image. Patch only the
  # bounded system extent; the Stage49 base remains the rollback source.
  dd if="$work/out/system.img" of="$delivery/images/super.img" \
    bs=1M seek=1 conv=notrunc,fsync status=progress
fi

cmp -n "$system_offset" "$base/images/super.img" "$delivery/images/super.img"
# Compare bounded samples instead of scanning the remaining 11+ GiB over /mnt/d.
cmp -n 4194304 -i "$system_end:$system_end" "$base/images/super.img" "$delivery/images/super.img"
cmp -n 4194304 -i "$((13421772800 - 4194304)):$((13421772800 - 4194304))" \
  "$base/images/super.img" "$delivery/images/super.img"

dd if="$delivery/images/super.img" of="$work/out/system.readback.img" \
  bs=4096 skip=256 count=259066 status=none
cmp "$work/out/system.img" "$work/out/system.readback.img"
fsck.erofs "$work/out/system.readback.img" > "$work/out/fsck-system-readback.txt" 2>&1
python3 "$avb" verify_image --image "$work/out/system.readback.img" \
  > "$work/out/avb-system-readback.txt"

cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
cp "$work/out/"fsck-*.txt "$work/out/"avb-*.txt "$work/out/mkfs-system.log" "$delivery/audit/"
cp "$src/stage52_services_audit.txt" "$delivery/audit/"

sha256sum "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"
sha256sum "$work/out/system.img" > "$delivery/audit/system.sha256"
sha256sum "$jar" > "$delivery/audit/services.jar.sha256"

cat > "$delivery/STATUS.txt" <<'EOF'
Stage52 fan/AOD/SIM candidate
Base: Stage49_FAN_SETTING_FIX
Changed partition: system only
Data wipe: no
Fan fix: static validation passed; device validation pending
Single-SIM-in-slot-2 registration: not patched; root cause not proven by supplied logs
EOF

cat > "$delivery/audit/STAGE49_CHANGES.txt" <<'EOF'
1. Observe the ACE7 UI key cooling_fan_mode instead of the unused cooling_fan_mode_v3 key.
2. Read cooling_fan_mode first while retaining cooling_fan_mode_v3 as a compatibility fallback.
3. Preserve all Stage48 ODM performance, camera, radio, and native bridge contents byte-for-byte.
4. Do not spoof service state, signal bars, or carrier registration.
EOF

echo STAGE49_OFFLINE_BUILD_PASSED
