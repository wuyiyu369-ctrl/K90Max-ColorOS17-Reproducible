#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
pkg=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage74_URCC_FULL_CLIENT
super="$pkg/images/super.img"
work=/root/k90_stage74_work
overlay=/root/k90_stage74_overlay
ext_offset=1062207488
ext_size=1087639552
super_size=13421772800
base_hash=781aca46fde4681e41f5d5074a6ef2c3f498ee6af94c226e4d6119787f7aafbc

test -s "$super"
test -s "$src/stage69_live_uah64.so"
test -s "$src/stage69_live_uah32.so"
test "$(stat -c%s "$super")" -eq "$super_size"
test "$(sha256sum "$super" | cut -d' ' -f1)" = "$base_hash"
test "$(sha256sum "$src/stage69_live_uah64.so" | cut -d' ' -f1)" = \
  4052fcf3e29ce32706f63083468762fdd135c5f6fb18bfefcd6c329fa3c02d28
test "$(sha256sum "$src/stage69_live_uah32.so" | cut -d' ' -f1)" = \
  b51f58a8f898c8dd00814638af8ac6b4e184384d8d5916188914198096bf3f61

rm -rf "$work" "$overlay"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

# Bind the untouched regions so an incorrect offset cannot silently alter ODM,
# system, product or metadata outside system_ext.
dd if="$super" bs=16M iflag=count_bytes count="$ext_offset" status=none \
  | sha256sum | tee "$work/pre-system_ext-before.sha256"
tail_offset=$((ext_offset + ext_size))
tail_size=$((super_size - tail_offset))
dd if="$super" bs=16M iflag=skip_bytes,count_bytes skip="$tail_offset" \
  count="$tail_size" status=none | sha256sum \
  | tee "$work/post-system_ext-before.sha256"

dd if="$super" of="$work/system_ext.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
fsck.erofs "$work/system_ext.base.img" > "$work/fsck-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/system_ext.base.img" "$overlay/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
for rel in lib lib64; do
  mkdir -p "$overlay/upper/$rel"
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
  cp --preserve=all "$overlay/lower/$rel/liboplus-uah-client.so" \
    "$overlay/upper/$rel/liboplus-uah-client.so"
done
cp "$src/stage69_live_uah64.so" \
  "$overlay/upper/lib64/liboplus-uah-client.so"
cp "$src/stage69_live_uah32.so" \
  "$overlay/upper/lib/liboplus-uah-client.so"
for rel in lib/liboplus-uah-client.so lib64/liboplus-uah-client.so; do
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux -v u:object_r:system_lib_file:s0 \
    "$overlay/upper/$rel"
done

mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /system_ext \
  "$work/file_contexts" > "$work/contexts.txt"
uuid=$(blkid -o value -s UUID "$work/system_ext.base.img")
label=$(blkid -o value -s LABEL "$work/system_ext.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime \
      --mount-point=/system_ext --file-contexts="$work/file_contexts")
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/system_ext.raw.img" "$overlay/merged" \
  > "$work/mkfs.log" 2>&1
test "$(stat -c%s "$work/system_ext.raw.img")" -le "$ext_size"
cp --sparse=always "$work/system_ext.raw.img" "$work/system_ext.img"
truncate -s "$ext_size" "$work/system_ext.img"
umount "$overlay/merged"
umount "$overlay/lower"

fsck.erofs "$work/system_ext.img" > "$work/fsck.txt" 2>&1
mount -t erofs -o ro,loop "$work/system_ext.img" "$overlay/verify"
cmp "$src/stage69_live_uah64.so" \
  "$overlay/verify/lib64/liboplus-uah-client.so"
cmp "$src/stage69_live_uah32.so" \
  "$overlay/verify/lib/liboplus-uah-client.so"
for rel in lib/liboplus-uah-client.so lib64/liboplus-uah-client.so; do
  test "$(getfattr -n security.selinux --only-values "$overlay/verify/$rel")" = \
    u:object_r:system_lib_file:s0
done
missing=0
while IFS= read -r -d '' item; do
  getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || \
    missing=$((missing + 1))
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

dd if="$work/system_ext.img" of="$super" bs=4096 \
  seek=$((ext_offset / 4096)) conv=notrunc,fsync status=none
dd if="$super" of="$work/readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
cmp "$work/system_ext.img" "$work/readback.img"
fsck.erofs "$work/readback.img" > "$work/fsck-readback.txt" 2>&1

dd if="$super" bs=16M iflag=count_bytes count="$ext_offset" status=none \
  | sha256sum | tee "$work/pre-system_ext-after.sha256"
dd if="$super" bs=16M iflag=skip_bytes,count_bytes skip="$tail_offset" \
  count="$tail_size" status=none | sha256sum \
  | tee "$work/post-system_ext-after.sha256"
cmp "$work/pre-system_ext-before.sha256" "$work/pre-system_ext-after.sha256"
cmp "$work/post-system_ext-before.sha256" "$work/post-system_ext-after.sha256"

sha256sum "$super" | tee "$pkg/SHA256SUMS.txt"
cp "$work/"*.txt "$work/"*.log "$work/"*.sha256 "$pkg/audit/" 2>/dev/null || true
cat > "$pkg/STATUS.txt" <<'EOF'
Stage74 full ColorOS UAH client with Android 17 URCC ABI alignment
Base: booted Stage73; system_ext replaced in place to preserve disk space
Changed extent: system_ext only; both UAH client libraries
Data wipe: no

Restores the Stage69 UAH clients, which retain the Android 17 Binder-reference
and death-recipient compatibility fixes but do not bypass remote urccInit.
The Stage73 Android 17 vtable-aligned URCC service in ODM is preserved exactly.
Fan, camera, performance service, policies and all other extents are unchanged.

Runtime request, matching release, service survival, Parcel cleanliness and
idle recovery are required before calling the scheduling chain complete.
EOF
echo STAGE74_REBUILD_PASSED
