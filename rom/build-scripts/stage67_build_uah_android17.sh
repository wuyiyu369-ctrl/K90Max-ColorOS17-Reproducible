#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage66_FAN_PERF_URCC_FIXED
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage67_UAH_ANDROID17_FIXED
work=/root/k90_stage67_work
overlay=/root/k90_stage67_overlay

super_size=13421772800
ext_offset=1062207488
ext_size=1087639552

test -s "$base/images/super.img"
test -s "$src/stage67_patch_uah_android17.py"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
if [[ -e "$out" ]]; then
  test -z "$(find "$out" -type f -print -quit)"
fi

rm -rf "$work" "$overlay"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify} "$out"/{images,audit}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

dd if="$base/images/super.img" of="$work/system_ext.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
test "$(stat -c%s "$work/system_ext.base.img")" -eq "$ext_size"
fsck.erofs "$work/system_ext.base.img" > "$work/fsck-system_ext-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/system_ext.base.img" "$overlay/lower"

setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
mkdir -p "$overlay/upper/lib" "$overlay/upper/lib64"
for dir in lib lib64; do
  chmod --reference="$overlay/lower/$dir" "$overlay/upper/$dir"
  chown --reference="$overlay/lower/$dir" "$overlay/upper/$dir"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$dir")" \
    "$overlay/upper/$dir"
done
for file in lib/liboplus-uah-client.so lib64/liboplus-uah-client.so; do
  cp --preserve=all "$overlay/lower/$file" "$overlay/upper/$file"
done

python3 "$src/stage67_patch_uah_android17.py" "$overlay/upper" \
  | tee "$work/uah-patch.txt"

for file in lib/liboplus-uah-client.so lib64/liboplus-uah-client.so; do
  chmod --reference="$overlay/lower/$file" "$overlay/upper/$file"
  chown --reference="$overlay/lower/$file" "$overlay/upper/$file"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$file")" \
    "$overlay/upper/$file"
done

# Stage24 rebuilt this brightness XML without an xattr. Preserve its contents
# byte-for-byte, but restore the label required for a complete EROFS rebuild.
mkdir -p "$overlay/upper/etc"
chmod --reference="$overlay/lower/etc" "$overlay/upper/etc"
chown --reference="$overlay/lower/etc" "$overlay/upper/etc"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/upper/etc"
cp --preserve=mode,ownership,timestamps \
  "$overlay/lower/etc/display_brightness_config_default.xml" \
  "$overlay/upper/etc/display_brightness_config_default.xml"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$overlay/upper/etc/display_brightness_config_default.xml"

mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /system_ext \
  "$work/system_ext.file_contexts" > "$work/system_ext-contexts.txt"

uuid=$(blkid -o value -s UUID "$work/system_ext.base.img")
label=$(blkid -o value -s LABEL "$work/system_ext.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime \
      --mount-point=/system_ext --file-contexts="$work/system_ext.file_contexts")
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/system_ext.raw.img" "$overlay/merged" \
  > "$work/mkfs-system_ext.log" 2>&1
test "$(stat -c%s "$work/system_ext.raw.img")" -le "$ext_size"
cp --sparse=always "$work/system_ext.raw.img" "$work/system_ext.img"
truncate -s "$ext_size" "$work/system_ext.img"

umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/system_ext.img" > "$work/fsck-system_ext.txt" 2>&1
mount -t erofs -o ro,loop "$work/system_ext.img" "$overlay/verify"

python3 - "$overlay/verify" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
checks = {
    "lib64/liboplus-uah-client.so": (0x1e810, bytes.fromhex("27000014")),
    "lib/liboplus-uah-client.so": (0x12c6c, bytes.fromhex("0021")),
}
for rel, (off, expected) in checks.items():
    data = (root / rel).read_bytes()
    assert data[off:off + len(expected)] == expected, rel
PY
for file in lib/liboplus-uah-client.so lib64/liboplus-uah-client.so; do
  test "$(getfattr -n security.selinux --only-values "$overlay/verify/$file")" = \
    u:object_r:system_lib_file:s0
done
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/etc/display_brightness_config_default.xml")" = \
  u:object_r:system_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify")" = \
  u:object_r:system_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/missing-system_ext-selinux-labels.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

building="$out/images/super.img.building"
cp --sparse=always "$base/images/super.img" "$building"
dd if="$work/system_ext.img" of="$building" bs=4096 \
  seek=$((ext_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_size"

dd if="$building" of="$work/system_ext.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
cmp "$work/system_ext.img" "$work/system_ext.readback.img"
fsck.erofs "$work/system_ext.readback.img" > "$work/fsck-system_ext-readback.txt" 2>&1

region_hash() {
  dd if="$1" bs=16M iflag=skip_bytes,count_bytes skip="$2" count="$3" \
    status=none | sha256sum | cut -d' ' -f1
}
test "$(region_hash "$base/images/super.img" 0 "$ext_offset")" = \
  "$(region_hash "$building" 0 "$ext_offset")"
tail_start=$((ext_offset + ext_size))
test "$(region_hash "$base/images/super.img" "$tail_start" "$((super_size-tail_start))")" = \
  "$(region_hash "$building" "$tail_start" "$((super_size-tail_start))")"

mv "$building" "$out/images/super.img"
cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$work/"*.txt "$work/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
cat > "$out/STATUS.txt" <<'EOF'
Stage67 Android 17 UAH compatibility candidate
Base: booted Stage66
Changed extent: system_ext only
Data wipe: no

The 32-bit and 64-bit Oplus UAH clients retain the connected URCC service when
Android 17 rejects the legacy death-recipient cookie/onUnlink combination.
Fan, performance/URCC services, camera and all other Stage66 extents are byte
identical. Runtime request/vendor-handle/release evidence is required.
EOF
echo STAGE67_BUILD_PASSED
