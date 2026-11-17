#!/usr/bin/env bash
set -euo pipefail
OUT=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage24_SMS_NATIVE/images/super.img
rm -f /root/system.img
dd if="$OUT" of=/root/system.img bs=4096 skip=2048 count=259066 status=progress
python3 /mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py verify_image --image /root/system.img
fsck.erofs /root/system.img
echo VERIFY_OK
