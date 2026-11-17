#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
s26="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage26_AOD_R1/images/super.img"
s31="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1/images/super.img"

hash_extent() {
  local image=$1 offset=$2 length=$3
  dd if="$image" bs=16M skip="$offset" count="$length" \
    iflag=skip_bytes,count_bytes status=none | sha256sum | cut -d' ' -f1
}

printf 'SYSTEM26=%s\n' "$(hash_extent "$s26" 1048576 1061134336)"
printf 'SYSTEM31=%s\n' "$(hash_extent "$s31" 1048576 1061134336)"
printf 'ODM18=%s\n' "$(sha256sum /root/k90_stage18_native/out/odm.img | cut -d' ' -f1)"
printf 'ODM31=%s\n' "$(hash_extent "$s31" 10713300992 1724530688)"
printf 'MY31=%s\n' "$(hash_extent "$s31" 2304770048 1138266112)"
printf 'MY32=%s\n' "$(sha256sum /root/k90_stage32_camera_external_return/out/my_product.img | cut -d' ' -f1)"
