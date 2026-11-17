#!/usr/bin/env bash
set -euo pipefail

base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX/images/super.img

parts=(
  "system:1048576:1061134336"
  "system_ext:1062207488:1087639552"
  "product:2150629376:152326144"
  "my_product:2304770048:1138266112"
  "odm:10713300992:1724530688"
)

for spec in "${parts[@]}"; do
  name=${spec%%:*}
  rest=${spec#*:}
  offset=${rest%%:*}
  size=${rest#*:}
  mount_dir="/mnt/k90_s52_${name}"

  mkdir -p "$mount_dir"
  mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  mount -t erofs -o "ro,loop,offset=$offset,sizelimit=$size" "$base" "$mount_dir"
  echo "=== $name offset=$offset size=$size ==="
  find "$mount_dir" -maxdepth 8 \
    \( -name SystemUI.apk \
    -o -name telephony-common.jar \
    -o -name '*feature*.xml' \
    -o -name '*native*bridge*' \
    -o -name 'k90*bridge*' \
    -o -name 'services.jar' \) \
    -print | sed -n '1,160p'
  umount "$mount_dir"
done
