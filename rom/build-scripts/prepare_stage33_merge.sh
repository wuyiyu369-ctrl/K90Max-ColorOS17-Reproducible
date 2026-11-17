#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
s26="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage26_AOD_R1/images/super.img"
s31="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1/images/super.img"
work=/root/k90_stage33_merge

system_offset=1048576
system_size=1061134336
odm_offset=10713300992
odm_size=1724530688

cleanup() {
  for mount_dir in "$work"/mnt_*; do
    mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  done
}
trap cleanup EXIT
cleanup

mkdir -p "$work"/{images,mnt_system26,mnt_system31,mnt_odm18,mnt_odm31,audit}
extract() {
  local source=$1 offset=$2 length=$3 target=$4
  if [[ ! -f "$target" ]] || [[ "$(stat -c%s "$target")" -ne "$length" ]]; then
    rm -f -- "$target"
    dd if="$source" of="$target" bs=16M skip="$offset" count="$length" \
      iflag=skip_bytes,count_bytes status=progress
  fi
}

extract "$s26" "$system_offset" "$system_size" "$work/images/system26.img"
extract "$s31" "$system_offset" "$system_size" "$work/images/system31.img"
extract "$s31" "$odm_offset" "$odm_size" "$work/images/odm31.img"

mount -t erofs -o ro,loop "$work/images/system26.img" "$work/mnt_system26"
mount -t erofs -o ro,loop "$work/images/system31.img" "$work/mnt_system31"
mount -t erofs -o ro,loop /root/k90_stage18_native/out/odm.img "$work/mnt_odm18"
mount -t erofs -o ro,loop "$work/images/odm31.img" "$work/mnt_odm31"

sha256sum \
  "$work/mnt_system26/system/framework/framework.jar" \
  "$work/mnt_system31/system/framework/framework.jar" \
  "$work/mnt_odm18/etc/selinux/odm_sepolicy.cil" \
  "$work/mnt_odm31/etc/selinux/odm_sepolicy.cil" \
  > "$work/audit/relevant-files.sha256"

diff -u \
  "$work/mnt_odm31/etc/selinux/odm_sepolicy.cil" \
  "$work/mnt_odm18/etc/selinux/odm_sepolicy.cil" \
  > "$work/audit/odm-policy.diff" || true

for source in system26 system31; do
  unzip -l "$work/mnt_${source}/system/framework/framework.jar" \
    > "$work/audit/${source}-framework-files.txt"
done
diff -u "$work/audit/system31-framework-files.txt" \
  "$work/audit/system26-framework-files.txt" \
  > "$work/audit/framework-file-list.diff" || true

cat "$work/audit/relevant-files.sha256"
echo STAGE33_MERGE_INPUTS_READY
