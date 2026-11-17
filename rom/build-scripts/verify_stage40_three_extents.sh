#!/usr/bin/env bash
set -euo pipefail
B=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img
C=/root/k90_stage40_fanperf_offline/delivery/images/super.img
cmp -n $((256*4096)) "$B" "$C"
cmp -i $((259322*4096)):$((259322*4096)) -n $(((562688-259322)*4096)) "$B" "$C"
cmp -i $((840585*4096)):$((840585*4096)) -n $(((2615552-840585)*4096)) "$B" "$C"
cmp -i $((3036580*4096)):$((3036580*4096)) -n $((240220*4096)) "$B" "$C"
echo ALL_NON_TARGET_SYSTEM_MYPRODUCT_ODM_EXTENTS_IDENTICAL
