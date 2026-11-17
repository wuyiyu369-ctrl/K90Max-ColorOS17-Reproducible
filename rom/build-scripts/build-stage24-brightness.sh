#!/bin/bash
set -euo pipefail

# Stage24: patch only the system_ext brightness table on top of the bootable
# Stage23 super image. No boot chain, modem, persist, userdata, or metadata is
# touched.
BASE=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage23_SCAN_BRIGHTNESS/images/super.img
W=/root/k90_stage24_brightness
EXT_OFF=1062207488
EXT_LEN=1087639552
UUID=4f4ca8f2-b540-519e-9d46-3e1c3a32a921

mkdir -p "$W"
rm -rf "$W"/lower "$W"/upper "$W"/work "$W"/merged "$W"/out
mkdir -p "$W"/{lower,upper,work,merged,out}

# The Windows side extracts the extent quickly before this script is run. The
# fallback keeps the script reproducible when the extent is not present.
if [ ! -f "$W/system_ext.base.img" ]; then
  dd if="$BASE" of="$W/system_ext.base.img" bs=4096 skip=$((EXT_OFF/4096)) count=$((EXT_LEN/4096)) status=progress
fi

mount -t erofs -o loop,ro "$W/system_ext.base.img" "$W/lower"
mount -t overlay overlay -o "lowerdir=$W/lower,upperdir=$W/upper,workdir=$W/work" "$W/merged"
trap 'umount "$W/merged" 2>/dev/null || true; umount "$W/lower" 2>/dev/null || true' EXIT

CFG="$W/merged/etc/display_brightness_config_default.xml"
grep -q '<brightness_table max="8191" min="222">' "$CFG"
mkdir -p "$W/upper/etc"
sed -i 's/<brightness_table max="8191" min="222">/<brightness_table max="8191" min="5">/' "$CFG"
grep -q '<brightness_table max="8191" min="5">' "$W/merged/etc/display_brightness_config_default.xml"

# OverlayFS does not inherit the lower filesystem root xattr onto the merged
# mount root.  Rebuilding EROFS without this label produced a statically valid
# image that failed during early Android boot.  Restore and verify it before
# mkfs; do not rely on fsck.erofs alone for SELinux metadata validation.
setfattr -n security.selinux -v 'u:object_r:system_file:s0' "$W/merged"
test "$(getfattr --only-values -n security.selinux "$W/merged")" = 'u:object_r:system_file:s0'

mkfs.erofs -z lz4hc,12 -C 16384 -U "$UUID" --preserve-mtime \
  "$W/out/system_ext.raw.img" "$W/merged" > "$W/mkfs.log" 2>&1
test "$(stat -c %s "$W/out/system_ext.raw.img")" -le "$EXT_LEN"
cp --sparse=always "$W/out/system_ext.raw.img" "$W/out/system_ext.img"
truncate -s "$EXT_LEN" "$W/out/system_ext.img"
fsck.erofs "$W/out/system_ext.img" > "$W/fsck.log" 2>&1
mkdir -p "$W/out-check"
mount -t erofs -o loop,ro "$W/out/system_ext.img" "$W/out-check"
test "$(getfattr --only-values -n security.selinux "$W/out-check")" = 'u:object_r:system_file:s0'
umount "$W/out-check"
sha256sum "$W/out/system_ext.img" > "$W/SHA256SUMS.txt"
echo STAGE24_BRIGHTNESS_SYSTEM_EXT_DONE
