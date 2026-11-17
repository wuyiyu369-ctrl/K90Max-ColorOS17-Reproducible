#!/bin/bash
set -euo pipefail
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN
work=$root/02_Codex完整工作区/wo/stage45_work
overlay=/root/k90_stage45_overlay
cleanup(){ for n in verify my_product_merged my_product_lower; do mountpoint -q "$overlay/$n" && umount "$overlay/$n" || true; done; }
trap cleanup EXIT
test -s "$work/out/odm.img"
test ! -e "$delivery/images/super.img"
mount -t erofs -o ro,loop "$work/out/my_product.base.img" "$overlay/my_product_lower"
mount -t overlay overlay -o "lowerdir=$overlay/my_product_lower,upperdir=$overlay/my_product_upper,workdir=$overlay/my_product_work" "$overlay/my_product_merged"
grep -q 'name="oplus.misc.fan.support"' "$overlay/my_product_merged/etc/permissions/oplus.feature.android.xml"
# Match Stage40's 64KiB compression cluster to fit the original partition.
mkfs.erofs -z lz4hc,12 -C 65536 -T 1791306550 -U "$(blkid -o value -s UUID "$work/out/my_product.base.img")" --preserve-mtime "$work/out/my_product.raw.img" "$overlay/my_product_merged" > "$work/out/mkfs-my_product-64k.log" 2>&1
test "$(stat -c%s "$work/out/my_product.raw.img")" -le 1138266112
cp --sparse=always "$work/out/my_product.raw.img" "$work/out/my_product.img"
truncate -s 1138266112 "$work/out/my_product.img"
fsck.erofs "$work/out/my_product.img" > "$work/out/fsck-my_product.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/my_product.img" "$overlay/verify"
test "$(stat -c %u:%g:%a "$overlay/verify")" = "$(stat -c %u:%g:%a "$overlay/my_product_lower")"
test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = "$(getfattr -n security.selinux --only-values "$overlay/my_product_lower" 2>/dev/null)"
cmp "$overlay/my_product_merged/etc/permissions/oplus.feature.android.xml" "$overlay/verify/etc/permissions/oplus.feature.android.xml"
umount "$overlay/verify"
cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
dd if="$work/out/my_product.img" of="$delivery/images/super.img.building" bs=1M seek=2198 conv=notrunc,fsync status=progress
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=1M seek=10217 conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$delivery/images/super.img"
cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
python3 "$src/stage45_verify.py" "$base/images/super.img" "$delivery" "$work/out"
cp "$work/out/"fsck-*.txt "$delivery/audit/"
cp "$src/stage45_diagnosis/调度与ACE7风扇排查.md" "$delivery/audit/"
echo STAGE45_OFFLINE_BUILD_PASSED
