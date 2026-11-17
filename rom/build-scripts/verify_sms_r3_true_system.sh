#!/usr/bin/env bash
set -euo pipefail

img=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/sms_r3_final_extract/system_a_a.img
avb_img=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/sms_r3_final_extract/system.img
candidate=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/sms_native_r3/telephony-common.native-sms-r3.jar
work=/root/k90_sms_r3_true_verify
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

for f in "$img" "$candidate" "$avb"; do test -f "$f"; done
rm -rf "$work"
mkdir -p "$work/mount"
ln -sf "$(basename "$img")" "$avb_img"
python3 "$avb" verify_image --image "$avb_img" > "$work/avb.txt"
fsck.erofs "$img" > "$work/fsck.txt" 2>&1
! grep -Eqi 'bogus|corruption|error|failed' "$work/fsck.txt"
dump.erofs -s "$img" > "$work/superblock.txt"
grep -q 'Filesystem UUID:.*212ef468-c526-563b-babf-8465c924ade4' "$work/superblock.txt"
grep -q 'Filesystem created:.*Oct  6 16:58:45 2026' "$work/superblock.txt"
mount -t erofs -o ro,loop "$img" "$work/mount"
trap 'umount "$work/mount" 2>/dev/null || true' EXIT
test "$(getfattr -n security.selinux --only-values "$work/mount" 2>/dev/null)" = 'u:object_r:rootfs:s0'
test "$(getfattr -n security.selinux --only-values "$work/mount/system/framework/telephony-common.jar" 2>/dev/null)" = 'u:object_r:system_file:s0'
test "$(sha256sum "$work/mount/system/framework/telephony-common.jar" | cut -d' ' -f1)" = "$(sha256sum "$candidate" | cut -d' ' -f1)"
stat -c '%u:%g %a %n' "$work/mount" "$work/mount/system/framework/telephony-common.jar" > "$work/stat.txt"
sha256sum "$img" "$work/mount/system/framework/telephony-common.jar" > "$work/SHA256SUMS.txt"
echo TRUE_SYSTEM_R3_VERIFY_OK
