#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
stage64_src=/mnt/d/K90_A17_STAGE64_SRC
base=${K90_STAGE_BASE:-$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage63_CONFIRMED_FIXES}
out=${K90_STAGE_OUT:-$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage64_FAN_URCC_PERF}
work=${K90_STAGE_WORK:-/root/k90_stage64_work}
overlay=${K90_STAGE_OVERLAY:-/root/k90_stage64_overlay}
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
system_lib=$root/trees/pmb_system/system/lib64
binder_headers=$stage64_src/binder_headers/include
aidl_root=/root/stage64_aidl_ndk

odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
super_size=13421772800
base_super_hash=${K90_STAGE_BASE_HASH:-97716a9baeebf11e2717e8c1bb7771d15117f05822231b5c2a2e9cc06ba63aeb}
base_hash_marker=${K90_STAGE_BASE_MARKER:-/root/k90_stage64_base_verified_$base_super_hash}
odm_base_cache=${K90_STAGE_ODM_CACHE:-/root/k90_stage64_odm.base.img}

for file in "$base/images/super.img" "$src/stage59_misc_fan_service.c" \
            "$src/stage44_native_bridge.c" "$src/generate_erofs_file_contexts.py" \
            "$src/stage62_policy_patch.c" "$src/stage64_urcc_service.cpp" \
            "$src/stage64_performance.cpp" "$src/stage64_performance.h" \
            "$src/stage64_performance_service.cpp"; do
  test -s "$file" || { echo "MISSING: $file" >&2; exit 1; }
done
test -s "$system_lib/libbinder_ndk.so"
test -f "$binder_headers/android/binder_interface_utils.h"
test -f "$aidl_root/urcc/include/aidl/vendor/oplus/hardware/urcc/IUrcc.h"
test -f "$aidl_root/performance/include/aidl/vendor/oplus/hardware/performance/IPerformance.h"
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

cc -O2 -Wall -Wextra -Werror -I"$src/stage44_toolchain_source/selinux-main/libsepol/include" \
  -o "$work/out/stage62_policy_patch" "$src/stage62_policy_patch.c" \
  "$src/stage44_toolchain_source/selinux-main/libsepol/src/libsepol.a"

mapfile -t urcc_cpp < <(find "$aidl_root/urcc/src" -type f -name '*.cpp' -print | sort)
mapfile -t perf_cpp < <(find "$aidl_root/performance/src" -type f -name '*.cpp' -print | sort)
test "${#urcc_cpp[@]}" -ge 4
test "${#perf_cpp[@]}" -ge 10
common_cxx=(
  -std=c++20 -O2 -Wall -Wextra -Werror -fPIE -pie -D__ANDROID__
  -static-libstdc++ -I"$binder_headers"
  -L"$system_lib" -Wl,-rpath-link,"$system_lib"
  -lbinder_ndk -llog -ldl -lm
)
"$ndk/bin/aarch64-linux-android34-clang++" \
  -I"$aidl_root/urcc/include" "$src/stage64_urcc_service.cpp" \
  "${urcc_cpp[@]}" "${common_cxx[@]}" \
  -o "$work/out/vendor.oplus.hardware.urcc-service"
"$ndk/bin/aarch64-linux-android34-clang++" \
  -I"$src/stage64_log_compat" -I"$aidl_root/performance/include" \
  "$src/stage64_performance.cpp" "$src/stage64_performance_service.cpp" \
  "${perf_cpp[@]}" "${common_cxx[@]}" \
  -o "$work/out/vendor-oplus-hardware-performance-V1-service"

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

for binary in k90_oplus_misc_fan k90_native_bridge \
              vendor.oplus.hardware.urcc-service \
              vendor-oplus-hardware-performance-V1-service; do
  "$ndk/bin/llvm-readelf" -h "$work/out/$binary" > "$work/out/$binary.readelf-header.txt"
  "$ndk/bin/llvm-readelf" -d "$work/out/$binary" > "$work/out/$binary.readelf-dynamic.txt"
  grep -q 'Machine:.*AArch64' "$work/out/$binary.readelf-header.txt"
