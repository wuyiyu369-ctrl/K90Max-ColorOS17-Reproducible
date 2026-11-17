#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery
base=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage55_FAN_EXEC
out=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF
work=/root/k90_stage56_work
overlay=/root/k90_stage56_overlay
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64

# Exact Stage53/55 super metadata extents.
odm_off=$((20924416 * 512))
odm_len=$((3368224 * 512))
super_len=13421772800

need_file() { test -s "$1" || { echo "MISSING: $1" >&2; exit 1; }; }
need_file "$base/images/super.img"
need_file "$src/stage44_native_bridge.c"
need_file "$src/stage44_payload/k90-stage44-native.rc"
need_file "$src/stage48_perf_bridge.sh"
need_file "$src/generate_erofs_file_contexts.py"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_len"
grep -q '^[[:space:]]*user system$' "$src/stage44_payload/k90-stage44-native.rc"
! grep -q '^[[:space:]]*user root$' "$src/stage44_payload/k90-stage44-native.rc"
/bin/sh -n "$src/stage48_perf_bridge.sh"

mkdir -p "$out/images" "$out/audit"
test ! -e "$out/images/super.img"
rm -rf "$work" "$overlay"
mkdir -p "$work" "$overlay"/{odm,odm.upper,odm.work,odm.merged,verify}

cleanup() {
  for m in "$overlay/verify" "$overlay/odm.merged" "$overlay/odm"; do
    mountpoint -q "$m" && umount "$m" || true
  done
}
trap cleanup EXIT

# Extract the ODM from the current, booted Stage55 baseline.  No older Stage
# supplies bytes to this build.
dd if="$base/images/super.img" of="$work/odm.base.img" \
  iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
test "$(stat -c%s "$work/odm.base.img")" -eq "$odm_len"
fsck.erofs "$work/odm.base.img" > "$work/fsck-odm-base.txt" 2>&1

# Recompile the native bridge from the checked source and run its host policy
# tests before any image is assembled.
"$ndk/bin/clang" -O2 -Wall -Wextra -Werror \
  -o "$work/bridge-host" "$src/stage44_native_bridge.c" -ldl
"$work/bridge-host" --self-test
"$ndk/bin/aarch64-linux-android34-clang" -O2 -Wall -Wextra -Werror \
  -fPIE -pie -D__ANDROID__ \
  -o "$work/k90_native_bridge" "$src/stage44_native_bridge.c" -llog -ldl
"$ndk/bin/llvm-readelf" -h "$work/k90_native_bridge" > "$work/bridge.readelf-header.txt"
"$ndk/bin/llvm-readelf" -d "$work/k90_native_bridge" > "$work/bridge.readelf-dynamic.txt"
grep -q 'Machine:.*AArch64' "$work/bridge.readelf-header.txt"
grep -q 'Shared library: \[liblog.so\]' "$work/bridge.readelf-dynamic.txt"
grep -q 'Shared library: \[libdl.so\]' "$work/bridge.readelf-dynamic.txt"
strings -a "$work/k90_native_bridge" | grep -q 'perf-status'
strings -a "$work/k90_native_bridge" | grep -q 'fan-request-read'

mount -t erofs -o ro,loop "$work/odm.base.img" "$overlay/odm"
root_label=$(getfattr -n security.selinux --only-values "$overlay/odm" 2>/dev/null)
test -n "$root_label"
setfattr -n security.selinux -v "$root_label" "$overlay/odm.upper"

mkdir -p "$overlay/odm.upper/bin" "$overlay/odm.upper/etc/init" \
  "$overlay/odm.upper/etc/performance" "$overlay/odm.upper/lib64"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm.upper/bin"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm.upper/lib64"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/odm.upper/etc" "$overlay/odm.upper/etc/init" \
  "$overlay/odm.upper/etc/performance"

# Four intended runtime changes:
#   1. native bridge binary with fan diagnostics + UniPerf/CPU readback;
#   2. native bridge starts as UID system, matching the request mailbox;
#   3. performance bridge combines short sconfig launch relief with UniPerf;
#   4. immutable defaults use a one-second decision loop and five-second burst.
install -m 0755 "$work/k90_native_bridge" "$overlay/odm.upper/bin/k90_native_bridge"
install -m 0644 "$src/stage44_payload/k90-stage44-native.rc" \
  "$overlay/odm.upper/etc/init/k90-stage44-native.rc"

