#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
out=/mnt/d/K90_STAGE79_WORK_V1/stage79_native
work=/root/k90_stage79_urcc
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
aidl_inc=/root/stage64_aidl_ndk/urcc/include
binder_src=/mnt/d/K90_A17_STAGE64_SRC/binder_headers/include
binder_inc=$work/binder_headers
platform_cxx=$work/platform_libcpp
system_lib=$root/trees/pmb_system/system/lib64

for f in "$src/stage64_urcc_service.cpp" "$src/stage70_live_urcc_v1_ndk.so"; do
  test -s "$f" || { echo "MISSING: $f" >&2; exit 1; }
done
test -x "$ndk/bin/aarch64-linux-android34-clang++"
test -d "$aidl_inc"
test -d "$binder_src"
test -d "$system_lib"

rm -rf "$work" "$out"
mkdir -p "$work/link" "$out/audit"

# Match the Android 17 platform C++ namespace and ICInterface vtable exactly.
cp -a "$ndk/sysroot/usr/include/c++/v1" "$platform_cxx"
sed -i 's/#define _LIBCPP_ABI_NAMESPACE __ndk1/#define _LIBCPP_ABI_NAMESPACE __1/' \
  "$platform_cxx/__config_site"
grep -q '^#define _LIBCPP_ABI_NAMESPACE __1$' "$platform_cxx/__config_site"

cp -a "$binder_src" "$binder_inc"
python3 - "$binder_inc/android/binder_interface_utils.h" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
decl = "    virtual inline binder_status_t dump(int fd, const char** args, uint32_t numArgs);\n"
if t.count(decl) != 1:
    raise SystemExit("unexpected ICInterface::dump declaration")
t = t.replace(decl, decl + "\n    virtual inline binder_status_t handleShellCommand(\n            int in, int out, int err, const char** argv, uint32_t argc);\n")
body = "binder_status_t ICInterface::dump(int /*fd*/, const char** /*args*/, uint32_t /*numArgs*/) {\n    return STATUS_OK;\n}\n"
if t.count(body) != 1:
    raise SystemExit("unexpected ICInterface::dump definition")
t = t.replace(body, body + "\nbinder_status_t ICInterface::handleShellCommand(\n        int /*in*/, int /*out*/, int /*err*/, const char** /*argv*/, uint32_t /*argc*/) {\n    return STATUS_OK;\n}\n")
p.write_text(t)
PY

cp "$src/stage70_live_urcc_v1_ndk.so" "$work/link/vendor.oplus.hardware.urcc-V1-ndk.so"
"$ndk/bin/aarch64-linux-android34-clang++" \
  -std=c++20 -O2 -Wall -Wextra -Werror -fPIE -pie -fno-rtti -D__ANDROID__ \
  -DK90_OPAQUE_URCC_REQUEST \
  -nostdinc++ -I"$platform_cxx" -I"$binder_inc" -I"$aidl_inc" \
  -L"$work/link" -L"$system_lib" \
  -Wl,-rpath-link,"$work/link" -Wl,-rpath-link,"$system_lib" \
  "$src/stage64_urcc_service.cpp" -Wl,--no-as-needed \
  -l:vendor.oplus.hardware.urcc-V1-ndk.so \
  -lbinder_ndk -llog -ldl -lm -nostdlib++ -lc++ \
  -o "$out/vendor.oplus.hardware.urcc-service"

"$ndk/bin/llvm-readelf" -h "$out/vendor.oplus.hardware.urcc-service" > "$out/audit/readelf-header.txt"
"$ndk/bin/llvm-readelf" -d "$out/vendor.oplus.hardware.urcc-service" > "$out/audit/readelf-dynamic.txt"
"$ndk/bin/llvm-nm" -n -C "$out/vendor.oplus.hardware.urcc-service" > "$out/audit/nm.txt"
"$ndk/bin/llvm-objdump" -s --section=.data.rel.ro "$out/vendor.oplus.hardware.urcc-service" > "$out/audit/vtable.txt"
grep -q 'Machine:.*AArch64' "$out/audit/readelf-header.txt"
grep -q 'Shared library: \[vendor.oplus.hardware.urcc-V1-ndk.so\]' "$out/audit/readelf-dynamic.txt"
grep -q 'Shared library: \[libc++.so\]' "$out/audit/readelf-dynamic.txt"
! grep -q 'libc++_shared.so' "$out/audit/readelf-dynamic.txt"
test "$(stat -c%s "$out/vendor.oplus.hardware.urcc-service")" -lt 200000
grep -a -q 'auto-expire=1' "$out/vendor.oplus.hardware.urcc-service"
sha256sum "$out/vendor.oplus.hardware.urcc-service" "$src/stage70_live_urcc_v1_ndk.so" | tee "$out/SHA256SUMS.txt"
echo STAGE79_URCC_BUILD_PASSED
