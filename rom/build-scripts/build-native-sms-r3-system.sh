#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_sms_native_r3_system
base=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/sms_r2_final_extract/system_a_a.img
candidate=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/sms_native_r3/telephony-common.native-sms-r3.jar
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py
partition_size=1061134336
original_size=1049554944

for f in "$base" "$candidate" "$avb"; do test -f "$f"; done
rm -rf "$work"
mkdir -p "$work"/{lower,upper,work,merged,verify,out}
cleanup() {
  for m in "$work/verify" "$work/merged" "$work/lower"; do
    mountpoint -q "$m" && umount "$m" || true
  done
}
trap cleanup EXIT

mount -t erofs -o ro,loop "$base" "$work/lower"
test "$(getfattr -n security.selinux --only-values "$work/lower" 2>/dev/null)" = 'u:object_r:rootfs:s0'
setfattr -n security.selinux -v u:object_r:rootfs:s0 "$work/upper"
mount -t overlay overlay -o "lowerdir=$work/lower,upperdir=$work/upper,workdir=$work/work" "$work/merged"
install -o 0 -g 0 -m 0644 "$candidate" "$work/merged/system/framework/telephony-common.jar"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper/system/framework/telephony-common.jar"

uuid=$(blkid -o value -s UUID "$base")
test "$uuid" = '212ef468-c526-563b-babf-8465c924ade4'
label=$(blkid -o value -s LABEL "$base" || true)
args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$uuid" --preserve-mtime)
[[ -n "$label" ]] && args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/out/system.raw.img" "$work/merged" > "$work/mkfs.log" 2>&1
if (( $(stat -c%s "$work/out/system.raw.img") > original_size )); then
  rm -f "$work/out/system.raw.img"
  args=(-z lz4hc,12 -C 32768 -T 1791277125 -U "$uuid" --preserve-mtime)
  [[ -n "$label" ]] && args+=(-L "$label")
  mkfs.erofs "${args[@]}" "$work/out/system.raw.img" "$work/merged" >> "$work/mkfs.log" 2>&1
fi
test "$(stat -c%s "$work/out/system.raw.img")" -le "$original_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$original_size" "$work/out/system.img"
python3 "$avb" add_hashtree_footer --image "$work/out/system.img" --partition_size "$partition_size" --partition_name system --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 --block_size 4096 --do_not_generate_fec --algorithm NONE --prop com.android.build.oplus_custom_images.os_version:11 --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$work/out/system.img" > "$work/avb-verify.txt"
fsck.erofs "$work/out/system.img" > "$work/fsck.txt" 2>&1
! grep -Eqi 'bogus|corruption|error|failed' "$work/fsck.txt"

mount -t erofs -o ro,loop "$work/out/system.img" "$work/verify"
test "$(getfattr -n security.selinux --only-values "$work/verify" 2>/dev/null)" = 'u:object_r:rootfs:s0'
test "$(getfattr -n security.selinux --only-values "$work/verify/system/framework/telephony-common.jar" 2>/dev/null)" = 'u:object_r:system_file:s0'
test "$(sha256sum "$work/verify/system/framework/telephony-common.jar" | cut -d' ' -f1)" = "$(sha256sum "$candidate" | cut -d' ' -f1)"
dump.erofs -s "$work/out/system.img" > "$work/superblock.txt"
grep -q '212ef468-c526-563b-babf-8465c924ade4' "$work/superblock.txt"
sha256sum "$work/out/system.img" > "$work/SHA256SUMS.txt"
echo SMS_NATIVE_R3_SYSTEM_OK
