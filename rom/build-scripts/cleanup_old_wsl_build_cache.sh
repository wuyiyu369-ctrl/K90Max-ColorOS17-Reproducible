#!/usr/bin/env bash
set -euo pipefail

targets=(
  /root/k90_stage15_cpu_sepolicy
  /root/k90_stage17_biometrics_display
  /root/k90_stage17_biometrics_display_r2
  /root/k90_stage17_biometrics_display_r2b
  /root/k90_stage18_native
  /root/k90_stage19_safety
  /root/k90_stage19_system_final
  /root/k90_stage19_odm_charge
  /root/k90_stage19_watchdog_fix
)

for target in "${targets[@]}"; do
  resolved=$(realpath -e "$target")
  case "$resolved" in
    /root/k90_stage*) ;;
    *) echo "unsafe target: $resolved" >&2; exit 2 ;;
  esac
  if mount | grep -Fq " $resolved/"; then
    echo "mounted target: $resolved" >&2
    exit 3
  fi
  echo "verified: $resolved"
done

for target in "${targets[@]}"; do
  rm -rf -- "$target"
done

df -h /root
echo OLD_WSL_BUILD_CACHE_REMOVED
