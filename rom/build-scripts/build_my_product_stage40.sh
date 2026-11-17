#!/usr/bin/env bash
set -euo pipefail
W=/root/k90_stage40_fanperf_offline
T=/root/k90_stage36/work/my_product_tree
OUT="$W/out/my_product.raw.img"
rm -f "$OUT" "$W/out/my_product.img"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$T" "$T/app" "$T/app/DeviceSettings" "$T/app/DeviceSettings/DeviceSettings.apk"
mkfs.erofs -z lz4hc,12 -C 65536 -T 1793863200 -U d133458d-0e5d-58f3-b521-b1bedbb17daf --preserve-mtime "$OUT" "$T" > "$W/out/mkfs-my_product.log" 2>&1
S=$(stat -c%s "$OUT")
echo RAW_SIZE=$S
test "$S" -le 1125847040
cp --sparse=always "$OUT" "$W/out/my_product.img"
truncate -s 1138266112 "$W/out/my_product.img"
fsck.erofs "$W/out/my_product.img" > "$W/out/fsck-my_product.log" 2>&1
mkdir -p /tmp/mp40
mount -t erofs -o ro,loop "$W/out/my_product.img" /tmp/mp40
test -f /tmp/mp40/app/DeviceSettings/DeviceSettings.apk
ls -l /tmp/mp40/app/DeviceSettings/DeviceSettings.apk
umount /tmp/mp40
echo MY_PRODUCT_BUILD_OK
