#!/usr/bin/env bash
set -euo pipefail
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX/images/super.img
work=$root/02_Codex完整工作区/wo/stage44_r2_fan_ui
mkdir -p "$work/out"
dd if="$base" of="$work/out/my_product.base.img" bs=1M skip=2198 count=1086 status=progress
test "$(stat -c%s "$work/out/my_product.base.img")" -eq 1138753536
# The partition ends before the next MiB-aligned extent: use exact size.
truncate -s 1138266112 "$work/out/my_product.base.img"
python3 "$root/02_Codex完整工作区/wo/tools/avb/avbtool.py" info_image --image "$work/out/my_product.base.img" > "$work/out/avb-base.txt" 2>&1 || true
fsck.erofs "$work/out/my_product.base.img" > "$work/out/fsck-base.txt" 2>&1
cat "$work/out/avb-base.txt"
