#!/usr/bin/env bash
set -euo pipefail

base='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/vendor_boot_unpack/vendor_ramdisk'
stock='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/04_原始底包与参考包/BAO/RedmiK90Max_OS4.0.0.14_17.0/zhuimeng/vendor_boot.img'
out='/mnt/d/vbtmp'

mkdir -p "$out"
rm -f "$out/ramdisk_before.lz4"
rm -f "$out/ramdisk_modified.lz4"
rm -f "$out/recovery.lz4"
rm -f "$out/stock_ramdisk.lz4"
rm -f "$out/stock_recovery.lz4"

lz4 -l -12 "$base/ramdisk.cpio.before_my_mounts" "$out/ramdisk_before.lz4" >/dev/null
lz4 -l -12 "$base/ramdisk.cpio" "$out/ramdisk_modified.lz4" >/dev/null
lz4 -l -12 "$base/recovery.cpio" "$out/recovery.lz4" >/dev/null

dd if="$stock" of="$out/stock_ramdisk.lz4" bs=4M iflag=skip_bytes,count_bytes skip=4096 count=36885943 status=none
dd if="$stock" of="$out/stock_recovery.lz4" bs=4M iflag=skip_bytes,count_bytes skip=36890039 count=16072280 status=none

sha256sum "$out/ramdisk_before.lz4" "$out/stock_ramdisk.lz4"
sha256sum "$out/recovery.lz4" "$out/stock_recovery.lz4"
sha256sum "$out/ramdisk_modified.lz4"
stat -c '%n %s' "$out/ramdisk_before.lz4" "$out/stock_ramdisk.lz4" "$out/recovery.lz4" "$out/stock_recovery.lz4" "$out/ramdisk_modified.lz4"

cmp "$out/ramdisk_before.lz4" "$out/stock_ramdisk.lz4"
cmp "$out/recovery.lz4" "$out/stock_recovery.lz4"
echo 'COMPRESSED_COMPONENTS_MATCH_STOCK=YES'
