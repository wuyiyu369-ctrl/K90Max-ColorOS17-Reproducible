#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
root17=$root/01_主工程/K90_A17_PORT_WORK
delivery=$root17/delivery
base=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage56_FAN_PERF
out=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage57_FAN_CONTROL_FIX
work=/root/k90_stage57_work
overlay=/root/k90_stage57_overlay
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py
jar=$src/_fan_live_services_stage57/services.stage57.jar

system_offset=1048576
system_size=1049554944
system_partition_size=1061134336
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
super_size=13421772800

need_file() {
  test -s "$1" || { echo "MISSING: $1" >&2; exit 1; }
}
need_file "$base/images/super.img"
need_file "$jar"
need_file "$src/stage44_native_bridge.c"
need_file "$src/generate_erofs_file_contexts.py"
need_file "$avb"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
base_hash_expected=3037215052f11be72f49cff526fafbc6d3ffeef8d6ce029279dcd0626311640b
base_hash_marker=/root/k90_stage57_stage56_base_verified_$base_hash_expected
if [[ ! -f "$base_hash_marker" ]]; then
  base_hash=$(sha256sum "$base/images/super.img" | cut -d' ' -f1)
  test "$base_hash" = "$base_hash_expected" \
    || { echo "STAGE56_BASE_HASH_FAILED: $base_hash" >&2; exit 1; }
  touch "$base_hash_marker"
fi
grep -q '^STAGE57_SERVICES_BUILD_PASSED$' \
  "$src/_fan_live_services_stage57/stage57_services_audit.txt"

rm -rf "$work" "$overlay"
mkdir -p "$work/out" "$out/images" "$out/audit"
mkdir -p "$overlay"/{system_lower,system_upper,system_work,system_merged,odm_lower,odm_upper,odm_work,odm_merged,verify}

cleanup() {
  for mount_name in verify system_merged system_lower odm_merged odm_lower; do
    mountpoint -q "$overlay/$mount_name" && umount "$overlay/$mount_name" || true
  done
}
trap cleanup EXIT

# Extract the exact Stage56 system partition and prove the full EROFS + AVB
# container is intact.  The super extent for system_a_a is only the file-system
# payload; the final system_partition_size includes its AVB footer.
dd if="$base/images/super.img" of="$work/out/system.base.img" \
  bs=16M iflag=skip_bytes,count_bytes skip="$system_offset" \
  count="$system_partition_size" status=none
test "$(stat -c%s "$work/out/system.base.img")" -eq "$system_partition_size"
fsck.erofs "$work/out/system.base.img" > "$work/out/fsck-system-base.txt" 2>&1
python3 "$avb" info_image --image "$work/out/system.base.img" \
  > "$work/out/avb-system-base.txt" 2>&1
# info_image is the authoritative baseline check here. avbtool verify_image
# resolves the descriptor partition name to a sibling file named system.img;
# the baseline is intentionally named system.base.img and is not verified via
# that filename to avoid accidentally checking a different sibling image.

mount -t erofs -o ro,loop "$work/out/system.base.img" "$overlay/system_lower"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/system_lower/system/framework/services.jar")" = u:object_r:system_file:s0
base_jar_hash=$(sha256sum "$overlay/system_lower/system/framework/services.jar" | cut -d' ' -f1)
test "$base_jar_hash" = 291529e31adc298f6aa4ae0133fabef4f01bfebdbc23d20128d59feda27fee88

system_root_label=$(getfattr -n security.selinux --only-values "$overlay/system_lower")
setfattr -n security.selinux -v "$system_root_label" "$overlay/system_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/system_lower,upperdir=$overlay/system_upper,workdir=$overlay/system_work" \
  "$overlay/system_merged"

cp "$jar" "$overlay/system_merged/system/framework/services.jar"
cp --attributes-only --preserve=all \
  "$overlay/system_lower/system/framework/services.jar" \
  "$overlay/system_upper/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/system_merged/system/framework/services.jar")" = u:object_r:system_file:s0
test "$(stat -c %u:%g:%a "$overlay/system_merged/system/framework/services.jar")" = \
  "$(stat -c %u:%g:%a "$overlay/system_lower/system/framework/services.jar")"

