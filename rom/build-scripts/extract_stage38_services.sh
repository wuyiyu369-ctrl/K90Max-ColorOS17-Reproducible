#!/usr/bin/env bash
set -euo pipefail

mount_dir=/mnt/k90_stage38_system
super=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img
output=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/device_policy_20261106/services_stage38.jar

mkdir -p "$mount_dir"
mountpoint -q "$mount_dir" && umount "$mount_dir"
mount -t erofs -o ro,loop,offset=$((256 * 4096)),sizelimit=1061134336 \
  "$super" "$mount_dir"
cp "$mount_dir/system/framework/services.jar" "$output"
sha256sum "$mount_dir/system/framework/services.jar"
ls -lh "$mount_dir/system/framework/services.jar"
umount "$mount_dir"
