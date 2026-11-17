#!/usr/bin/env bash
set -euo pipefail
img=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage25_perf/final_extract/system_a_a.img
mnt=/root/k90_stage25_scan
mkdir -p "$mnt"
mountpoint -q "$mnt" && umount "$mnt" || true
mount -t erofs -o ro,loop "$img" "$mnt"
trap 'umount "$mnt" 2>/dev/null || true' EXIT
grep -R -a -l -F 'vendor.oplus.hardware.urcc.IUrcc' \
  "$mnt/system/framework" "$mnt/system/lib64" "$mnt/system/lib" \
  "$mnt/system/app" "$mnt/system/priv-app" 2>/dev/null | head -200
