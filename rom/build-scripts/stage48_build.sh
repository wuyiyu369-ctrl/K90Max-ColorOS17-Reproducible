#!/bin/bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage48_CPU_SCENE_STATEFIX
work=$root/02_Codex完整工作区/wo/stage48_work
overlay=/root/k90_stage48_overlay
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py

odm_offset_mib=10217
odm_size=1724530688
odm_offset=$((odm_offset_mib * 1024 * 1024))
odm_end=$((odm_offset + odm_size))

mkdir -p "$work/out" "$delivery/images" "$delivery/audit"
mkdir -p "$overlay"/{odm_lower,odm_upper,odm_work,odm_merged,verify}

cleanup() {
  for mount_name in verify odm_merged odm_lower; do
    mountpoint -q "$overlay/$mount_name" && umount "$overlay/$mount_name" || true
  done
}
trap cleanup EXIT

test -s "$base/images/super.img"
test -s "$src/stage48_perf_bridge.sh"
test ! -e "$delivery/images/super.img"

if [[ ! -s "$work/out/odm.base.img" ]]; then
  dd if="$base/images/super.img" of="$work/out/odm.base.img" \
    bs=1M skip="$odm_offset_mib" count=1645 status=progress
  truncate -s "$odm_size" "$work/out/odm.base.img"
fi

fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/odm_lower"

root_label=$(getfattr -n security.selinux --only-values "$overlay/odm_lower" 2>/dev/null)
setfattr -n security.selinux -v "$root_label" "$overlay/odm_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" \
  "$overlay/odm_merged"

cp "$src/stage48_perf_bridge.sh" "$overlay/odm_merged/bin/k90_perf_bridge.sh"
cp --attributes-only --preserve=all \
  "$overlay/odm_lower/bin/k90_perf_bridge.sh" \
  "$overlay/odm_upper/bin/k90_perf_bridge.sh"

uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
mkfs_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || mkfs_args+=(-L "$label")

mkfs.erofs "${mkfs_args[@]}" "$work/out/odm.raw.img" "$overlay/odm_merged" \
  > "$work/out/mkfs-odm.log" 2>&1
actual=$(stat -c%s "$work/out/odm.raw.img")
test "$actual" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"

if python3 "$avb" info_image --image "$work/out/odm.base.img" \
  > "$work/out/avb-odm-base.txt" 2>&1; then
  echo "SOURCE_HAS_AVB_REQUIRES_EXACT_FOOTER_REBUILD"
  exit 12
fi

fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"

test "$(stat -c %u:%g:%a "$overlay/verify")" = \
  "$(stat -c %u:%g:%a "$overlay/odm_lower")"
test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = \
  "$(getfattr -n security.selinux --only-values "$overlay/odm_lower" 2>/dev/null)"
cmp "$src/stage48_perf_bridge.sh" "$overlay/verify/bin/k90_perf_bridge.sh"

for item in \
  etc/selinux/precompiled_sepolicy \
  etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 \
  etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 \
  etc/selinux/odm_sepolicy.cil \
  etc/init/k90-stage44-native.rc \
  etc/build.prop; do
  cmp "$overlay/odm_lower/$item" "$overlay/verify/$item"
done

script_mode=$(stat -c %u:%g:%a "$overlay/odm_lower/bin/k90_perf_bridge.sh")
test "$(stat -c %u:%g:%a "$overlay/verify/bin/k90_perf_bridge.sh")" = "$script_mode"
script_context=$(getfattr -n security.selinux --only-values \
  "$overlay/odm_lower/bin/k90_perf_bridge.sh" 2>/dev/null)
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/bin/k90_perf_bridge.sh" 2>/dev/null)" = "$script_context"
umount "$overlay/verify"

cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" \
  bs=1M seek="$odm_offset_mib" conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$delivery/images/super.img"

cmp -n "$odm_offset" "$base/images/super.img" "$delivery/images/super.img"
cmp -i "$odm_end:$odm_end" "$base/images/super.img" "$delivery/images/super.img"

dd if="$delivery/images/super.img" of="$work/out/odm.readback.img" \
  bs=1M skip="$odm_offset_mib" count=1645 status=none
truncate -s "$odm_size" "$work/out/odm.readback.img"
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
fsck.erofs "$work/out/odm.readback.img" > "$work/out/fsck-odm-readback.txt" 2>&1

cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
cp "$work/out/"fsck-*.txt "$work/out/mkfs-odm.log" "$delivery/audit/"

sha256sum "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"
sha256sum "$work/out/odm.img" > "$delivery/audit/odm.sha256"
sha256sum "$src/stage48_perf_bridge.sh" > "$delivery/audit/k90_perf_bridge.sha256"

cat > "$delivery/STATUS.txt" <<'EOF'
Stage48 CPU scene state fix
Base: Stage45_UNIPERF_FAN
Changed partition: odm only
Data wipe: no
Runtime device validation: pending
EOF

cat > "$delivery/audit/STAGE48_CHANGES.txt" <<'EOF'
1. Persist performance-scene ownership across daemon restarts.
2. Force mi_thermald table reload when sconfig value already equals target.
3. Recover stale managed game scenes at daemon startup.
4. Preserve the original Xiaomi thermal tables and temperature protection.
EOF

echo STAGE48_OFFLINE_BUILD_PASSED
