#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage57_FAN_CONTROL_FIX/images/super.img
candidate=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage58_FAN_BRANCH_FIX/images/super.img.candidate
work=/root/k90_stage58_independent_audit
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py
system_offset=1048576
system_partition_size=1061134336
super_size=13421772800
expected_jar=d8791c7b1b9524c4cdc4a70afcf8064f9c6f18f420dbf5c99b18e24f721ee884

mkdir -p "$work/mount"
rm -f "$work/missing-selinux-labels.txt"
test "$(stat -c%s "$base")" -eq "$super_size"
test "$(stat -c%s "$candidate")" -eq "$super_size"

if [[ ! -f "$work/system.img" ]] || [[ "$(stat -c%s "$work/system.img")" -ne "$system_partition_size" ]]; then
  dd if="$candidate" of="$work/system.img" iflag=skip_bytes,count_bytes \
    skip="$system_offset" count="$system_partition_size" status=none
fi
python3 "$avb" verify_image --image "$work/system.img" > "$work/avb.txt"
fsck.erofs "$work/system.img" > "$work/fsck.txt" 2>&1
mount -t erofs -o ro,loop "$work/system.img" "$work/mount"
test "$(sha256sum "$work/mount/system/framework/services.jar" | cut -d' ' -f1)" = "$expected_jar"
test "$(getfattr -n security.selinux --only-values "$work/mount/system/framework/services.jar")" = u:object_r:system_file:s0

missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/missing-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$work/mount" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$work/mount"

cmp -n "$system_offset" "$base" "$candidate"
tail_offset=$((system_offset + system_partition_size))
tail_size=$((super_size - tail_offset))
chunk=$((tail_size / 4))
pids=()
for index in 0 1 2 3; do
  offset=$((tail_offset + index * chunk))
  length=$chunk
  if [[ "$index" -eq 3 ]]; then
    length=$((tail_size - 3 * chunk))
  fi
  cmp -n "$length" -i "$offset:$offset" "$base" "$candidate" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

candidate_hash=$(sha256sum "$candidate" | cut -d' ' -f1)
printf 'AUDIT_OK\nSUPER_SHA256=%s\nSERVICES_JAR_SHA256=%s\nMISSING_SELINUX_LABELS=%d\n' \
  "$candidate_hash" "$expected_jar" "$missing"
