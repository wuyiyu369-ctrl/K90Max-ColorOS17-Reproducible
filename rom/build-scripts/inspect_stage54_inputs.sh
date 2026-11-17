#!/usr/bin/env bash
set -euo pipefail

delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
work=/root/stage54_inspect

rm -rf "$work"
mkdir -p "$work"

dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX/images/super.img" \
  of="$work/system49.img" bs=1M skip=1 count=1012 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage52_FAN_AOD_SIM/images/super.img" \
  of="$work/system52.img" bs=1M skip=1 count=1012 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX/images/super.img" \
  of="$work/product49.img" bs=1M skip=2051 count=146 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage53_LABELS_FAN/images/super.img" \
  of="$work/product53.img" bs=1M skip=2051 count=146 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX/images/super.img" \
  of="$work/odm49.img" bs=1M skip=10217 count=1645 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage53_LABELS_FAN/images/super.img" \
  of="$work/odm53.img" bs=1M skip=10217 count=1645 status=none
dd if="$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX/images/super.img" \
  of="$work/my_manifest49.img" bs=512 skip=4499456 count=1152 status=none

sha256sum "$work"/*.img
du -sh "$work"

mkdir -p "$work/my_manifest_mount"
mount -t erofs -o ro,loop "$work/my_manifest49.img" "$work/my_manifest_mount"
fsck.erofs "$work/my_manifest49.img" > "$work/fsck-my_manifest49.txt" 2>&1
find "$work/my_manifest_mount" -maxdepth 2 -type f -printf '%P\n' | sort > "$work/my_manifest_files.txt"
getfattr -n security.selinux --only-values "$work/my_manifest_mount" > "$work/my_manifest_root_label.txt" 2>/dev/null || true
stat -c 'root=%u:%g:%a' "$work/my_manifest_mount" >> "$work/my_manifest_root_label.txt"
cat "$work/my_manifest_files.txt" | head -n 80
cat "$work/my_manifest_root_label.txt"
umount "$work/my_manifest_mount"