done
grep -q 'Shared library: \[libbinder_ndk.so\]' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
grep -q 'Shared library: \[liblog.so\]' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
! grep -Eq 'libstdc\+\+|libc\+\+' "$work/out/k90_oplus_misc_fan.readelf-dynamic.txt"
grep -a -q 'vendor.oplus.hardware.misc.IOplusMisc/default' \
  "$work/out/k90_oplus_misc_fan"
grep -a -q 'misc_fan_active' "$work/out/k90_native_bridge"
for binary in vendor.oplus.hardware.urcc-service \
              vendor-oplus-hardware-performance-V1-service; do
  grep -q 'Shared library: \[libbinder_ndk.so\]' "$work/out/$binary.readelf-dynamic.txt"
  grep -q 'Shared library: \[liblog.so\]' "$work/out/$binary.readelf-dynamic.txt"
  ! grep -Eq 'libstdc\+\+|libc\+\+' "$work/out/$binary.readelf-dynamic.txt"
done
grep -a -q 'vendor.oplus.hardware.urcc.IUrcc' \
  "$work/out/vendor.oplus.hardware.urcc-service"
grep -a -q 'cae43655eaf0af39cbb6d273c5e2206eebe33a10' \
  "$work/out/vendor.oplus.hardware.urcc-service"
grep -a -q 'vendor.oplus.hardware.performance.IPerformance' \
  "$work/out/vendor-oplus-hardware-performance-V1-service"
grep -a -q 'acb8b4f9dbecfc3818e1b9e0e203b191d2ba7648' \
  "$work/out/vendor-oplus-hardware-performance-V1-service"

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

# Remove the earlier cross-partition experiment when rebuilding from Stage62.
# The standalone ODM policy does not own the system_ext property type, and the
# rule was not effective on the booted device.
sed -i '/^(allow zygote oplus_fingerprint_prop (file (getattr open read map)))$/d' \
  "$overlay/merged/etc/selinux/odm_sepolicy.cil"

mkdir -p "$overlay/upper/bin" "$overlay/upper/bin/hw" "$overlay/upper/lib64" \
  "$overlay/upper/etc/init" "$overlay/upper/etc/vintf/manifest"
for rel in bin bin/hw lib64 etc etc/init etc/vintf etc/vintf/manifest; do
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done
install -m 0755 "$work/out/k90_oplus_misc_fan" "$overlay/merged/bin/k90_oplus_misc_fan"
install -m 0755 "$work/out/vendor.oplus.hardware.urcc-service" \
  "$overlay/merged/bin/hw/vendor.oplus.hardware.urcc-service"
install -m 0755 "$work/out/vendor-oplus-hardware-performance-V1-service" \
  "$overlay/merged/bin/hw/vendor-oplus-hardware-performance-V1-service"
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
    interface aidl vendor.oplus.hardware.misc.IOplusMisc/default
    disabled
    oneshot

on post-fs-data
    mkdir /data/vendor/k90max 0770 system system
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/target_level
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/target_level

on property:sys.boot_completed=1
    start k90-oplus-misc-fan
EOF

cat > "$overlay/merged/etc/init/vendor.oplus.hardware.urcc-service.rc" <<'EOF'
service vendor.urcc-hal-aidl /odm/bin/hw/vendor.oplus.hardware.urcc-service
    class hal
    user root
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0
    interface aidl vendor.oplus.hardware.urcc.IUrcc/default
    oneshot
EOF

cat > "$overlay/merged/etc/init/vendor-oplus-hardware-performance-V1-service.rc" <<'EOF'
service oplus.performance.hal.service-1-0 /odm/bin/hw/vendor-oplus-hardware-performance-V1-service
    class hal
    capabilities SYS_PTRACE
    user root
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0
    interface aidl vendor.oplus.hardware.performance.IPerformance/default
    oneshot
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

