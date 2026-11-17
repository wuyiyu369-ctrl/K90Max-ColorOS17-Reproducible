#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
pre=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage65_PRE_FAN_PERF_ABI
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage65_FAN_PERF_ABI_FIXED
work=/root/k90_stage65_finalize
overlay=/root/k90_stage65_finalize_overlay

super_size=13421772800
manifest_offset=$((4499456 * 512))
manifest_size=$((1152 * 512))
my_product_offset=$((4501504 * 512))
my_product_size=$((2223176 * 512))
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))

test -s "$pre/images/super.img"
test -s "$src/stage65_fan_configs_v2.xml"
test "$(stat -c%s "$pre/images/super.img")" -eq "$super_size"
rm -rf "$work" "$overlay" "$out"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify} "$out"/{images,audit}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

extract_extent() {
  local name=$1 offset=$2 length=$3
  dd if="$pre/images/super.img" of="$work/$name.base.img" bs=16M \
    iflag=skip_bytes,count_bytes skip="$offset" count="$length" status=none
  test "$(stat -c%s "$work/$name.base.img")" -eq "$length"
  fsck.erofs "$work/$name.base.img" > "$work/fsck-$name-base.txt" 2>&1
}

rebuild_my_product() {
  extract_extent my_product "$my_product_offset" "$my_product_size"
  mount -t erofs -o ro,loop "$work/my_product.base.img" "$overlay/lower"
  setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" "$overlay/upper"
  mkdir -p "$overlay/upper/etc/fan_configs"
  setfattr -n security.selinux -v u:object_r:system_file:s0 \
    "$overlay/upper/etc" "$overlay/upper/etc/fan_configs"
  install -m 0644 "$src/stage65_fan_configs_v2.xml" \
    "$overlay/upper/etc/fan_configs/fan_configs_v2.xml"
  setfattr -n security.selinux -v u:object_r:system_file:s0 \
    "$overlay/upper/etc/fan_configs/fan_configs_v2.xml"
  mount -t overlay overlay \
    -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
    "$overlay/merged"

  local uuid label
  uuid=$(blkid -o value -s UUID "$work/my_product.base.img")
  label=$(blkid -o value -s LABEL "$work/my_product.base.img" || true)
  local args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$uuid" --preserve-mtime)
  [[ -z "$label" ]] || args+=(-L "$label")
  mkfs.erofs "${args[@]}" "$work/my_product.raw.img" "$overlay/merged" \
    > "$work/mkfs-my_product.log" 2>&1
  test "$(stat -c%s "$work/my_product.raw.img")" -le "$my_product_size"
  cp --sparse=always "$work/my_product.raw.img" "$work/my_product.img"
  truncate -s "$my_product_size" "$work/my_product.img"
  umount "$overlay/merged"
  umount "$overlay/lower"
  rm -rf "$overlay"/{upper,work,merged}
  mkdir -p "$overlay"/{upper,work,merged}

  fsck.erofs "$work/my_product.img" > "$work/fsck-my_product.txt" 2>&1
  mount -t erofs -o ro,loop "$work/my_product.img" "$overlay/verify"
  cmp "$src/stage65_fan_configs_v2.xml" "$overlay/verify/etc/fan_configs/fan_configs_v2.xml"
  grep -q '<strategy name="Common" smart_shifting="true">' \
    "$overlay/verify/etc/fan_configs/fan_configs_v2.xml"
  test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/fan_configs/fan_configs_v2.xml")" = \
    u:object_r:system_file:s0
  umount "$overlay/verify"
}

