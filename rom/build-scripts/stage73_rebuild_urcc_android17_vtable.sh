#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
pkg=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage73_URCC_ANDROID17_VTABLE
super="$pkg/images/super.img"
work=/root/k90_stage73_work
overlay=/root/k90_stage73_overlay
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
aidl_inc=/root/stage64_aidl_ndk/urcc/include
binder_src=/mnt/d/K90_A17_STAGE64_SRC/binder_headers/include
binder_inc=/root/k90_stage73_binder_headers
platform_cxx=/root/k90_stage73_platform_libcpp
system_lib=$root/trees/pmb_system/system/lib64

odm_off=$((20924416 * 512))
odm_len=$((3368224 * 512))
super_len=13421772800
base_hash=eed1a6cf6ff945f66a0e41f7c3aaee8bb707d4c1cd7a97c952efa8dd185f4cae
wire_hash=ae94a7505a18e9304d387f3dd87912e427478ae5d61441e3afe352c6b2cb140b

test -s "$super"
test -s "$src/stage64_urcc_service.cpp"
test -s "$src/stage70_live_urcc_v1_ndk.so"
test -s "$src/generate_erofs_file_contexts.py"
test "$(stat -c%s "$super")" -eq "$super_len"
test "$(sha256sum "$super" | cut -d' ' -f1)" = "$base_hash"
test "$(sha256sum "$src/stage70_live_urcc_v1_ndk.so" | cut -d' ' -f1)" = "$wire_hash"

rm -rf "$work" "$overlay" "$platform_cxx" "$binder_inc"
mkdir -p "$work/out" "$overlay"/{lower,upper,work,merged,verify}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

# The device platform uses libc++ namespace __1 while the standalone NDK uses
# __ndk1. Use a private header copy so the service ABI matches ColorOS exactly.
cp -a "$ndk/sysroot/usr/include/c++/v1" "$platform_cxx"
sed -i 's/#define _LIBCPP_ABI_NAMESPACE __ndk1/#define _LIBCPP_ABI_NAMESPACE __1/' \
  "$platform_cxx/__config_site"
grep -q '^#define _LIBCPP_ABI_NAMESPACE __1$' "$platform_cxx/__config_site"

# Android 17 platform libbinder_ndk includes handleShellCommand in
# ndk::ICInterface. The standalone NDK headers omit binder_shell.h and therefore
# omit this virtual, shifting every stable-AIDL method one vtable slot early.
# Keep the build headers private and restore the exact platform virtual without
# importing or calling any unavailable shell-command symbol.
cp -a "$binder_src" "$binder_inc"
python3 - "$binder_inc/android/binder_interface_utils.h" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "    virtual inline binder_status_t dump(int fd, const char** args, uint32_t numArgs);\n"
replacement = needle + "\n" + (
    "    // Android 17 platform ABI slot; default implementation is intentionally inert.\n"
    "    virtual inline binder_status_t handleShellCommand(\n"
    "            int in, int out, int err, const char** argv, uint32_t argc);\n"
)
if text.count(needle) != 1:
    raise SystemExit("unexpected ICInterface::dump declaration count")
text = text.replace(needle, replacement)
definition = (
    "binder_status_t ICInterface::dump(int /*fd*/, const char** /*args*/, uint32_t /*numArgs*/) {\n"
    "    return STATUS_OK;\n"
    "}\n"
)
definition_replacement = definition + (
    "\n"
    "binder_status_t ICInterface::handleShellCommand(\n"
    "        int /*in*/, int /*out*/, int /*err*/, const char** /*argv*/, uint32_t /*argc*/) {\n"
    "    return STATUS_OK;\n"
    "}\n"
)
if text.count(definition) != 1:
    raise SystemExit("unexpected ICInterface::dump definition count")
path.write_text(text.replace(definition, definition_replacement))
PY
grep -q 'Android 17 platform ABI slot' \
  "$binder_inc/android/binder_interface_utils.h"

mkdir -p "$work/link"
cp "$src/stage70_live_urcc_v1_ndk.so" \
  "$work/link/vendor.oplus.hardware.urcc-V1-ndk.so"
"$ndk/bin/aarch64-linux-android34-clang++" \
  -std=c++20 -O2 -Wall -Wextra -Werror -fPIE -pie -fno-rtti -D__ANDROID__ \
  -DK90_OPAQUE_URCC_REQUEST \
  -nostdinc++ -I"$platform_cxx" -I"$binder_inc" -I"$aidl_inc" \
  -L"$work/link" -L"$system_lib" \
  -Wl,-rpath-link,"$work/link" -Wl,-rpath-link,"$system_lib" \
  "$src/stage64_urcc_service.cpp" -Wl,--no-as-needed \
  -l:vendor.oplus.hardware.urcc-V1-ndk.so \
  -lbinder_ndk -llog -ldl -lm -nostdlib++ -lc++ \
  -o "$work/out/vendor.oplus.hardware.urcc-service"
"$ndk/bin/llvm-nm" -n -C "$work/out/vendor.oplus.hardware.urcc-service" \
  > "$work/out/urcc.nm.txt"
"$ndk/bin/llvm-objdump" -s --section=.data.rel.ro \
  "$work/out/vendor.oplus.hardware.urcc-service" \
  > "$work/out/urcc.vtable.txt"
"$ndk/bin/llvm-readelf" -h "$work/out/vendor.oplus.hardware.urcc-service" \
  > "$work/out/urcc.readelf-header.txt"
"$ndk/bin/llvm-readelf" -d "$work/out/vendor.oplus.hardware.urcc-service" \
  > "$work/out/urcc.readelf-dynamic.txt"