cp -a "$overlay/odm/bin/k90_perf_bridge.sh" \
  "$overlay/odm.upper/bin/k90_perf_bridge.sh"
cp "$src/stage48_perf_bridge.sh" "$overlay/odm.upper/bin/k90_perf_bridge.sh"
chmod --reference="$overlay/odm/bin/k90_perf_bridge.sh" \
  "$overlay/odm.upper/bin/k90_perf_bridge.sh"
chown --reference="$overlay/odm/bin/k90_perf_bridge.sh" \
  "$overlay/odm.upper/bin/k90_perf_bridge.sh"

cp -a "$overlay/odm/etc/performance/thermal_safe" \
  "$overlay/odm.upper/etc/performance/thermal_safe"
sed -i 's/^[[:space:]]*POLL_SEC=.*/POLL_SEC=1/' \
  "$overlay/odm.upper/etc/performance/thermal_safe"
sed -i 's/^[[:space:]]*LAUNCH_BOOST_SEC=.*/LAUNCH_BOOST_SEC=5/' \
  "$overlay/odm.upper/etc/performance/thermal_safe"
if grep -q '^[[:space:]]*LAUNCH_SCENE=' "$overlay/odm.upper/etc/performance/thermal_safe"; then
  sed -i 's/^[[:space:]]*LAUNCH_SCENE=.*/LAUNCH_SCENE=20/' \
    "$overlay/odm.upper/etc/performance/thermal_safe"
else
  sed -i '/^[[:space:]]*LAUNCH_BOOST_SEC=/a LAUNCH_SCENE=20' \
    "$overlay/odm.upper/etc/performance/thermal_safe"
fi

setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/odm.upper/bin/k90_native_bridge"
perf_label=$(getfattr -n security.selinux --only-values \
  "$overlay/odm/bin/k90_perf_bridge.sh" 2>/dev/null)
test -n "$perf_label"
setfattr -n security.selinux -v "$perf_label" \
  "$overlay/odm.upper/bin/k90_perf_bridge.sh"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/odm.upper/etc/init/k90-stage44-native.rc" \
  "$overlay/odm.upper/etc/performance/thermal_safe"

# Keep the Stage55 camera/linker regression fix explicit in the rebuilt inode.
cp -a "$overlay/odm/lib64/libc++_shared.so" \
  "$overlay/odm.upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm.upper/lib64/libc++_shared.so"

mount -t overlay overlay \
  -o "lowerdir=$overlay/odm,upperdir=$overlay/odm.upper,workdir=$overlay/odm.work" \
  "$overlay/odm.merged"

o_uuid=$(blkid -o value -s UUID "$work/odm.base.img")
o_label=$(blkid -o value -s LABEL "$work/odm.base.img" || true)
o_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$o_uuid" --preserve-mtime)
[[ -z "$o_label" ]] || o_args+=(-L "$o_label")
python3 "$src/generate_erofs_file_contexts.py" "$overlay/odm.merged" /odm \
  "$work/odm.file-contexts" \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/bin/k90_native_bridge=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/etc/init/k90-stage44-native.rc=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/performance/thermal_safe=u:object_r:vendor_configs_file:s0 \
  > "$work/odm.contexts.log"
o_args+=(--mount-point=/odm --file-contexts="$work/odm.file-contexts")
mkfs.erofs "${o_args[@]}" "$work/odm.raw.img" "$overlay/odm.merged" \
  > "$work/odm.mkfs.log" 2>&1
test "$(stat -c%s "$work/odm.raw.img")" -le "$odm_len"
cp --sparse=always "$work/odm.raw.img" "$work/odm.img"
truncate -s "$odm_len" "$work/odm.img"
umount "$overlay/odm.merged"
umount "$overlay/odm"

# Full readback validation of the rebuilt ODM.
fsck.erofs "$work/odm.img" > "$work/fsck-odm.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.img" "$overlay/verify"
cmp "$work/k90_native_bridge" "$overlay/verify/bin/k90_native_bridge"
cmp "$src/stage48_perf_bridge.sh" "$overlay/verify/bin/k90_perf_bridge.sh"
cmp "$src/stage44_payload/k90-stage44-native.rc" \
  "$overlay/verify/etc/init/k90-stage44-native.rc"
