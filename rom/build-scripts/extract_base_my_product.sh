#!/usr/bin/env bash
set -euo pipefail
W=/root/k90_stage40_fanperf_offline
BASE=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img
dd if="$BASE" of="$W/out/my_product.base.img" bs=4096 skip=562688 count=277897 status=progress
stat -c "%s" "$W/out/my_product.base.img"
fsck.erofs "$W/out/my_product.base.img" > "$W/out/fsck-my_product-base.log" 2>&1
echo MY_PRODUCT_BASE_EXTRACT_OK