grep -q 'Machine:.*AArch64' "$work/out/urcc.readelf-header.txt"
grep -q 'Shared library: \[vendor.oplus.hardware.urcc-V1-ndk.so\]' \
  "$work/out/urcc.readelf-dynamic.txt"
grep -q 'Shared library: \[libc++.so\]' "$work/out/urcc.readelf-dynamic.txt"
! grep -q 'libc++_shared.so' "$work/out/urcc.readelf-dynamic.txt"
test "$(stat -c%s "$work/out/vendor.oplus.hardware.urcc-service")" -lt 200000

# Preserve hashes of both immutable regions before modifying the ODM extent.
dd if="$super" bs=16M iflag=count_bytes count="$odm_off" status=none \
  | sha256sum | tee "$work/pre-odm-before.sha256"
tail_off=$((odm_off + odm_len))
tail_len=$((super_len - tail_off))
dd if="$super" bs=16M iflag=skip_bytes,count_bytes skip="$tail_off" \
  count="$tail_len" status=none | sha256sum | tee "$work/post-odm-before.sha256"

dd if="$super" of="$work/odm.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
fsck.erofs "$work/odm.base.img" > "$work/fsck-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.base.img" "$overlay/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
for rel in bin bin/hw lib64; do
  mkdir -p "$overlay/upper/$rel"
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done

cp --preserve=all "$overlay/lower/bin/hw/vendor.oplus.hardware.urcc-service" \
  "$overlay/upper/bin/hw/vendor.oplus.hardware.urcc-service"
cp "$work/out/vendor.oplus.hardware.urcc-service" \
  "$overlay/upper/bin/hw/vendor.oplus.hardware.urcc-service"
chmod --reference="$overlay/lower/bin/hw/vendor.oplus.hardware.urcc-service" \
  "$overlay/upper/bin/hw/vendor.oplus.hardware.urcc-service"
chown --reference="$overlay/lower/bin/hw/vendor.oplus.hardware.urcc-service" \
  "$overlay/upper/bin/hw/vendor.oplus.hardware.urcc-service"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/upper/bin/hw/vendor.oplus.hardware.urcc-service"

install -m 0644 "$src/stage70_live_urcc_v1_ndk.so" \
  "$overlay/upper/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"
chown 0:0 "$overlay/upper/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/upper/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"

mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /odm \
  "$work/file_contexts" \
  --override /odm/bin/hw/vendor.oplus.hardware.urcc-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/lib64/vendor.oplus.hardware.urcc-V1-ndk.so=u:object_r:vendor_file:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  > "$work/contexts.txt"
uuid=$(blkid -o value -s UUID "$work/odm.base.img")
label=$(blkid -o value -s LABEL "$work/odm.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime \
      --mount-point=/odm --file-contexts="$work/file_contexts")
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/odm.raw.img" "$overlay/merged" \
  > "$work/mkfs.log" 2>&1
test "$(stat -c%s "$work/odm.raw.img")" -le "$odm_len"
cp --sparse=always "$work/odm.raw.img" "$work/odm.img"
truncate -s "$odm_len" "$work/odm.img"
umount "$overlay/merged"
umount "$overlay/lower"

fsck.erofs "$work/odm.img" > "$work/fsck.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.img" "$overlay/verify"
cmp "$work/out/vendor.oplus.hardware.urcc-service" \
  "$overlay/verify/bin/hw/vendor.oplus.hardware.urcc-service"
cmp "$src/stage70_live_urcc_v1_ndk.so" \
  "$overlay/verify/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/hw/vendor.oplus.hardware.urcc-service")" = \
  u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/vendor.oplus.hardware.urcc-V1-ndk.so")" = \
  u:object_r:vendor_file:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || \
    missing=$((missing + 1))
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

dd if="$work/odm.img" of="$super" bs=4096 \
  seek=$((odm_off / 4096)) conv=notrunc,fsync status=none
dd if="$super" of="$work/readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
cmp "$work/odm.img" "$work/readback.img"
fsck.erofs "$work/readback.img" > "$work/fsck-readback.txt" 2>&1

dd if="$super" bs=16M iflag=count_bytes count="$odm_off" status=none \
  | sha256sum | tee "$work/pre-odm-after.sha256"
dd if="$super" bs=16M iflag=skip_bytes,count_bytes skip="$tail_off" \
  count="$tail_len" status=none | sha256sum | tee "$work/post-odm-after.sha256"
cmp "$work/pre-odm-before.sha256" "$work/pre-odm-after.sha256"
cmp "$work/post-odm-before.sha256" "$work/post-odm-after.sha256"

sha256sum "$super" | tee "$pkg/SHA256SUMS.txt"
cp "$work/"*.txt "$work/"*.log "$work/"*.sha256 "$pkg/audit/" 2>/dev/null || true
cat > "$pkg/STATUS.txt" <<'EOF'
Stage73 Android 17 vtable-aligned ColorOS URCC candidate
Base: booted Stage72; ODM replaced in place to preserve disk space
Changed extent: ODM only
Data wipe: no

The K90 UniPerf-backed URCC implementation links to the exact ColorOS wire
library and treats the private UrccRequestParcel object as opaque. It issues a
bounded generic UniPerf hint and tracks/releases the returned handle without
reading private struct offsets. Its private Binder header restores the Android
17 handleShellCommand vtable slot omitted by standalone NDK headers. This aligns
urccInit at +0x30, state request at +0x48 and listener registration at +0x50.
Fan, camera, performance service, policies and every other super extent are
unchanged.

Runtime UAH request, positive UniPerf handle, release, idle recovery and
absence of Parcel object-offset errors are required before calling it fixed.
EOF
echo STAGE73_REBUILD_PASSED