cat > "$overlay/merged/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml" <<'EOF'
<manifest version="1.0" type="device">
    <hal format="aidl">
        <name>vendor.oplus.hardware.urcc</name>
        <version>1</version>
        <fqname>IUrcc/default</fqname>
    </hal>
</manifest>
EOF

cat > "$overlay/merged/etc/vintf/manifest/manifest_performance_aidl.xml" <<'EOF'
<manifest version="1.0" type="device">
    <hal format="aidl">
        <name>vendor.oplus.hardware.performance</name>
        <version>2</version>
        <fqname>IPerformance/default</fqname>
    </hal>
</manifest>
EOF

service_context='vendor.oplus.hardware.misc.IOplusMisc/default u:object_r:hal_power_service:s0'
service_contexts="$overlay/merged/etc/selinux/odm_service_contexts"
touch "$service_contexts"
grep -q '^vendor.oplus.hardware.misc.IOplusMisc/default ' "$service_contexts" || \
  printf '%s\n' "$service_context" >> "$service_contexts"
grep -q '^vendor.oplus.hardware.urcc.IUrcc/default ' "$service_contexts" || \
  printf '%s\n' 'vendor.oplus.hardware.urcc.IUrcc/default u:object_r:hal_power_service:s0' >> "$service_contexts"
grep -q '^vendor.oplus.hardware.performance.IPerformance/default ' "$service_contexts" || \
  printf '%s\n' 'vendor.oplus.hardware.performance.IPerformance/default u:object_r:hal_power_service:s0' >> "$service_contexts"

"$work/out/stage62_policy_patch" \
  "$overlay/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/merged/etc/selinux/precompiled_sepolicy" \
  > "$work/out/policy-patch.txt"
