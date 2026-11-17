#!/usr/bin/env bash
set -euo pipefail

base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img
candidate=/root/k90_stage40_fanperf_offline/delivery/images/super.img

cmp -n $((256 * 4096)) "$base" "$candidate"
echo PREFIX_UNCHANGED

middle_start=$((259322 * 4096))
cmp -i "$middle_start:$middle_start" -n $((2356230 * 4096)) "$base" "$candidate"
echo MIDDLE_UNCHANGED

tail_start=$((3036580 * 4096))
cmp -i "$tail_start:$tail_start" -n $((240220 * 4096)) "$base" "$candidate"
echo TAIL_UNCHANGED

echo ALL_NON_TARGET_EXTENTS_IDENTICAL
