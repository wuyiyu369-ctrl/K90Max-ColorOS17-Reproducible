#!/usr/bin/env bash
set -euo pipefail
old='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS/images/super.img'
new='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR/images/super.img'
out='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR/INDEPENDENT_AUDIT.txt'
test "$(stat -c%s "$old")" -eq 13421772800
test "$(stat -c%s "$new")" -eq 13421772800
cmp <(dd if="$old" bs=4096 count=256 status=none) <(dd if="$new" bs=4096 count=256 status=none)
cmp <(dd if="$old" bs=4096 skip=259322 status=none) <(dd if="$new" bs=4096 skip=259322 status=none)
new_system=$(dd if="$new" bs=4096 skip=256 count=259066 status=none | sha256sum | awk '{print $1}')
test "$new_system" = f5592e0e9492f06d0ac380ceab32139386266bb4bbaf5b626620f36e828f2293
cat > "$out" <<EOF
AUDIT_OK
ONLY_SYSTEM_EXTENT_CHANGED
STAGE41_PREFIX_AND_SUFFIX_IDENTICAL
SYSTEM_EXTENT_SHA256=$new_system
EOF
cat "$out"