rebuild_manifest() {
  extract_extent my_manifest "$manifest_offset" "$manifest_size"
  mount -t erofs -o ro,loop "$work/my_manifest.base.img" "$overlay/lower"
  setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" "$overlay/upper"
  cp --attributes-only --preserve=all "$overlay/lower/build.prop" "$overlay/upper/build.prop"
  cp "$overlay/lower/build.prop" "$work/build.prop"
  sed -i \
    -e 's/^ro\.product\.model=.*/ro.product.model=OnePlus Ace 6 Ultimate/' \
    -e 's/^ro\.product\.bootimage\.model=.*/ro.product.bootimage.model=OnePlus Ace 6 Ultimate/' \
    -e 's/^ro\.vendor\.oplus\.market\.name=.*/ro.vendor.oplus.market.name=一加 Ace 6 至尊版/' \
    -e 's/^ro\.product\.marketname=.*/ro.product.marketname=一加 Ace 6 至尊版/' \
    "$work/build.prop"
  for key in ro.config.bt_name ro.config.wifi_ap_ssid; do
    if grep -q "^$key=" "$work/build.prop"; then
      sed -i "s/^$key=.*/$key=一加 Ace 6 至尊版/" "$work/build.prop"
    else
      printf '%s\n' "$key=一加 Ace 6 至尊版" >> "$work/build.prop"
    fi
  done
  cp "$work/build.prop" "$overlay/upper/build.prop"
  chmod --reference="$overlay/lower/build.prop" "$overlay/upper/build.prop"
  chown --reference="$overlay/lower/build.prop" "$overlay/upper/build.prop"
  setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/upper/build.prop"
  mount -t overlay overlay \
    -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
    "$overlay/merged"

  python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /my_manifest \
    "$work/my_manifest.file_contexts" \
    --override /my_manifest/build.prop=u:object_r:vendor_file:s0 \
    > "$work/my_manifest-contexts.txt"
  local uuid label
  uuid=$(blkid -o value -s UUID "$work/my_manifest.base.img")
  label=$(blkid -o value -s LABEL "$work/my_manifest.base.img" || true)
  local args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$uuid" --preserve-mtime)
  [[ -z "$label" ]] || args+=(-L "$label")
  args+=(--mount-point=/my_manifest --file-contexts="$work/my_manifest.file_contexts")
  mkfs.erofs "${args[@]}" "$work/my_manifest.raw.img" "$overlay/merged" \
    > "$work/mkfs-my_manifest.log" 2>&1
  test "$(stat -c%s "$work/my_manifest.raw.img")" -le "$manifest_size"
  cp --sparse=always "$work/my_manifest.raw.img" "$work/my_manifest.img"
  truncate -s "$manifest_size" "$work/my_manifest.img"
  umount "$overlay/merged"
  umount "$overlay/lower"
  fsck.erofs "$work/my_manifest.img" > "$work/fsck-my_manifest.txt" 2>&1
  mount -t erofs -o ro,loop "$work/my_manifest.img" "$overlay/verify"
  grep -q '^ro.product.model=OnePlus Ace 6 Ultimate$' "$overlay/verify/build.prop"
  grep -q '^ro.product.bootimage.model=OnePlus Ace 6 Ultimate$' "$overlay/verify/build.prop"
  grep -q '^ro.vendor.oplus.market.name=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
  test "$(getfattr -n security.selinux --only-values "$overlay/verify/build.prop")" = \
    u:object_r:vendor_file:s0
  umount "$overlay/verify"
}

rebuild_my_product
rebuild_manifest

if [[ "${K90_STAGE65_PARTITIONS_ONLY:-0}" == 1 ]]; then
  trap - EXIT
  cleanup
  exit 0
fi

building="$out/images/super.img.building"
cp --sparse=always "$pre/images/super.img" "$building"
dd if="$work/my_manifest.img" of="$building" bs=4096 \
  seek=$((manifest_offset / 4096)) conv=notrunc,fsync status=none
dd if="$work/my_product.img" of="$building" bs=4096 \
  seek=$((my_product_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_size"

dd if="$building" of="$work/my_manifest.readback.img" bs=16M iflag=skip_bytes,count_bytes \
  skip="$manifest_offset" count="$manifest_size" status=none
dd if="$building" of="$work/my_product.readback.img" bs=16M iflag=skip_bytes,count_bytes \
  skip="$my_product_offset" count="$my_product_size" status=none
cmp "$work/my_manifest.img" "$work/my_manifest.readback.img"
cmp "$work/my_product.img" "$work/my_product.readback.img"

compare_unchanged_region() {
  local name=$1 offset=$2 length=$3 source_hash built_hash
  source_hash=$(dd if="$pre/images/super.img" bs=16M iflag=skip_bytes,count_bytes \
    skip="$offset" count="$length" status=none | sha256sum | cut -d' ' -f1)
  built_hash=$(dd if="$building" bs=16M iflag=skip_bytes,count_bytes \
    skip="$offset" count="$length" status=none | sha256sum | cut -d' ' -f1)
  test "$source_hash" = "$built_hash"
  printf '%s offset=%s length=%s sha256=%s\n' \
    "$name" "$offset" "$length" "$source_hash" \
    >> "$work/unchanged-region-sha256.txt"
}

: > "$work/unchanged-region-sha256.txt"
compare_unchanged_region prefix 0 "$manifest_offset"
manifest_gap_start=$((manifest_offset + manifest_size))
compare_unchanged_region manifest_to_my_product "$manifest_gap_start" \
  "$((my_product_offset - manifest_gap_start))"
between_start=$((my_product_offset + my_product_size))
compare_unchanged_region my_product_to_odm "$between_start" \
  "$((odm_offset - between_start))"
odm_tail=$((odm_offset + odm_size))
compare_unchanged_region odm "$odm_offset" "$odm_size"
compare_unchanged_region odm_to_end "$odm_tail" "$((super_size - odm_tail))"

mv "$building" "$out/images/super.img"
cp -a "$pre/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$pre/$file" || cp "$pre/$file" "$out/"
done
cp "$pre/audit/"* "$out/audit/" 2>/dev/null || true
cp "$work/"*.txt "$work/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/my_manifest.img" "$work/my_product.img" > "$out/audit/finalized-partitions-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage65 fan/performance ABI integration candidate
Base: Stage63 stable image
Changed extents: my_manifest, my_product, odm
Data wipe: no

Candidate changes:
- Adds the missing v2 Common fan strategy while retaining Ace7 1-20 fan levels.
- Aligns the Oplus performance Binder service to the device's version-5 transaction table.
- Keeps URCC translation and Xiaomi UniPerf/MTK backend integration from Stage64 source.
- Uses ASCII immutable model values to avoid invalid HTTP header crashes.
- Keeps Chinese market, Bluetooth and hotspot display names.

Only runtime evidence after flashing can promote this candidate to released.
EOF

echo STAGE65_FINALIZE_PASSED
