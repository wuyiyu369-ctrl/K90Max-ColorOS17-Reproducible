#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
tree="$root/01_主工程/K90_A17_PORT_WORK/trees/pmb_odm"
inspect=/root/stage54_inspect
mnt=/root/stage54_dep_mount
out=/root/stage54_dependency_probe

mkdir -p "$out" "$mnt"

{
  echo "DONOR=$tree"
  echo "=== LIBRARIES ==="
  for lib in \
    libbase.so \
    libcutils.so \
    liblog.so \
    libbinder_ndk.so \
    libprocessgroup.so \
    libutils.so \
    libcrypto.so \
    libxml2.so \
    libprotobuf-cpp-lite-21.12.so \
    android.frameworks.stats-V1-ndk.so \
    libc++.so \
    libc++_shared.so; do
    printf '%s: ' "$lib"
    found=
    for dir in lib lib64; do
      if [[ -e "$tree/$dir/$lib" ]]; then
        printf '%s ' "$dir/$lib"
        found=1
      fi
    done
    [[ -n "$found" ]] || printf 'MISSING'
    printf '\n'
  done
} > "$out/donor-libraries.txt"

{
  echo "=== SELINUX CONTEXT FILES ==="
  find "$tree/etc/selinux" -maxdepth 1 -type f \
    \( -name '*file_contexts*' -o -name '*service_contexts*' \
       -o -name '*policy*.cil' -o -name '*policy*.bin' \) \
    -printf '%f\n' | sort
  echo "=== MATCHES ==="
  grep -R -n -E \
    'vendor-oplus-hardware-performance|vendor\.oplus\.hardware\.urcc-service|liburcccore|performance-V[1-5]|urcc-V1|hal_oplus_performance|hal_urcc' \
    "$tree/etc/selinux" 2>/dev/null || true
} > "$out/donor-selinux.txt"

{
  echo "=== INIT ==="
  cat "$tree/etc/init/vendor-oplus-hardware-performance-V1-service.rc"
  echo "=== URCC INIT ==="
  cat "$tree/etc/init/vendor.oplus.hardware.urcc-service.rc"
  echo "=== PERFORMANCE VINTF ==="
  cat "$tree/etc/vintf/manifest/manifest_performance_aidl.xml"
  echo "=== URCC VINTF ==="
  cat "$tree/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml"
} > "$out/donor-services.txt"

if [[ -s "$inspect/odm53.img" ]]; then
  mount -t erofs -o ro,loop "$inspect/odm53.img" "$mnt"
  {
    echo "=== ACTUAL FILE ==="
    stat -c 'inode=%i mode=%a uid=%u gid=%g size=%s' "$mnt/lib64/libc++_shared.so"
    printf 'selinux='
    getfattr -n security.selinux --only-values "$mnt/lib64/libc++_shared.so" 2>/dev/null || true
    echo
    echo "=== CONTEXT MATCHES ==="
    grep -n -E \
      'libc\+\+_shared|vendor-oplus-hardware-performance|urcc-service|liburcccore|performance-V5|urcc-V1|hal_oplus_performance|hal_urcc' \
      "$mnt/etc/selinux/odm_file_contexts" \
      "$mnt/etc/selinux/odm_service_contexts" 2>/dev/null || true
    echo "=== POLICY MATCHES ==="
    grep -n -E \
      'hal_oplus_performance|hal_urcc' \
      "$mnt/etc/selinux/odm_sepolicy.cil" 2>/dev/null || true
  } > "$out/odm53-runtime-labels.txt"
  umount "$mnt"
fi

mkdir -p /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage54_dependency_probe
cp "$out"/*.txt /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage54_dependency_probe/
echo STAGE54_DEPENDENCY_PROBE_DONE
