#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage48_CPU_SCENE_STATEFIX
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX
work=$root/02_Codex完整工作区/wo/stage49_work
jar=$src/stage49_services.aligned.jar
mount_dir=/root/k90_stage49_super_verify

super_size=13421772800
system_offset=1048576
system_partition_size=1061134336
system_end=$((system_offset + system_partition_size))
odm_offset=$((10217 * 1024 * 1024))
odm_size=1724530688
odm_tail=$((odm_offset + odm_size - 4194304))
file_tail=$((super_size - 4194304))

test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
test "$(stat -c%s "$delivery/images/super.img")" -eq "$super_size"
test "$(stat -c%s "$work/out/system.img")" -eq "$system_partition_size"
test -s "$jar"

# The only mutating command in the build was a bounded dd at system_offset.
# Sample every critical boundary to detect a wrong seek, count, or truncation.
cmp -n "$system_offset" "$base/images/super.img" "$delivery/images/super.img"
cmp -n 4194304 -i "$system_end:$system_end" "$base/images/super.img" "$delivery/images/super.img"
cmp -n 4194304 -i "$odm_offset:$odm_offset" "$base/images/super.img" "$delivery/images/super.img"
cmp -n 4194304 -i "$odm_tail:$odm_tail" "$base/images/super.img" "$delivery/images/super.img"
cmp -n 4194304 -i "$file_tail:$file_tail" "$base/images/super.img" "$delivery/images/super.img"

mkdir -p "$mount_dir"
mountpoint -q "$mount_dir" && umount "$mount_dir" || true
mount -t erofs -o ro,loop,offset="$system_offset" "$delivery/images/super.img" "$mount_dir"
trap 'mountpoint -q "$mount_dir" && umount "$mount_dir" || true' EXIT
cmp "$jar" "$mount_dir/system/framework/services.jar"
test "$(stat -c %u:%g:%a "$mount_dir/system/framework/services.jar")" = 0:0:644
test "$(getfattr -n security.selinux --only-values "$mount_dir/system/framework/services.jar" 2>/dev/null)" = \
  u:object_r:system_file:s0
umount "$mount_dir"
trap - EXIT

python3 "$root/02_Codex完整工作区/wo/tools/avb/avbtool.py" \
  verify_image --image "$work/out/system.img" > "$work/out/avb-system.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1

mkdir -p "$delivery/audit"
cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
cp "$work/out/"fsck-*.txt "$work/out/"avb-*.txt "$work/out/mkfs-system.log" "$delivery/audit/"
cp "$src/stage49_services_audit.txt" "$delivery/audit/"
sha256sum "$work/out/system.img" > "$delivery/audit/system.sha256"
sha256sum "$jar" > "$delivery/audit/services.jar.sha256"

cat > "$delivery/STATUS.txt" <<'EOF'
Stage49 fan setting bridge fix
Base: Stage48_CPU_SCENE_STATEFIX
Changed partition: system only
Data wipe: no
Fan fix: static validation passed; device validation pending
Single-SIM-in-slot-2 registration: not patched; root cause not proven by supplied logs
EOF

cat > "$delivery/audit/STAGE49_CHANGES.txt" <<'EOF'
1. Observe the ACE7 UI key cooling_fan_mode instead of the unused cooling_fan_mode_v3 key.
2. Read cooling_fan_mode first while retaining cooling_fan_mode_v3 as a compatibility fallback.
3. Preserve the Stage48 ODM performance, camera, radio, and native bridge contents.
4. Do not spoof service state, signal bars, or carrier registration.
EOF

cat > "$delivery/audit/SUPER_BOUNDARY_AUDIT.txt" <<'EOF'
SUPER_SIZE_IDENTICAL
SUPER_HEADER_IDENTICAL
POST_SYSTEM_BOUNDARY_SAMPLE_IDENTICAL
ODM_START_SAMPLE_IDENTICAL
ODM_END_SAMPLE_IDENTICAL
SUPER_TAIL_SAMPLE_IDENTICAL
SYSTEM_EXTENT_MOUNT_READBACK_PASSED
EOF

echo STAGE49_FINALIZE_PASSED