python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/system_merged" /system "$work/out/system_file_contexts.generated" \
  --override /system/my_reserve=u:object_r:system_file:s0 \
  > "$work/out/system-file-contexts-generation.txt"
system_uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
system_label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
system_args=(-z lz4hc,12 -C 16384 -T 1791287125 -U "$system_uuid" --preserve-mtime)
[[ -z "$system_label" ]] || system_args+=(-L "$system_label")
system_args+=(
  --mount-point=/system
  --file-contexts="$work/out/system_file_contexts.generated"
)
mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" \
  "$overlay/system_merged" > "$work/out/mkfs-system.log" 2>&1
test "$(stat -c%s "$work/out/system.raw.img")" -le "$system_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_size" "$work/out/system.img"

# Recreate the same unencrypted AVB hashtree container used by the booted
# Stage56 system image.  This changes no rollback index and adds no signing key.
python3 "$avb" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_partition_size" --partition_name system \
  --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
  --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
test "$(stat -c%s "$work/out/system.img")" -eq "$system_partition_size"
python3 "$avb" verify_image --image "$work/out/system.img" \
  > "$work/out/avb-system.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1

umount "$overlay/system_merged"
umount "$overlay/system_lower"
mount -t erofs -o ro,loop "$work/out/system.img" "$overlay/verify"
cmp "$jar" "$overlay/verify/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/system/framework/services.jar")" = u:object_r:system_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify")" = "$system_root_label"

missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-system-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

# Compile the native bridge with the new custom 1..8 mapping and run the host
# policy self-test before installing it into ODM.
"$ndk/bin/clang" -O2 -Wall -Wextra -Werror \
  -o "$work/out/bridge-host" "$src/stage44_native_bridge.c" -ldl
"$work/out/bridge-host" --self-test | tee "$work/out/bridge-self-test.txt"
"$ndk/bin/aarch64-linux-android34-clang" -O2 -Wall -Wextra -Werror \
  -fPIE -pie -D__ANDROID__ \
  -o "$work/out/k90_native_bridge" "$src/stage44_native_bridge.c" -llog -ldl
"$ndk/bin/llvm-readelf" -h "$work/out/k90_native_bridge" \
  > "$work/out/bridge.readelf-header.txt"
"$ndk/bin/llvm-readelf" -d "$work/out/k90_native_bridge" \
  > "$work/out/bridge.readelf-dynamic.txt"
grep -q 'Machine:.*AArch64' "$work/out/bridge.readelf-header.txt"
grep -q 'Shared library: \[liblog.so\]' "$work/out/bridge.readelf-dynamic.txt"

dd if="$base/images/super.img" of="$work/out/odm.base.img" \
  bs=16M iflag=skip_bytes,count_bytes skip="$odm_offset" \
  count="$odm_size" status=none
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/odm_lower"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/odm_lower/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
odm_root_label=$(getfattr -n security.selinux --only-values "$overlay/odm_lower")
setfattr -n security.selinux -v "$odm_root_label" "$overlay/odm_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" \
  "$overlay/odm_merged"

mkdir -p "$overlay/odm_upper/bin" "$overlay/odm_upper/lib64"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm_upper/bin" "$overlay/odm_upper/lib64"
cp -a "$overlay/odm_lower/bin/k90_native_bridge" \
  "$overlay/odm_upper/bin/k90_native_bridge"
cp "$work/out/k90_native_bridge" \
  "$overlay/odm_merged/bin/k90_native_bridge"
cp --attributes-only --preserve=all \
  "$overlay/odm_lower/bin/k90_native_bridge" \
  "$overlay/odm_upper/bin/k90_native_bridge"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/odm_upper/bin/k90_native_bridge"

# Preserve the Stage56 camera/linker repair explicitly while touching ODM.
cp -a "$overlay/odm_lower/lib64/libc++_shared.so" \
  "$overlay/odm_upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm_upper/lib64/libc++_shared.so"

python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/odm_merged" /odm "$work/out/odm_file_contexts.generated" \
  --override /odm/bin/k90_native_bridge=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  > "$work/out/odm-file-contexts-generation.txt"
odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime)
[[ -z "$odm_label" ]] || odm_args+=(-L "$odm_label")
odm_args+=(
  --mount-point=/odm
  --file-contexts="$work/out/odm_file_contexts.generated"
)
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" \
  "$overlay/odm_merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/odm_merged"
