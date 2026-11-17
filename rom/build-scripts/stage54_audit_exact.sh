#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
tree="$root/01_主工程/K90_A17_PORT_WORK/trees/pmb_odm"
inspect=/root/stage54_inspect
mnt=/root/stage54_runtime_mount
out=/root/stage54_exact_audit

mkdir -p "$out" "$mnt"

echo '=== DONOR TREE FILES ===' > "$out/donor-files.txt"
find "$tree" -type f \( \
  -iname '*performance*' -o \
  -iname '*urcc*' -o \
  -iname '*uah*' \
  \) -printf '%P\n' 2>/dev/null | sort >> "$out/donor-files.txt"

echo '=== DONOR CONTEXT MATCHES ===' > "$out/donor-contexts.txt"
grep -R -n -E \
  'performance|urcc|liburcccore|oplus_performance|hal_urcc' \
  "$tree/etc/selinux" 2>/dev/null >> "$out/donor-contexts.txt" || true

echo '=== DONOR INIT MATCHES ===' > "$out/donor-init.txt"
grep -R -n -E \
  'performance|urcc|uah|mi_thermal|uniperf|mipower' \
  "$tree/etc/init" 2>/dev/null >> "$out/donor-init.txt" || true

echo '=== DONOR VINTF ===' > "$out/donor-vintf.txt"
grep -R -n -E \
  'IPerformance|IUrcc|performance|urcc' \
  "$tree/etc/vintf" 2>/dev/null >> "$out/donor-vintf.txt" || true

for part in odm product system; do
  image="$inspect/${part}53.img"
  [[ "$part" == system ]] && image="$inspect/system52.img"
  [[ -f "$image" ]] || continue
  mount -t erofs -o ro,loop "$image" "$mnt"
  section="$out/${part}-runtime.txt"
  {
    echo "IMAGE=$image"
    if [[ "$part" == odm ]]; then
      echo '--- target files ---'
      for rel in \
        lib64/libc++_shared.so \
        lib64/libbase.so \
        lib64/libcutils.so \
        lib64/liblog.so \
        lib64/libbinder_ndk.so \
        lib64/libprocessgroup.so \
        lib64/libutils.so \
        lib64/libcrypto.so \
        lib64/libxml2.so \
        lib64/libprotobuf-cpp-lite-21.12.so \
        lib64/android.frameworks.stats-V1-ndk.so \
        lib/libc++_shared.so; do
        f="$mnt/$rel"
        if [[ -e "$f" ]]; then
          ls -lZ "$f"
          printf 'SELINUX='
          getfattr -n security.selinux --only-values "$f" 2>/dev/null || true
          echo
        else
          echo "MISSING $rel"
        fi
      done
      echo '--- selinux matches ---'
      grep -R -n -E \
        'performance|urcc|liburcccore|libc\+\+_shared' \
        "$mnt/etc/selinux" 2>/dev/null | head -n 400 || true
    elif [[ "$part" == product ]]; then
      echo '--- feature/name files ---'
      for rel in \
        etc/permissions/oplus.feature.android.xml \
        etc/build.prop \
        etc/init/k90-user-names.rc; do
        f="$mnt/$rel"
        if [[ -e "$f" ]]; then
          ls -lZ "$f"
          grep -n -E 'fan|marketname|device_name|product.model|bt_name|wifi_ap' "$f" || true
        else
          echo "MISSING $rel"
        fi
      done
    else
      echo '--- HIDL/AIDL Java classes and service binaries ---'
      find "$mnt" -type f \( \
        -iname '*performance*' -o \
        -iname '*urcc*' \
        \) -printf '%P\n' 2>/dev/null | sort | head -n 500
    fi
  } > "$section"
  umount "$mnt"
done

cp "$out"/*.txt /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage54_exact_audit/ 2>/dev/null || {
  mkdir -p /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage54_exact_audit
  cp "$out"/*.txt /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage54_exact_audit/
}

echo 'STAGE54_EXACT_AUDIT_DONE'
