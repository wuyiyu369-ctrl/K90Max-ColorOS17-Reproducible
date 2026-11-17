#!/usr/bin/env bash
set -euo pipefail

BASE=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_BRIGHTNESS_CURVE_R4/images/super.img
CANDIDATE=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE_CANDIDATE/native_patch/telephony-common.jar
EXTRACT=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/super_unpack_test/system_a_a.img
OUT=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE/images
WORK=/root/k90_stage24_sms_native
OFF=8388608
PART_LEN=1061134336
SUPER_LEN=13421772800

test -f "$BASE"; test -f "$CANDIDATE"; test -f "$EXTRACT"
rm -rf "$WORK"
mkdir -p "$WORK"/{lower,upper,work,merged,out}
cp --sparse=always "$EXTRACT" "$WORK/system.base.img"
mount -t erofs -o loop,ro "$WORK/system.base.img" "$WORK/lower"
mount -t overlay overlay -o "lowerdir=$WORK/lower,upperdir=$WORK/upper,workdir=$WORK/work" "$WORK/merged"
trap 'umount "$WORK/merged" 2>/dev/null || true; umount "$WORK/lower" 2>/dev/null || true' EXIT
install -o 0 -g 0 -m 0644 "$CANDIDATE" "$WORK/merged/system/framework/telephony-common.jar"
setfattr -n security.selinux -v 'u:object_r:system_file:s0' "$WORK/upper/system/framework/telephony-common.jar"
setfattr -n security.selinux -v 'u:object_r:system_file:s0' "$WORK/merged"
test "$(getfattr --only-values -n security.selinux "$WORK/merged")" = 'u:object_r:system_file:s0'
mkfs.erofs -z lz4hc,12 -C 16384 --preserve-mtime "$WORK/out/system.raw.img" "$WORK/merged" > "$WORK/mkfs.log" 2>&1
test "$(stat -c %s "$WORK/out/system.raw.img")" -le 1049554944
cp --sparse=always "$WORK/out/system.raw.img" "$WORK/out/system.img"
python3 /mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py add_hashtree_footer --image "$WORK/out/system.img" --partition_size "$PART_LEN" --partition_name system --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 --block_size 4096 --do_not_generate_fec --algorithm NONE --prop com.android.build.oplus_custom_images.os_version:11 --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
truncate -s "$PART_LEN" "$WORK/out/system.img"
fsck.erofs "$WORK/out/system.img" > "$WORK/fsck.log" 2>&1
mkdir -p "$OUT"
cp --sparse=always "$BASE" "$OUT/super.img"
dd if="$WORK/out/system.img" of="$OUT/super.img" bs=4096 seek=$((OFF/4096)) conv=notrunc status=progress
test "$(stat -c %s "$OUT/super.img")" -eq "$SUPER_LEN"
sha256sum "$OUT/super.img" > "$OUT/SHA256SUMS.txt"
echo "NATIVE_SMS_SUPER_BUILT=$OUT/super.img"
