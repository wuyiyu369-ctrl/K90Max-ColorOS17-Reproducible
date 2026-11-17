#!/usr/bin/env bash
set -euo pipefail

img=/root/k90_stage59_work/out/odm.readback.img
mount_root=/root/k90_stage59_independent_mount
report=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage59_MISC_FAN/audit/INDEPENDENT_AUDIT.txt

test -s "$img"
mkdir -p "$mount_root"
mountpoint -q "$mount_root" && umount "$mount_root" || true
fsck.erofs "$img" > /tmp/stage59-independent-fsck.txt 2>&1
mount -t erofs -o ro,loop "$img" "$mount_root"
cleanup() { mountpoint -q "$mount_root" && umount "$mount_root" || true; }
trap cleanup EXIT

grep -Fx 'vendor.oplus.hardware.misc.IOplusMisc/default u:object_r:hal_power_service:s0' \
  "$mount_root/etc/selinux/odm_service_contexts"
grep -Fq 'service k90-oplus-misc-fan /odm/bin/k90_oplus_misc_fan' \
  "$mount_root/etc/init/k90-misc-fan.rc"
grep -Fq '<fqname>IOplusMisc/default</fqname>' \
  "$mount_root/etc/vintf/manifest/manifest_k90_misc_fan.xml"
if command -v xmllint >/dev/null; then
  xmllint --noout "$mount_root/etc/vintf/manifest/manifest_k90_misc_fan.xml"
fi

test "$(getfattr -n security.selinux --only-values "$mount_root/bin/k90_oplus_misc_fan")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$mount_root/bin/k90_native_bridge")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$mount_root/lib64/libc++_shared.so")" = \
  u:object_r:vendor_file:s0

missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf 'MISSING_LABEL %s\n' "$item" >&2
    missing=$((missing + 1))
  fi
done < <(find "$mount_root" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0

cat > "$report" <<'EOF'
Stage59 independent audit: PASSED
- Final super readback ODM EROFS fsck: passed
- IOplusMisc service context: exact match
- Init service and VINTF declaration: present
- New service and legacy bridge executable labels: correct
- Camera-critical libc++_shared.so label: vendor_file
- Missing SELinux labels across ODM files/directories: 0
- Binary dependency and final readback cmp: passed separately
EOF

echo INDEPENDENT_ODM_AUDIT_PASSED
