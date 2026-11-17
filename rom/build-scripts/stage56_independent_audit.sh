#!/usr/bin/env bash
set -euo pipefail

delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
stage55=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage55_FAN_EXEC
stage56=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF
mount55=/root/k90_stage56_audit/stage55
mount56=/root/k90_stage56_audit/stage56
odm_offset=$((20924416 * 512))
odm_length=$((3368224 * 512))
expected_super=3037215052f11be72f49cff526fafbc6d3ffeef8d6ce029279dcd0626311640b
expected_bridge=eed32cd0d067ab2d5f4b3e4d009a732233bd8213f3900f2e389b438b8fe421e5
expected_perf=3ba4823d1d10535ec84f5cf3503cfb906c272423ae2fb78715ff60d3cd76819f

loop55=
loop56=
cleanup() {
    mountpoint -q "$mount55" && umount "$mount55" || true
    mountpoint -q "$mount56" && umount "$mount56" || true
    [[ -z "$loop55" ]] || losetup -d "$loop55" || true
    [[ -z "$loop56" ]] || losetup -d "$loop56" || true
}
trap cleanup EXIT

test -s "$stage55/images/super.img"
test -s "$stage56/images/super.img"
test "$(stat -c%s "$stage56/images/super.img")" -eq 13421772800
actual_super=$(sha256sum "$stage56/images/super.img" | awk '{print $1}')
test "$actual_super" = "$expected_super"
printf '%s  images/super.img\n' "$actual_super" > "$stage56/SHA256SUMS.txt"

rm -rf /root/k90_stage56_audit
mkdir -p "$mount55" "$mount56"
loop55=$(losetup --find --show --read-only --offset "$odm_offset" \
    --sizelimit "$odm_length" "$stage55/images/super.img")
loop56=$(losetup --find --show --read-only --offset "$odm_offset" \
    --sizelimit "$odm_length" "$stage56/images/super.img")
fsck.erofs "$loop55" > /root/k90_stage56_audit/fsck-stage55.txt 2>&1
fsck.erofs "$loop56" > /root/k90_stage56_audit/fsck-stage56.txt 2>&1
mount -t erofs -o ro "$loop55" "$mount55"
mount -t erofs -o ro "$loop56" "$mount56"

test "$(getfattr -n security.selinux --only-values "$mount56/bin/k90_native_bridge" 2>/dev/null)" \
    = u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$mount56/lib64/libc++_shared.so" 2>/dev/null)" \
    = u:object_r:vendor_file:s0
test "$(getfattr -n security.selinux --only-values "$mount56/etc/init/k90-stage44-native.rc" 2>/dev/null)" \
    = u:object_r:vendor_configs_file:s0
grep -Eq '^[[:space:]]*user system[[:space:]]*$' "$mount56/etc/init/k90-stage44-native.rc"
! grep -Eq '^[[:space:]]*user root[[:space:]]*$' "$mount56/etc/init/k90-stage44-native.rc"
grep -q '^POLL_SEC=1$' "$mount56/etc/performance/thermal_safe"
grep -q '^LAUNCH_BOOST_SEC=5$' "$mount56/etc/performance/thermal_safe"
grep -q '^LAUNCH_SCENE=20$' "$mount56/etc/performance/thermal_safe"
grep -q 'launch-combined:' "$mount56/bin/k90_perf_bridge.sh"
/bin/sh -n "$mount56/bin/k90_perf_bridge.sh"
strings -a "$mount56/bin/k90_native_bridge" | grep -q 'fan-request-read'
strings -a "$mount56/bin/k90_native_bridge" | grep -q 'perf-status'
test "$(sha256sum "$mount56/bin/k90_native_bridge" | awk '{print $1}')" = "$expected_bridge"
test "$(sha256sum "$mount56/bin/k90_perf_bridge.sh" | awk '{print $1}')" = "$expected_perf"

# Camera and policy inputs must remain byte-identical to the booted Stage55.
cmp "$mount55/lib64/libc++_shared.so" "$mount56/lib64/libc++_shared.so"
cmp "$mount55/etc/selinux/precompiled_sepolicy" "$mount56/etc/selinux/precompiled_sepolicy"
cmp "$mount55/etc/selinux/odm_sepolicy.cil" "$mount56/etc/selinux/odm_sepolicy.cil"
cmp "$mount55/etc/camera/cameraopt_perf.json" "$mount56/etc/camera/cameraopt_perf.json"

cat > "$stage56/INDEPENDENT_AUDIT.txt" <<EOF
AUDIT_OK
Stage56 independent audit passed on 2026-11-08.
super_sha256=$actual_super
odm_fsck=passed
bridge_uid=system
bridge_selinux=u:object_r:vendor_touch_init_shell_exec:s0
camera_lib_selinux=u:object_r:vendor_file:s0
launch_scene=20
launch_boost_seconds=5
stage55_camera_and_policy_inputs=byte_identical
EOF

echo STAGE56_INDEPENDENT_AUDIT_PASSED
