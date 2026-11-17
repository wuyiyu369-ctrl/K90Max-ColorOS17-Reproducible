#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage57_FAN_CONTROL_FIX
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage58_FAN_BRANCH_FIX
work=/root/k90_stage58_work
overlay=/root/k90_stage58_overlay
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py
jar=$src/_fan_live_services_stage57/services.stage57.jar

system_offset=1048576
system_size=1049554944
system_partition_size=1061134336
super_size=13421772800
base_super_hash=142caee297d8998e4fa0365045e01a4ee43af82effc3fdf1a9290972061af082
base_jar_hash=445e1461a26577f38929a05c10303a73563cdd7124d2e2a22261eb62831f732a

test -s "$base/images/super.img"
test -s "$jar"
test -s "$avb"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
test "$(sha256sum "$base/images/super.img" | cut -d' ' -f1)" = "$base_super_hash"

rm -rf "$work" "$overlay"
mkdir -p "$work/out" "$overlay"/{lower,upper,work,merged,verify} "$out/images" "$out/audit"
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

dd if="$base/images/super.img" of="$work/out/system.base.img" \
  iflag=skip_bytes,count_bytes skip="$system_offset" \
  count="$system_partition_size" status=none
test "$(stat -c%s "$work/out/system.base.img")" -eq "$system_partition_size"
fsck.erofs "$work/out/system.base.img" > "$work/out/fsck-system-base.txt" 2>&1
python3 "$avb" info_image --image "$work/out/system.base.img" \
  > "$work/out/avb-system-base.txt"

mount -t erofs -o ro,loop "$work/out/system.base.img" "$overlay/lower"
test "$(sha256sum "$overlay/lower/system/framework/services.jar" | cut -d' ' -f1)" = "$base_jar_hash"
test "$(getfattr -n security.selinux --only-values "$overlay/lower/system/framework/services.jar")" = u:object_r:system_file:s0

root_label=$(getfattr -n security.selinux --only-values "$overlay/lower")
setfattr -n security.selinux -v "$root_label" "$overlay/upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
cp "$jar" "$overlay/merged/system/framework/services.jar"
cp --attributes-only --preserve=all \
  "$overlay/lower/system/framework/services.jar" \
  "$overlay/upper/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values "$overlay/merged/system/framework/services.jar")" = u:object_r:system_file:s0

python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/merged" /system "$work/out/system_file_contexts.generated" \
  --override /system/my_reserve=u:object_r:system_file:s0 \
  > "$work/out/system-file-contexts-generation.txt"
uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791287125 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || args+=(-L "$label")
args+=(--mount-point=/system --file-contexts="$work/out/system_file_contexts.generated")
mkfs.erofs "${args[@]}" "$work/out/system.raw.img" "$overlay/merged" \
  > "$work/out/mkfs-system.log" 2>&1
test "$(stat -c%s "$work/out/system.raw.img")" -le "$system_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_size" "$work/out/system.img"
python3 "$avb" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_partition_size" --partition_name system \
  --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
  --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$work/out/system.img" > "$work/out/avb-system.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1

umount "$overlay/merged"
umount "$overlay/lower"
mount -t erofs -o ro,loop "$work/out/system.img" "$overlay/verify"
cmp "$jar" "$overlay/verify/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/system/framework/services.jar")" = u:object_r:system_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-system-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

cp "$base/images/super.img" "$out/images/super.img.candidate"
dd if="$work/out/system.img" of="$out/images/super.img.candidate" bs=4096 \
  seek=$((system_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$out/images/super.img.candidate")" -eq "$super_size"
dd if="$out/images/super.img.candidate" of="$work/out/system.readback.img" \
  iflag=skip_bytes,count_bytes skip="$system_offset" \
  count="$system_partition_size" status=none
cmp "$work/out/system.img" "$work/out/system.readback.img"
fsck.erofs "$work/out/system.readback.img" > "$work/out/fsck-system-readback.txt" 2>&1
python3 "$avb" verify_image --image "$work/out/system.readback.img" \
  > "$work/out/avb-system-readback.txt"

# The candidate is a checked full-file copy of Stage57 followed by one exact,
# size-bounded system write. Check both unchanged ranges independently.
cmp -n "$system_offset" "$base/images/super.img" "$out/images/super.img.candidate"
tail=$((system_offset + system_partition_size))
cmp -n "$((super_size - tail))" -i "$tail:$tail" \
  "$base/images/super.img" "$out/images/super.img.candidate"

cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
cp "$src/_fan_live_services_stage57/stage57_services_audit.txt" "$out/audit/services-audit.txt"
echo STAGE58_OFFLINE_BUILD_PASSED
