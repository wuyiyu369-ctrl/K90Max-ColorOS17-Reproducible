#!/usr/bin/env bash
set -euo pipefail
W=/root/k90_stage40_fanperf_offline
BASE="$W/out/my_product.base.img"
LOWER="$W/mp_lower"
UPPER="$W/mp_upper"
WORK="$W/mp_work"
MERGED="$W/mp_merged"
OUT="$W/out/my_product.raw.img"
for d in "$LOWER" "$UPPER" "$WORK" "$MERGED"; do mkdir -p "$d"; done
cleanup(){ mountpoint -q "$MERGED" && umount "$MERGED" || true; mountpoint -q "$LOWER" && umount "$LOWER" || true; }
trap cleanup EXIT
mount -t erofs -o ro,loop "$BASE" "$LOWER"
mkdir -p "$UPPER/app/DeviceSettings"
cp -a "$LOWER/app/DeviceSettings/DeviceSettings.apk" "$UPPER/app/DeviceSettings/DeviceSettings.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$UPPER" "$UPPER/app" "$UPPER/app/DeviceSettings" "$UPPER/app/DeviceSettings/DeviceSettings.apk"
mount -t overlay overlay -o "lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK" "$MERGED"
rm -f "$OUT" "$W/out/my_product.img"
mkfs.erofs -z lz4hc,12 -C 65536 -T 1793863200 -U d133458d-0e5d-58f3-b521-b1bedbb17daf --preserve-mtime "$OUT" "$MERGED" > "$W/out/mkfs-my_product-labels.log" 2>&1
S=$(stat -c%s "$OUT")
echo RAW_SIZE=$S
test "$S" -le 1138266112
cp --sparse=always "$OUT" "$W/out/my_product.img"
truncate -s 1138266112 "$W/out/my_product.img"
fsck.erofs "$W/out/my_product.img" > "$W/out/fsck-my_product.log" 2>&1
echo MY_PRODUCT_LABEL_BUILD_OK