umount "$overlay/odm_lower"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
cmp "$work/out/k90_native_bridge" "$overlay/verify/bin/k90_native_bridge"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/k90_native_bridge")" = u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-odm-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

# Assemble Stage57 from Stage56.  Read back both extents and prove every byte
# outside the two intentionally replaced ranges remains byte-identical.
building="$out/images/super.img.building"
rm -f "$building"
cp --sparse=always "$base/images/super.img" "$building"
dd if="$work/out/system.img" of="$building" bs=4096 \
  seek=$((system_offset / 4096)) conv=notrunc,fsync status=none
dd if="$work/out/odm.img" of="$building" bs=4096 \
  seek=$((odm_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_size"

dd if="$building" of="$work/out/system.readback.img" \
  iflag=skip_bytes,count_bytes skip="$system_offset" \
  count="$system_partition_size" status=none
cmp "$work/out/system.img" "$work/out/system.readback.img"
fsck.erofs "$work/out/system.readback.img" \
  > "$work/out/fsck-system-readback.txt" 2>&1
python3 "$avb" verify_image --image "$work/out/system.readback.img" \
  > "$work/out/avb-system-readback.txt"

dd if="$building" of="$work/out/odm.readback.img" \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
fsck.erofs "$work/out/odm.readback.img" \
  > "$work/out/fsck-odm-readback.txt" 2>&1

cmp -n "$system_offset" "$base/images/super.img" "$building"
system_tail=$((system_offset + system_partition_size))
cmp -n "$((odm_offset - system_tail))" \
  -i "$system_tail:$system_tail" "$base/images/super.img" "$building"
odm_tail=$((odm_offset + odm_size))
cmp -n "$((super_size - odm_tail))" \
  -i "$odm_tail:$odm_tail" "$base/images/super.img" "$building"
mv "$building" "$out/images/super.img"

cp -a "$base/platform-tools" "$out/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$out/"
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
cp "$src/_fan_live_services_stage57/stage57_services_audit.txt" "$out/audit/"
(
  cd "$out"
  sha256sum images/super.img
) > "$out/SHA256SUMS.txt"
sha256sum \
  "$work/out/system.img" \
  "$work/out/odm.img" \
  "$work/out/k90_native_bridge" \
  "$jar" > "$out/audit/component-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage57 fan control fix candidate
Base: booted Stage56 FAN_PERF
Changed partitions: system (services.jar only), ODM (native bridge only)
Data wipe: no

Fixes:
- Prefer existing cooling_fan_mode_v3 over legacy cooling_fan_mode.
- Observe mode_v3, stepless level, and their two legacy backup keys.
- Publish the settings mailbox at observer construction and on every change.
- Read stepless level 1..8 and map to PWM 12/25/37/50/62/74/87/99.
- Add a system_server publication log line for direct runtime diagnosis.

Validation:
- Live Stage56 classes4.dex hash matched before patching.
- Only the two intended services.jar classes changed.
- DEX class set remains exactly 6867 classes.
- Other services.jar members are byte-identical.
- Native 13-case fan policy self-test passed.
- EROFS fsck and AVB verify passed for the rebuilt system.
- Every file/directory in rebuilt system and ODM has a SELinux label.
- Camera-critical odm/lib64/libc++_shared.so remains vendor_file.
- Only system and ODM super extents differ from Stage56; all other bytes match.

Physical airflow and all four UI modes must be tested after a keep-data flash.
This package does not touch boot, init_boot, modem, persist, nvdata, nvcfg,
protect*, or preloader.
EOF

cat > "$out/audit/CHANGES.txt" <<'EOF'
1. Stage56 already ran the native bridge as UID system; mailbox access was not
   the remaining fault. The old cooling_fan_mode setting was overwriting V3.
2. Sync now treats V3 as authoritative, fallback only when V3 is absent.
3. The ContentObserver now listens to mode_v3 and the actual 1..8 level key.
4. The native bridge maps custom levels to the same 8-step PWM ladder as UI.
5. Rebuild only the services.jar-bearing system extent and patched ODM binary.
6. Preserve full lower-tree SELinux labels and Stage56 camera linker repair.
EOF

echo STAGE57_OFFLINE_BUILD_PASSED