/bin/sh -n "$overlay/verify/bin/k90_perf_bridge.sh"
grep -q '^[[:space:]]*user system$' \
  "$overlay/verify/etc/init/k90-stage44-native.rc"
! grep -q '^[[:space:]]*user root$' \
  "$overlay/verify/etc/init/k90-stage44-native.rc"
grep -q '^POLL_SEC=1$' "$overlay/verify/etc/performance/thermal_safe"
grep -q '^LAUNCH_BOOST_SEC=5$' "$overlay/verify/etc/performance/thermal_safe"
grep -q '^LAUNCH_SCENE=20$' "$overlay/verify/etc/performance/thermal_safe"
grep -q 'launch-combined:' "$overlay/verify/bin/k90_perf_bridge.sh"
grep -q 'gpu=' "$overlay/verify/bin/k90_perf_bridge.sh"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/k90_native_bridge")" = u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0

# Require every regular file and directory in ODM to carry a SELinux label.
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/missing-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

# Assemble from Stage55 and prove every byte outside ODM is unchanged.
building="$out/images/super.img.building"
rm -f "$building"
cp --sparse=always "$base/images/super.img" "$building"
dd if="$work/odm.img" of="$building" bs=4096 \
  seek=$((odm_off / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_len"

cmp -n "$odm_off" "$base/images/super.img" "$building"
tail_off=$((odm_off + odm_len))
tail_len=$((super_len - tail_off))
cmp -n "$tail_len" -i "$tail_off:$tail_off" \
  "$base/images/super.img" "$building"

dd if="$building" of="$work/odm.readback.img" \
  iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
cmp "$work/odm.img" "$work/odm.readback.img"
fsck.erofs "$work/odm.readback.img" > "$work/fsck-odm-readback.txt" 2>&1
mv "$building" "$out/images/super.img"

cp -a "$base/platform-tools" "$out/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$out/"
cp "$work/"*.txt "$work/"*.log "$work/"*.readelf-* "$out/audit/" 2>/dev/null || true
(
  cd "$out"
  sha256sum images/super.img
) > "$out/SHA256SUMS.txt"
sha256sum "$work/odm.img" "$work/k90_native_bridge" \
  "$src/stage48_perf_bridge.sh" > "$out/audit/component-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage56 fan + performance scheduling candidate
Base: currently booted Stage55 image
Changed partition: ODM only
Data wipe: no

Fan:
- Native bridge UID changed from root to system.
- Matches /data/system/k90fan.request owner/mode system:system 0600.
- Avoids broad dac_override/dac_read_search capabilities.

Scheduling:
- Xiaomi UniPerf launch hint remains enabled.
- Non-game app transitions temporarily select sconfig 20 for five seconds.
- Games remain mapped to Xiaomi scenes 18/19/20 by package.
- Screen-off, high temperature, exit and unmatched idle restore vendor auto.
- CPU three-cluster current/max, scene, foreground and temperature are logged.
- GPU/DDR/UFS readback is attempted from the real MTK devfreq/GED nodes; a
  question mark means that node still needs a narrow read-only SELinux rule.

Validation:
- Native host policy self-test passed.
- Rebuilt ODM fsck passed.
- Every regular file/directory in rebuilt ODM has a SELinux label.
- Camera-critical odm/lib64/libc++_shared.so remains vendor_file.
- All bytes outside the ODM extent are identical to Stage55.

Runtime fan, launch/game scheduling, GPU/DDR/UFS readback and camera smoke tests
must still be performed after keep-data flashing.  This package does not touch
boot, init_boot, modem, persist, nvdata, nvcfg, protect*, or preloader.
EOF

cat > "$out/audit/CHANGES.txt" <<'EOF'
1. Fix fan mailbox access by running the native bridge as UID system.
2. Keep Xiaomi UniPerf and combine it with short sconfig launch relief.
3. Preserve persistent game scenes with 45C safety fallback.
4. Add observable foreground, scene, CPU cluster, GPU, DDR and UFS status.
5. Rebuild only ODM from Stage55; preserve all other super extents byte-for-byte.
6. Preserve the Stage55 camera/linker SELinux label repair.
EOF

echo STAGE56_OFFLINE_BUILD_PASSED
