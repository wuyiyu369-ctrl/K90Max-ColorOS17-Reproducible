#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage65_FAN_PERF_ABI_FIXED
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage66_FAN_PERF_URCC_FIXED
work=/root/k90_stage66_work
overlay=/root/k90_stage66_overlay

super_size=13421772800
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))

for file in "$base/images/super.img" "$src/stage62_policy_patch.c" \
            "$src/generate_erofs_file_contexts.py"; do
  test -s "$file" || { echo "MISSING: $file" >&2; exit 1; }
done
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"

rm -rf "$work" "$overlay" "$out"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify} "$out"/{images,audit}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

cc -O2 -Wall -Wextra -Werror \
  -I"$src/stage44_toolchain_source/selinux-main/libsepol/include" \
  -o "$work/stage66_policy_patch" "$src/stage62_policy_patch.c" \
  "$src/stage44_toolchain_source/selinux-main/libsepol/src/libsepol.a"

dd if="$base/images/super.img" of="$work/odm.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
test "$(stat -c%s "$work/odm.base.img")" -eq "$odm_size"
fsck.erofs "$work/odm.base.img" > "$work/fsck-odm-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.base.img" "$overlay/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"

mkdir -p "$overlay/upper/etc/selinux"
for dir in etc etc/selinux; do
  chmod --reference="$overlay/lower/$dir" "$overlay/upper/$dir"
  chown --reference="$overlay/lower/$dir" "$overlay/upper/$dir"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$dir")" \
    "$overlay/upper/$dir"
done
cp --attributes-only --preserve=all \
  "$overlay/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/upper/etc/selinux/precompiled_sepolicy"
"$work/stage66_policy_patch" \
  "$overlay/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/upper/etc/selinux/precompiled_sepolicy" \
  > "$work/policy-patch.txt"
chmod --reference="$overlay/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/upper/etc/selinux/precompiled_sepolicy"
chown --reference="$overlay/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/upper/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/upper/etc/selinux/precompiled_sepolicy"

for rule in \
  'allow stats hal_power_service:service_manager { find };' \
  'allow system_server hal_power_service:service_manager { find };' \
  'allow platform_app hal_power_service:service_manager { find };'; do
  grep -Fqx "$rule" "$work/policy-patch.txt"
done
grep -q '^POLICY_READBACK_OK ' "$work/policy-patch.txt"

mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /odm \
  "$work/odm.file_contexts" > "$work/odm-contexts.txt"
uuid=$(blkid -o value -s UUID "$work/odm.base.img")
label=$(blkid -o value -s LABEL "$work/odm.base.img" || true)
args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$uuid" --preserve-mtime \
      --mount-point=/odm --file-contexts="$work/odm.file_contexts")
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/odm.raw.img" "$overlay/merged" \
  > "$work/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/odm.raw.img" "$work/odm.img"
truncate -s "$odm_size" "$work/odm.img"

umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/odm.img" > "$work/fsck-odm.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.img" "$overlay/verify"
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/etc/selinux/precompiled_sepolicy")" = u:object_r:sepolicy_file:s0
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/missing-odm-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

# The Windows host copies the 13.4 GB base super into this path before resume.
if [[ "${K90_STAGE66_PARTITION_ONLY:-0}" == 1 ]]; then
  echo STAGE66_ODM_PARTITION_PASSED
  exit 0
fi

building="$out/images/super.img.building"
test -s "$building"
test "$(stat -c%s "$building")" -eq "$super_size"
dd if="$work/odm.img" of="$building" bs=4096 \
  seek=$((odm_offset / 4096)) conv=notrunc,fsync status=none
dd if="$building" of="$work/odm.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/odm.img" "$work/odm.readback.img"
fsck.erofs "$work/odm.readback.img" > "$work/fsck-odm-readback.txt" 2>&1

region_hash() {
  local image=$1 offset=$2 length=$3
  dd if="$image" bs=16M iflag=skip_bytes,count_bytes \
    skip="$offset" count="$length" status=none | sha256sum | cut -d' ' -f1
}
prefix_base=$(region_hash "$base/images/super.img" 0 "$odm_offset")
prefix_new=$(region_hash "$building" 0 "$odm_offset")
test "$prefix_base" = "$prefix_new"
odm_tail=$((odm_offset + odm_size))
tail_length=$((super_size - odm_tail))
tail_base=$(region_hash "$base/images/super.img" "$odm_tail" "$tail_length")
tail_new=$(region_hash "$building" "$odm_tail" "$tail_length")
test "$tail_base" = "$tail_new"
printf 'prefix sha256=%s\ntail sha256=%s\n' "$prefix_base" "$tail_base" \
  > "$work/unchanged-region-sha256.txt"

mv "$building" "$out/images/super.img"
cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$work/"*.txt "$work/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
cat > "$out/STATUS.txt" <<'EOF'
Stage66 fan/performance/URCC runtime candidate
Base: booted Stage65
Changed extent: ODM only
Data wipe: no

Adds only the three runtime-observed UAH client service-manager find rules:
- stats -> hal_power_service
- system_server -> hal_power_service
- platform_app -> hal_power_service

The fan Common strategy, performance ABI v5 mapping, identity fix and all
other Stage65 contents remain unchanged. Runtime UAH/URCC backend evidence is
required before release.
EOF
echo STAGE66_BUILD_PASSED