cat >> "$overlay/merged/etc/selinux/odm_sepolicy.cil" <<'EOF'
; Stage62 exact Stage61 runtime denials and integrated bridge access.
(allow system_app vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell system_app (binder (transfer)))
(typeattributeset hal_micharge_client (vendor_touch_init_shell))
(allow vendor_touch_init_shell sysfs_ged (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_ged (file (getattr open read)))
(allow vendor_touch_init_shell sysfs_dvfsrc_devfreq (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_dvfsrc_devfreq (file (getattr open read)))
(allow vendor_touch_init_shell sysfs_devices_block (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_devices_block (file (getattr open read)))
(allow vendor_touch_init_shell sysfs_usb_supply (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_usb_supply (file (getattr open read)))
(allow vendor_touch_init_shell sysfs_ti_battery (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_ti_battery (file (getattr open read)))
(allow vendor_touch_init_shell thermal_data_file (dir (getattr search open read)))
(allow vendor_touch_init_shell vendor_data_file (dir (remove_name)))
(allow vendor_touch_init_shell vendor_data_file (file (rename unlink)))
; Stage64 compatibility services share the proven native bridge domain.
(allow surfaceflinger vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell surfaceflinger (binder (transfer)))
(allow platform_app vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell platform_app (binder (transfer)))
(allow stats vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell stats (binder (transfer)))
EOF
for rel in etc/selinux/precompiled_sepolicy etc/selinux/odm_sepolicy.cil \
           etc/selinux/odm_service_contexts; do
  cp --attributes-only --preserve=all "$overlay/lower/$rel" "$overlay/upper/$rel"
done
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/upper/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/upper/etc/selinux/odm_sepolicy.cil"
setfattr -n security.selinux -v u:object_r:service_contexts_file:s0 \
  "$overlay/upper/etc/selinux/odm_service_contexts"

for rel in bin/k90_oplus_misc_fan bin/k90_native_bridge; do
  setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
    "$overlay/merged/$rel"
  setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
    "$overlay/upper/$rel"
done
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/merged/bin/hw/vendor.oplus.hardware.urcc-service"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/merged/bin/hw/vendor-oplus-hardware-performance-V1-service"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/merged/etc/init/k90-misc-fan.rc"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/upper/etc/init/k90-misc-fan.rc"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/merged/etc/vintf/manifest/manifest_k90_misc_fan.xml"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/upper/etc/vintf/manifest/manifest_k90_misc_fan.xml"
for rel in \
  etc/init/vendor.oplus.hardware.urcc-service.rc \
  etc/init/vendor-oplus-hardware-performance-V1-service.rc \
  etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml \
  etc/vintf/manifest/manifest_performance_aidl.xml; do
  setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
    "$overlay/merged/$rel"
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
  --override /odm/bin/hw/vendor.oplus.hardware.urcc-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/bin/hw/vendor-oplus-hardware-performance-V1-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/etc/init/k90-misc-fan.rc=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/vintf/manifest/manifest_k90_misc_fan.xml=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/selinux/precompiled_sepolicy=u:object_r:sepolicy_file:s0 \
  --override /odm/etc/selinux/odm_sepolicy.cil=u:object_r:sepolicy_file:s0 \
  --override /odm/etc/selinux/odm_service_contexts=u:object_r:service_contexts_file:s0 \
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
cmp "$work/out/vendor.oplus.hardware.urcc-service" \
  "$overlay/verify/bin/hw/vendor.oplus.hardware.urcc-service"
cmp "$work/out/vendor-oplus-hardware-performance-V1-service" \
  "$overlay/verify/bin/hw/vendor-oplus-hardware-performance-V1-service"
grep -q '^service k90-oplus-misc-fan ' "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '^    disabled$' "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '^    oneshot$' "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '^    interface aidl vendor.oplus.hardware.misc.IOplusMisc/default$' \
  "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '^on property:sys.boot_completed=1$' "$overlay/verify/etc/init/k90-misc-fan.rc"
grep -q '<name>vendor.oplus.hardware.misc</name>' \
  "$overlay/verify/etc/vintf/manifest/manifest_k90_misc_fan.xml"
grep -q '<version>1</version>' \
  "$overlay/verify/etc/vintf/manifest/manifest_k90_misc_fan.xml"
grep -q '<fqname>IOplusMisc/default</fqname>' \
  "$overlay/verify/etc/vintf/manifest/manifest_k90_misc_fan.xml"
grep -q '<version>1</version>' \
  "$overlay/verify/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml"
grep -q '<fqname>IUrcc/default</fqname>' \
  "$overlay/verify/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml"
grep -q '<version>2</version>' \
  "$overlay/verify/etc/vintf/manifest/manifest_performance_aidl.xml"
grep -q '<fqname>IPerformance/default</fqname>' \
  "$overlay/verify/etc/vintf/manifest/manifest_performance_aidl.xml"
grep -q "^$service_context$" "$overlay/verify/etc/selinux/odm_service_contexts"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_oplus_misc_fan")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_native_bridge")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/hw/vendor.oplus.hardware.urcc-service")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/hw/vendor-oplus-hardware-performance-V1-service")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++_shared.so")" = \
  u:object_r:vendor_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/init/k90-misc-fan.rc")" = \
  u:object_r:vendor_configs_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/vintf/manifest/manifest_k90_misc_fan.xml")" = \
  u:object_r:vendor_configs_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/selinux/precompiled_sepolicy")" = \
  u:object_r:sepolicy_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/selinux/odm_sepolicy.cil")" = \
  u:object_r:sepolicy_file:s0
grep -q '^POLICY_READBACK_OK ' "$work/out/policy-patch.txt"
grep -q '^allow system_app vendor_touch_init_shell:binder { call transfer };$' \
  "$work/out/policy-patch.txt"
grep -q '^typeattribute vendor_touch_init_shell hal_micharge_client;$' \
  "$work/out/policy-patch.txt"
grep -q '^allow surfaceflinger vendor_touch_init_shell:binder { call transfer };$' \
  "$work/out/policy-patch.txt"
grep -q '^allow platform_app vendor_touch_init_shell:binder { call transfer };$' \
  "$work/out/policy-patch.txt"
grep -q '^vendor.oplus.hardware.urcc.IUrcc/default u:object_r:hal_power_service:s0$' \
  "$overlay/verify/etc/selinux/odm_service_contexts"
grep -q '^vendor.oplus.hardware.performance.IPerformance/default u:object_r:hal_power_service:s0$' \
  "$overlay/verify/etc/selinux/odm_service_contexts"
grep -q '^(typeattributeset hal_micharge_client (vendor_touch_init_shell))$' \
  "$overlay/verify/etc/selinux/odm_sepolicy.cil"
grep -q '^allow vendor_touch_init_shell sysfs_ged:dir ' "$work/out/policy-patch.txt"
grep -q '^allow vendor_touch_init_shell sysfs_dvfsrc_devfreq:dir ' "$work/out/policy-patch.txt"
grep -q '^allow vendor_touch_init_shell sysfs_devices_block:dir ' "$work/out/policy-patch.txt"
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-odm-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

building="$work/out/super.img.building"
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
cp --sparse=always "$building" "$out/images/super.img.building"
mv "$out/images/super.img.building" "$out/images/super.img"

cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/out/odm.img" "$work/out/k90_oplus_misc_fan" \
  "$work/out/k90_native_bridge" > "$out/audit/component-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage62 integrated policy and native compatibility candidate
Base: booted Stage61 MISC_VINTF_FIX
Changed partition: ODM only
Data wipe: no

Implemented:
- Original Ace7 DeviceSettings/Aeolus fan output now has its expected stable
  AIDL service: vendor.oplus.hardware.misc.IOplusMisc/default.
- Main switch node 0x191 and raw speed node 0x193 are translated to the K90
  Xiaomi fan driver. Ace7 speed 0..20 maps to PWM 0..99.
- The legacy mailbox bridge yields while the IOplusMisc service heartbeat is
  fresh, preventing two writers from fighting over pwm_duty.
- The compatibility service is disabled during early boot and starts only
  after sys.boot_completed=1. It is oneshot, so registration failure cannot
  create an init restart loop.
- Restores the exact Ace7 AIDL VINTF declaration required by the stable Binder.
- Adds the matching init interface declaration while preserving delayed start:
  disabled + oneshot + sys.boot_completed=1.
- Both the manifest fragment and init rc use vendor_configs_file labels.
- Adds the exact system_app <-> vendor_touch_init_shell Binder permissions
  observed when OplusFanService called IOplusMisc node 0x191 on Stage61.
- Adds read-only GPU/DDR/UFS metric access for the existing native performance
  bridge and Xiaomi charging-node reads observed in Stage61 denials.
- Adds only vendor bridge state-file cleanup permission; no thermal disable,
  fixed-frequency lock, permissive domain, or direct modem/persist change.

Offline validation:
- 8-case speed mapping self-test passed.
- Both binaries are ARM64 PIE and the misc service links libbinder_ndk/liblog.
- EROFS fsck passed before and after final super readback.
- Every rebuilt ODM file and directory has a SELinux label.
- New binaries use the already proven vendor_touch_init_shell_exec label.
- IOplusMisc uses the already proven hal_power_service service type.
- VINTF declaration is statically present, but the service still cannot start
  before Android reports sys.boot_completed=1.
- Camera-critical odm/lib64/libc++_shared.so remains vendor_file.
- Every byte outside the ODM extent is identical to Stage58.

Not yet claimed:
- Physical airflow is not proven until a keep-data flash and real device test.
- A complete Oplus IPerformance/URCC/UAH service translation is not claimed;
  the incompatible Qualcomm Ace7 URCC daemon is intentionally excluded.
- TEE/private keys and hardware features absent from K90 are not fabricated.
EOF

echo STAGE62_OFFLINE_BUILD_PASSED
