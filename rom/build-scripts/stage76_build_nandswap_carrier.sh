#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage75_AOD_CARRIER_FINAL
delivery=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage76_NANDSWAP_CARRIER
patch_root=/mnt/d/K90_AOD_STAGE75_WORK
work=/root/k90_stage76_work
overlay=/root/k90_stage76_overlay
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

base_super=$base/images/super.img
output_super=$delivery/images/super.img
telephony_jar=$patch_root/telephony-common.stage76.jar

super_size=13421772800
system_offset=1048576
system_erofs_size=1049554944
system_partition_size=1061134336
system_end=$((system_offset + system_partition_size))
product_offset=2150629376
product_size=152326144
product_end=$((product_offset + product_size))
base_hash=b17da1a1e0c864de58935f6ebce2708fe77480244a44127dc41cbd1d1367ed08
base_telephony_hash=aff73c492d36bf005d4c5c0b409451546fb02bdccf1f445be88d18369a4ff399

for tool in mkfs.erofs fsck.erofs getfattr setfattr sha256sum cmp; do
  command -v "$tool" >/dev/null
done
test -s "$base_super"
test -s "$telephony_jar"
test -s "$avb"
test "$(stat -c%s "$base_super")" -eq "$super_size"
test "$(sha256sum "$base_super" | cut -d' ' -f1)" = "$base_hash"

rm -rf "$work" "$overlay" "$delivery"
mkdir -p "$work" "$delivery/images" "$delivery/audit"
mkdir -p "$overlay"/{system_lower,system_upper,system_work,system_merged,product_lower,product_upper,product_work,product_merged,verify}

cleanup() {
  for m in verify system_merged system_lower product_merged product_lower; do
    mountpoint -q "$overlay/$m" && umount "$overlay/$m" || true
  done
}
trap cleanup EXIT

dd if="$base_super" of="$work/system.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$system_offset" \
  count="$system_partition_size" status=none
dd if="$base_super" of="$work/product.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$product_offset" \
  count="$product_size" status=none
test "$(stat -c%s "$work/system.base.img")" -eq "$system_partition_size"
test "$(stat -c%s "$work/product.base.img")" -eq "$product_size"
fsck.erofs "$work/system.base.img" > "$work/fsck-system-base.txt" 2>&1
fsck.erofs "$work/product.base.img" > "$work/fsck-product-base.txt" 2>&1
python3 "$avb" info_image --image "$work/system.base.img" > "$work/avb-system-base.txt"

mount -t erofs -o ro,loop "$work/system.base.img" "$overlay/system_lower"
test "$(sha256sum "$overlay/system_lower/system/framework/telephony-common.jar" | cut -d' ' -f1)" = "$base_telephony_hash"
test -s "$overlay/system_lower/system/lib/libc++.so"
test -s "$overlay/system_lower/system/lib64/libc++.so"
libc32_hash=$(sha256sum "$overlay/system_lower/system/lib/libc++.so" | cut -d' ' -f1)
libc64_hash=$(sha256sum "$overlay/system_lower/system/lib64/libc++.so" | cut -d' ' -f1)

setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/system_lower")" \
  "$overlay/system_upper"
mkdir -p "$overlay/system_upper/system/framework"
for rel in system system/framework; do
  chmod --reference="$overlay/system_lower/$rel" "$overlay/system_upper/$rel"
  chown --reference="$overlay/system_lower/$rel" "$overlay/system_upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/system_lower/$rel")" \
    "$overlay/system_upper/$rel"
done
cp --preserve=all "$overlay/system_lower/system/framework/telephony-common.jar" \
  "$overlay/system_upper/system/framework/telephony-common.jar"
dd if="$telephony_jar" \
  of="$overlay/system_upper/system/framework/telephony-common.jar" status=none

mount -t overlay overlay \
  -o "lowerdir=$overlay/system_lower,upperdir=$overlay/system_upper,workdir=$overlay/system_work" \
  "$overlay/system_merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/system_merged" /system \
  "$work/system_file_contexts" \
  --override /system/my_reserve=u:object_r:system_file:s0 \
  > "$work/system-contexts.txt"
system_uuid=$(blkid -o value -s UUID "$work/system.base.img")
system_label=$(blkid -o value -s LABEL "$work/system.base.img" || true)
system_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$system_uuid" --preserve-mtime \
  --mount-point=/system --file-contexts="$work/system_file_contexts")
[[ -z "$system_label" ]] || system_args+=(-L "$system_label")
mkfs.erofs "${system_args[@]}" "$work/system.raw.img" "$overlay/system_merged" \
  > "$work/mkfs-system.log" 2>&1
test "$(stat -c%s "$work/system.raw.img")" -le "$system_erofs_size"
cp --sparse=always "$work/system.raw.img" "$work/system.img"
truncate -s "$system_erofs_size" "$work/system.img"
python3 "$avb" add_hashtree_footer --image "$work/system.img" \
  --partition_size "$system_partition_size" --partition_name system \
  --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
  --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$work/system.img" > "$work/avb-system.txt"
fsck.erofs "$work/system.img" > "$work/fsck-system.txt" 2>&1

mount -t erofs -o ro,loop "$work/product.base.img" "$overlay/product_lower"
test "$(sha256sum "$overlay/product_lower/lib/libc++.so" | cut -d' ' -f1)" = "$libc32_hash"
test "$(sha256sum "$overlay/product_lower/lib64/libc++.so" | cut -d' ' -f1)" = "$libc64_hash"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/product_lower")" \
  "$overlay/product_upper"
