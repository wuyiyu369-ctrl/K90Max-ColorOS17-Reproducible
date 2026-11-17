#!/usr/bin/env bash
set -euo pipefail

base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS/images/super.img
candidate=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage42_FANPERF_POLICY/images/super.img
start=$((2615552 * 4096))
length=$((421028 * 4096))
end=$((start + length))

test "$(stat -c%s "$base")" -eq 13421772800
test "$(stat -c%s "$candidate")" -eq 13421772800
cmp -n "$start" "$base" "$candidate"
cmp -i "$end:$end" "$base" "$candidate"

echo OUTSIDE_ODM_BYTE_IDENTICAL
echo ODM_START="$start"
echo ODM_LENGTH="$length"
echo ODM_END="$end"
