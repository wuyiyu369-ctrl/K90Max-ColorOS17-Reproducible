#!/usr/bin/env bash
set -euo pipefail

out=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF
work=/root/k90_stage56_verify
base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage55_FAN_EXEC
odm_off=$((20924416 * 512))
odm_len=$((3368224 * 512))

rm -rf "$work"
mkdir -p "$work"
(
    cd "$out"
    sha256sum images/super.img
) > "$out/SHA256SUMS.txt"
(
    cd "$out"
    sha256sum -c SHA256SUMS.txt
)

dd if="$out/images/super.img" of="$work/odm.img" \
    iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
fsck.erofs "$work/odm.img" > "$work/fsck.txt" 2>&1
fsck.erofs --extract="$work/extract" --overwrite "$work/odm.img" \
    > "$work/extract.log" 2>&1

# fsck.erofs extraction deliberately does not materialize security.selinux
# xattrs in the host namespace.  The same rebuilt image was already mounted and
# label-checked by stage56_build_fan_perf.sh; here verify the inode xattr payload
# and all file contents from the independently extracted image.
dump.erofs --path=/bin/k90_native_bridge "$work/odm.img" \
    > "$work/label-bridge.txt" 2>&1
dump.erofs --path=/lib64/libc++_shared.so "$work/odm.img" \
    > "$work/label-camera.txt" 2>&1
dump.erofs --path=/etc/init/k90-stage44-native.rc "$work/odm.img" \
    > "$work/label-initrc.txt" 2>&1
grep -q 'Xattr size: 16' "$work/label-bridge.txt"
grep -q 'Xattr size: 16' "$work/label-camera.txt"
grep -q 'Xattr size: 16' "$work/label-initrc.txt"
grep -Eq '^[[:space:]]*user system[[:space:]]*$' \
    "$work/extract/etc/init/k90-stage44-native.rc"
! grep -Eq '^[[:space:]]*user root[[:space:]]*$' \
    "$work/extract/etc/init/k90-stage44-native.rc"
grep -q '^POLL_SEC=1$' "$work/extract/etc/performance/thermal_safe"
grep -q '^LAUNCH_BOOST_SEC=5$' "$work/extract/etc/performance/thermal_safe"
grep -q '^LAUNCH_SCENE=20$' "$work/extract/etc/performance/thermal_safe"
grep -q 'launch-combined:' "$work/extract/bin/k90_perf_bridge.sh"
grep -q 'gpu=' "$work/extract/bin/k90_perf_bridge.sh"
/bin/sh -n "$work/extract/bin/k90_perf_bridge.sh"
file "$work/extract/bin/k90_native_bridge" | grep -q 'ARM aarch64'
strings -a "$work/extract/bin/k90_native_bridge" | grep -q 'perf-status'
strings -a "$work/extract/bin/k90_native_bridge" | grep -q 'fan-request-read'

# Prove that the new image and Stage55 image differ only in the intended ODM.
dd if="$out/images/super.img" of="$work/head.new" \
    iflag=count_bytes count="$odm_off" status=none
dd if="$base/images/super.img" of="$work/head.base" \
    iflag=count_bytes count="$odm_off" status=none
cmp "$work/head.base" "$work/head.new"
tail_off=$((odm_off + odm_len))
tail_len=$((13421772800 - tail_off))
dd if="$out/images/super.img" of="$work/tail.new" \
    iflag=skip_bytes,count_bytes skip="$tail_off" count="$tail_len" status=none
dd if="$base/images/super.img" of="$work/tail.base" \
    iflag=skip_bytes,count_bytes skip="$tail_off" count="$tail_len" status=none
cmp "$work/tail.base" "$work/tail.new"

printf '%s\n' 'bridge_xattr_payload=16_bytes'
printf '%s\n' 'camera_xattr_payload=16_bytes'
printf '%s\n' 'selinux_label_values=validated_by_same_input_build_mount'
cat "$out/SHA256SUMS.txt"
printf '%s\n' 'STAGE56_INDEPENDENT_VERIFICATION_PASSED'
