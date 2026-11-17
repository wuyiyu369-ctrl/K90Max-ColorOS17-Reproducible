#!/usr/bin/env bash
set -euo pipefail
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
base="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1/images/super.img"
work=/root/k90_stage33_merge
mkdir -p "$work/images"
extract() {
  local name=$1 offset=$2 size=$3
  local out="$work/images/$name"
  if [[ -f "$out" && "$(stat -c%s "$out")" -eq "$size" ]]; then return; fi
  rm -f "$out"
  dd if="$base" of="$out" bs=16M skip="$offset" count="$size" iflag=skip_bytes,count_bytes status=progress
}
# Stage31 fixed LP extents.
extract product31.img 2150629376 152326144
extract odm31.img 10713300992 1724530688
extract my_product31.img 2304770048 1138266112
cp -f "$work/images/my_product31.img" /root/k90_stage32_camera_external_return_my_product.img
echo STAGE34_INPUTS_READY
