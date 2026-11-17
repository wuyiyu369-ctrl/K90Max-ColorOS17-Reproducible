#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage25_perf_system
base=/root/k90_sms_native_r3_system/out/system.img
jar_root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage25_perf
framework="$jar_root/framework.stage25.jar"
oplus_framework="$jar_root/oplus-framework.stage25.jar"
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py
partition_size=1061134336
original_size=1049554944

for f in "$base" "$framework" "$oplus_framework" "$avb"; do test -f "$f"; done
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

framework_target="$work/merged/system/framework/framework.jar"
oplus_target="$work/merged/system/framework/oplus-framework.jar"
telephony_target="$work/merged/system/framework/telephony-common.jar"
test -f "$framework_target"
test -f "$oplus_target"
test -f "$telephony_target"
telephony_before=$(sha256sum "$telephony_target" | cut -d' ' -f1)
test "$telephony_before" = '235f3189ba172e3fce471aeba7c7e9a9cc2f88c19c5986ffb8a459675fea146f'

install -o 0 -g 0 -m 0644 "$framework" "$framework_target"
install -o 0 -g 0 -m 0644 "$oplus_framework" "$oplus_target"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper/system/framework/framework.jar"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper/system/framework/oplus-framework.jar"

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
for file in framework.jar oplus-framework.jar telephony-common.jar; do
  test "$(getfattr -n security.selinux --only-values "$work/verify/system/framework/$file" 2>/dev/null)" = 'u:object_r:system_file:s0'
done
test "$(sha256sum "$work/verify/system/framework/framework.jar" | cut -d' ' -f1)" = "$(sha256sum "$framework" | cut -d' ' -f1)"
test "$(sha256sum "$work/verify/system/framework/oplus-framework.jar" | cut -d' ' -f1)" = "$(sha256sum "$oplus_framework" | cut -d' ' -f1)"
test "$(sha256sum "$work/verify/system/framework/telephony-common.jar" | cut -d' ' -f1)" = "$telephony_before"
dump.erofs -s "$work/out/system.img" > "$work/superblock.txt"
grep -q '212ef468-c526-563b-babf-8465c924ade4' "$work/superblock.txt"
sha256sum "$work/out/system.img" "$work/verify/system/framework/framework.jar" "$work/verify/system/framework/oplus-framework.jar" "$work/verify/system/framework/telephony-common.jar" > "$work/SHA256SUMS.txt"
echo STAGE25_PERF_SYSTEM_OK
