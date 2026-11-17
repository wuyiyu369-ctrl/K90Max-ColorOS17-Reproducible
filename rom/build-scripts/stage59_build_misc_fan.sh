#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage58_FAN_BRANCH_FIX
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage59_MISC_FAN
work=/root/k90_stage59_work
overlay=/root/k90_stage59_overlay
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
system_lib=$root/trees/pmb_system/system/lib64

odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
super_size=13421772800
base_super_hash=2e3d8fb7b6d9969ca8b6b5f03c61b11be03f2d082ba818c62ee8d3a564de54e4
base_hash_marker=/root/k90_stage59_stage58_base_verified_$base_super_hash
odm_base_cache=/root/k90_stage59_stage58_odm.base.img

for file in "$base/images/super.img" "$src/stage59_misc_fan_service.c" \
            "$src/stage44_native_bridge.c" "$src/generate_erofs_file_contexts.py"; do
  test -s "$file" || { echo "MISSING: $file" >&2; exit 1; }
done
test -s "$system_lib/libbinder_ndk.so"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
if [[ ! -f "$base_hash_marker" ]]; then
  test "$(sha256sum "$base/images/super.img" | cut -d' ' -f1)" = "$base_super_hash"
  touch "$base_hash_marker"
fi

rm -rf "$work" "$overlay" "$out"
mkdir -p "$work/out" "$overlay"/{lower,upper,work,merged,verify} "$out"/{images,audit}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

cc -O2 -Wall -Wextra -Werror -o "$work/out/misc-fan-host" \
  "$src/stage59_misc_fan_service.c"
"$work/out/misc-fan-host" --self-test | tee "$work/out/misc-fan-self-test.txt"
"$ndk/bin/aarch64-linux-android34-clang" -O2 -Wall -Wextra -Werror \
  -fPIE -pie -D__ANDROID__ -o "$work/out/k90_oplus_misc_fan" \
  "$src/stage59_misc_fan_service.c" -L"$system_lib" \
  -Wl,-rpath-link,"$system_lib" -lbinder_ndk -llog
"$ndk/bin/aarch64-linux-android34-clang" -O2 -Wall -Wextra -Werror \
  -fPIE -pie -D__ANDROID__ -o "$work/out/k90_native_bridge" \
  "$src/stage44_native_bridge.c" -llog -ldl

for binary in k90_oplus_misc_fan k90_native_bridge; do
  "$ndk/bin/llvm-readelf" -h "$work/out/$binary" > "$work/out/$binary.readelf-header.txt"
  "$ndk/bin/llvm-readelf" -d "$work/out/$binary" > "$work/out/$binary.readelf-dynamic.txt"
  grep -q 'Machine:.*AArch64' "$work/out/$binary.readelf-header.txt"
done
grep -q 'Shared library: \[libbinder_ndk.so\]' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
grep -q 'Shared library: \[liblog.so\]' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
! grep -Eq 'libstdc\+\+|libc\+\+' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
strings -a "$work/out/k90_oplus_misc_fan" | grep -q 'vendor.oplus.hardware.misc.IOplusMisc/default'
strings -a "$work/out/k90_native_bridge" | grep -q 'misc_fan_active'

if [[ ! -f "$odm_base_cache" || "$(stat -c%s "$odm_base_cache")" -ne "$odm_size" ]]; then
  rm -f "$odm_base_cache"
  dd if="$base/images/super.img" of="$odm_base_cache" \
    iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
fi
test "$(stat -c%s "$odm_base_cache")" -eq "$odm_size"
fsck.erofs "$odm_base_cache" > "$work/out/fsck-odm-base.txt" 2>&1
mount -t erofs -o ro,loop "$odm_base_cache" "$overlay/lower"
test "$(getfattr -n security.selinux --only-values "$overlay/lower/lib64/libc++_shared.so")" = \
  u:object_r:vendor_file:s0

root_label=$(getfattr -n security.selinux --only-values "$overlay/lower")
setfattr -n security.selinux -v "$root_label" "$overlay/upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"

mkdir -p "$overlay/upper/bin" "$overlay/upper/lib64" \
  "$overlay/upper/etc/init" "$overlay/upper/etc/vintf/manifest"
for rel in bin lib64 etc etc/init etc/vintf etc/vintf/manifest; do
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done
install -m 0755 "$work/out/k90_oplus_misc_fan" "$overlay/merged/bin/k90_oplus_misc_fan"
cp -a "$overlay/lower/bin/k90_native_bridge" "$overlay/upper/bin/k90_native_bridge"
cp "$work/out/k90_native_bridge" "$overlay/merged/bin/k90_native_bridge"
cp --attributes-only --preserve=all "$overlay/lower/bin/k90_native_bridge" \
  "$overlay/upper/bin/k90_native_bridge"

cat > "$overlay/merged/etc/init/k90-misc-fan.rc" <<'EOF'
service k90-oplus-misc-fan /odm/bin/k90_oplus_misc_fan
    class late_start
    user system
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0

on post-fs-data
    mkdir /data/vendor/k90max 0770 system system
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/target_level
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/target_level
EOF