mkdir -p "$overlay/product_upper/lib" "$overlay/product_upper/lib64"
for rel in . lib lib64; do
  chmod --reference="$overlay/product_lower/$rel" "$overlay/product_upper/$rel"
  chown --reference="$overlay/product_lower/$rel" "$overlay/product_upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/product_lower/$rel")" \
    "$overlay/product_upper/$rel"
done
cp --preserve=all "$overlay/system_lower/system/lib/libc++.so" \
  "$overlay/product_upper/lib/libc++.so"
cp --preserve=all "$overlay/system_lower/system/lib64/libc++.so" \
  "$overlay/product_upper/lib64/libc++.so"
mount -t overlay overlay \
  -o "lowerdir=$overlay/product_lower,upperdir=$overlay/product_upper,workdir=$overlay/product_work" \
  "$overlay/product_merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/product_merged" /product \
  "$work/product_file_contexts" \
  --override /product/lib/libc++.so=u:object_r:system_lib_file:s0 \
  --override /product/lib64/libc++.so=u:object_r:system_lib_file:s0 \
  > "$work/product-contexts.txt"
product_uuid=$(blkid -o value -s UUID "$work/product.base.img")
product_label=$(blkid -o value -s LABEL "$work/product.base.img" || true)
product_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$product_uuid" --preserve-mtime \
  --mount-point=/product --file-contexts="$work/product_file_contexts")
[[ -z "$product_label" ]] || product_args+=(-L "$product_label")
mkfs.erofs "${product_args[@]}" "$work/product.img" "$overlay/product_merged" \
  > "$work/mkfs-product.log" 2>&1
test "$(stat -c%s "$work/product.img")" -le "$product_size"
truncate -s "$product_size" "$work/product.img"
fsck.erofs "$work/product.img" > "$work/fsck-product.txt" 2>&1

umount "$overlay/system_merged"
umount "$overlay/product_merged"
umount "$overlay/product_lower"
umount "$overlay/system_lower"

for part in system product; do
  mount -t erofs -o ro,loop "$work/$part.img" "$overlay/verify"
  missing=0
  while IFS= read -r -d '' item; do
    getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || \
      missing=$((missing + 1))
  done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
  echo "$missing" > "$work/missing-selinux-labels-$part.txt"
  test "$missing" -eq 0
  if [[ "$part" = system ]]; then
    cmp "$telephony_jar" "$overlay/verify/system/framework/telephony-common.jar"
    test "$(getfattr -n security.selinux --only-values "$overlay/verify/system/framework/telephony-common.jar")" = u:object_r:system_file:s0
  else
    test "$(sha256sum "$overlay/verify/lib/libc++.so" | cut -d' ' -f1)" = \
      "$libc32_hash"
    test "$(sha256sum "$overlay/verify/lib64/libc++.so" | cut -d' ' -f1)" = \
      "$libc64_hash"
    test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib/libc++.so")" = u:object_r:system_lib_file:s0
    test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++.so")" = u:object_r:system_lib_file:s0
    test "$(stat -c %u:%g:%a "$overlay/verify/lib/libc++.so")" = 0:0:644
    test "$(stat -c %u:%g:%a "$overlay/verify/lib64/libc++.so")" = 0:0:644
  fi
  umount "$overlay/verify"
done

cp --sparse=always "$base_super" "$delivery/images/super.img.building"
dd if="$work/system.img" of="$delivery/images/super.img.building" \
  bs=4096 seek=$((system_offset / 4096)) conv=notrunc,fsync status=progress
dd if="$work/product.img" of="$delivery/images/super.img.building" \
  bs=4096 seek=$((product_offset / 4096)) conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$output_super"
test "$(stat -c%s "$output_super")" -eq "$super_size"

cmp -n "$system_offset" "$base_super" "$output_super"
cmp -n $((product_offset - system_end)) -i "$system_end:$system_end" "$base_super" "$output_super"
cmp -n $((super_size - product_end)) -i "$product_end:$product_end" "$base_super" "$output_super"

dd if="$output_super" of="$work/system.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$system_offset" count="$system_partition_size" status=none
dd if="$output_super" of="$work/product.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$product_offset" count="$product_size" status=none
cmp "$work/system.img" "$work/system.readback.img"
cmp "$work/product.img" "$work/product.readback.img"
fsck.erofs "$work/system.readback.img" > "$work/fsck-system-readback.txt" 2>&1
fsck.erofs "$work/product.readback.img" > "$work/fsck-product-readback.txt" 2>&1
python3 "$avb" verify_image --image "$work/system.readback.img" > "$work/avb-system-readback.txt"

cp -a "$base/platform-tools" "$delivery/"
for name in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  [[ -f "$base/$name" ]] && cp "$base/$name" "$delivery/"
done
cp "$work/"*.txt "$work/"*.log "$delivery/audit/"
sha256sum "$output_super" > "$delivery/SHA256SUMS.txt"
sha256sum "$telephony_jar" > "$delivery/audit/patched-files.sha256"
printf '%s  %s\n' "$libc32_hash" '/product/lib/libc++.so' \
  >> "$delivery/audit/patched-files.sha256"
printf '%s  %s\n' "$libc64_hash" '/product/lib64/libc++.so' \
  >> "$delivery/audit/patched-files.sha256"

cat > "$delivery/STATUS.txt" <<'EOF'
Stage76 nandswap and dynamic carrier-name candidate
Base: booted Stage75
Changed partitions: system and product
Data wipe: no

- Preserves the verified Stage75 full-screen AOD integration.
- Restores standard carrier-name publication when the Oplus telephony extension
  is absent; names still come from live PLMN/SPN data and are not hard-coded.
- Adds the matching ColorOS libc++.so to the product linker namespace so the
  existing nandswap_tool can start.
- Does not claim benchmark improvement until device runtime and benchmark tests.
EOF

echo STAGE76_BUILD_PASSED
