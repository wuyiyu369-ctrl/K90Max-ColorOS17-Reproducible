#!/usr/bin/env bash
set -euo pipefail

tree=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/trees/pmb_odm
out=/root/stage54_perf_audit
mkdir -p "$out"

for soc in lib lib64; do
  for f in \
    "$tree/$soc/vendor.oplus.hardware.performance-V5-ndk.so" \
    "$tree/$soc/vendor.oplus.hardware.urcc-V1-ndk.so" \
    "$tree/$soc/liburcccore.so"; do
    if [ -f "$f" ]; then
      base=$(basename "$f")
      echo "== $soc/$base =="
      readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/NEEDED \1/p'
    fi
  done
done

echo '== STRINGS PERFORMANCE SERVICE =='
strings -a "$tree/bin/hw/vendor-oplus-hardware-performance-V1-service" |
  grep -Ei 'kgsl|schedtune|msm|qcom|walt|/proc/perfmgr|/sys/class/devfreq|thermal_message|sconfig|uniperf|mipower|mtk|/odm|/vendor' |
  head -n 180 || true

echo '== STRINGS URCC SERVICE =='
strings -a "$tree/bin/hw/vendor.oplus.hardware.urcc-service" |
  grep -Ei 'kgsl|schedtune|msm|qcom|walt|/proc/perfmgr|/sys/class/devfreq|thermal_message|sconfig|uniperf|mipower|mtk|/odm|/vendor' |
  head -n 180 || true

for f in \
  "$tree/bin/hw/vendor-oplus-hardware-performance-V1-service" \
  "$tree/bin/hw/vendor.oplus.hardware.urcc-service"; do
  echo "== $(basename "$f") =="
  readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/NEEDED \1/p'
  echo "RPATH"
  readelf -d "$f" | sed -n 's/.*RPATH.*\[\(.*\)\]/RPATH \1/p'
  readelf -d "$f" | sed -n 's/.*RUNPATH.*\[\(.*\)\]/RUNPATH \1/p'
done