cat > "$overlay/merged/etc/vintf/manifest/manifest_k90_misc_fan.xml" <<'EOF'
<manifest version="1.0" type="device">
    <hal format="aidl">
        <name>vendor.oplus.hardware.misc</name>
        <version>1</version>
        <fqname>IOplusMisc/default</fqname>
    </hal>
</manifest>
EOF

service_context='vendor.oplus.hardware.misc.IOplusMisc/default u:object_r:hal_power_service:s0'
service_contexts="$overlay/merged/etc/selinux/odm_service_contexts"
grep -q '^vendor.oplus.hardware.misc.IOplusMisc/default ' "$service_contexts" || \
  printf '%s\n' "$service_context" >> "$service_contexts"

for rel in bin/k90_oplus_misc_fan bin/k90_native_bridge; do
  setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
    "$overlay/merged/$rel"
  setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
    "$overlay/upper/$rel"
done
for rel in etc/init/k90-misc-fan.rc etc/vintf/manifest/manifest_k90_misc_fan.xml; do
  setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/merged/$rel"
  setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/upper/$rel"
done

# Force-copy the camera-critical linker library into upper so its known-good
# Stage58 label cannot be lost during the EROFS rebuild.
cp -a "$overlay/lower/lib64/libc++_shared.so" "$overlay/upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/upper/lib64/libc++_shared.so"

python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /odm \
  "$work/out/odm_file_contexts.generated" \
  --override /odm/bin/k90_oplus_misc_fan=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/bin/k90_native_bridge=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/etc/init/k90-misc-fan.rc=u:object_r:vendor_file:s0 \
  --override /odm/etc/vintf/manifest/manifest_k90_misc_fan.xml=u:object_r:vendor_file:s0 \
  > "$work/out/odm-file-contexts-generation.txt"

uuid=$(blkid -o value -s UUID "$odm_base_cache")
label=$(blkid -o value -s LABEL "$odm_base_cache" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || args+=(-L "$label")
args+=(--mount-point=/odm --file-contexts="$work/out/odm_file_contexts.generated")
mkfs.erofs "${args[@]}" "$work/out/odm.raw.img" "$overlay/merged" \
  > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
cmp "$work/out/k90_oplus_misc_fan" "$overlay/verify/bin/k90_oplus_misc_fan"
cmp "$work/out/k90_native_bridge" "$overlay/verify/bin/k90_native_bridge"
grep -q '^service k90-oplus-misc-fan ' "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '<fqname>IOplusMisc/default</fqname>' \
  "$overlay/verify/etc/vintf/manifest/manifest_k90_misc_fan.xml"
grep -q "^$service_context$" "$overlay/verify/etc/selinux/odm_service_contexts"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_oplus_misc_fan")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_native_bridge")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++_shared.so")" = \
  u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-odm-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

building="$out/images/super.img.building"
cp --sparse=always "$base/images/super.img" "$building"
dd if="$work/out/odm.img" of="$building" bs=4096 \
  seek=$((odm_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_size"
dd if="$building" of="$work/out/odm.readback.img" \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
fsck.erofs "$work/out/odm.readback.img" > "$work/out/fsck-odm-readback.txt" 2>&1
cmp -n "$odm_offset" "$base/images/super.img" "$building"
odm_tail=$((odm_offset + odm_size))
cmp -n "$((super_size - odm_tail))" -i "$odm_tail:$odm_tail" \
  "$base/images/super.img" "$building"
mv "$building" "$out/images/super.img"

cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/out/odm.img" "$work/out/k90_oplus_misc_fan" \
  "$work/out/k90_native_bridge" > "$out/audit/component-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage59 IOplusMisc fan compatibility candidate
Base: booted Stage58 FAN_BRANCH_FIX
Changed partition: ODM only
Data wipe: no

Implemented:
- Original Ace7 DeviceSettings/Aeolus fan output now has its expected stable
  AIDL service: vendor.oplus.hardware.misc.IOplusMisc/default.
- Main switch node 0x191 and raw speed node 0x193 are translated to the K90
  Xiaomi fan driver. Ace7 speed 0..20 maps to PWM 0..99.
- The legacy mailbox bridge yields while the IOplusMisc service heartbeat is
  fresh, preventing two writers from fighting over pwm_duty.

Offline validation:
- 8-case speed mapping self-test passed.
- Both binaries are ARM64 PIE and the misc service links libbinder_ndk/liblog.
- EROFS fsck passed before and after final super readback.
- Every rebuilt ODM file and directory has a SELinux label.
- New binaries use the already proven vendor_touch_init_shell_exec label.
- IOplusMisc uses the already proven hal_power_service service type.
- Camera-critical odm/lib64/libc++_shared.so remains vendor_file.
- Every byte outside the ODM extent is identical to Stage58.

Not yet claimed:
- Physical airflow is not proven until a keep-data flash and real device test.
- Full-screen AOD and complete Oplus performance/URCC proxies are not part of
  this fan-only build.
EOF

echo STAGE59_OFFLINE_BUILD_PASSED
