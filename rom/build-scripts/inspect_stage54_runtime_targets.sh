#!/usr/bin/env bash
set -euo pipefail

work=/root/stage54_inspect
odm="$work/odm53.img"
product="$work/product53.img"
mount_root="$work/runtime_mount"

mkdir -p "$mount_root"

mount -t erofs -o ro,loop "$odm" "$mount_root"
echo 'ODM_LIBCXX_SHARED'
find "$mount_root" -xdev -type f -name 'libc++_shared.so' -printf '%i %p\n' 2>/dev/null || true
for f in "$mount_root/lib64/libc++_shared.so" "$mount_root/lib/libc++_shared.so"; do
  if [ -e "$f" ]; then
    echo "PATH=$f"
    stat -c 'inode=%i mode=%a uid=%u gid=%g' "$f"
    getfattr -n security.selinux --only-values "$f" 2>/dev/null || true
    echo
  fi
done
echo 'ODM_BRIDGES'
for f in \
  "$mount_root/bin/k90_native_bridge" \
  "$mount_root/bin/k90_perf_bridge.sh" \
  "$mount_root/bin/k90-charge-daemon.sh" \
  "$mount_root/bin/vendor.oplus.hardware.charger-V11-service"; do
  if [ -e "$f" ]; then
    echo "PATH=$f"
    stat -c 'inode=%i mode=%a uid=%u gid=%g' "$f"
    getfattr -n security.selinux --only-values "$f" 2>/dev/null || true
    echo
  fi
done
echo 'ODM_FILE_CONTEXTS_MATCHES'
grep -n -E 'libc\+\+_shared|k90_native_bridge|k90_perf_bridge|k90-charge-daemon|charger-V11' \
  "$mount_root/etc/selinux/odm_file_contexts" || true
echo 'ODM_POLICY_MATCHES'
grep -n -E 'IPerformance|IUrcc|uniperf|mipower|xiaomi_fan|thermal_message|perfserv' \
  "$mount_root/etc/selinux/odm_sepolicy.cil" | head -n 150 || true
umount "$mount_root"

mount -t erofs -o ro,loop "$product" "$mount_root"
echo 'PRODUCT_FAN_FEATURE'
for f in \
  "$mount_root/etc/permissions/oplus.feature.android.xml" \
  "$mount_root/etc/build.prop" \
  "$mount_root/etc/init/k90-user-names.rc"; do
  if [ -e "$f" ]; then
    echo "PATH=$f"
    grep -n -E 'fan|ro.product.model|marketname|bt_name|wifi_ap|device_name' "$f" || true
    stat -c 'inode=%i mode=%a uid=%u gid=%g' "$f"
    getfattr -n security.selinux --only-values "$f" 2>/dev/null || true
    echo
  fi
done
umount "$mount_root"
