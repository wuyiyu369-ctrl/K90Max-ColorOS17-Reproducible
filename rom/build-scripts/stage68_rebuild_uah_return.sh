#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
pkg=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage68_UAH_RETURN_FIXED
work=/root/k90_stage68_work
overlay=/root/k90_stage68_overlay
super="$pkg/images/super.img"
ext_offset=1062207488
ext_size=1087639552
super_size=13421772800

test -s "$super"
test "$(stat -c%s "$super")" -eq "$super_size"
rm -rf "$work" "$overlay"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

dd if="$super" of="$work/system_ext.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
fsck.erofs "$work/system_ext.base.img" > "$work/fsck-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/system_ext.base.img" "$overlay/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
mkdir -p "$overlay/upper/lib64"
chmod --reference="$overlay/lower/lib64" "$overlay/upper/lib64"
chown --reference="$overlay/lower/lib64" "$overlay/upper/lib64"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/upper/lib64"
cp --preserve=all "$overlay/lower/lib64/liboplus-uah-client.so" \
  "$overlay/upper/lib64/liboplus-uah-client.so"
python3 "$src/stage69_patch_uah_skip_death.py" \
  "$overlay/upper/lib64/liboplus-uah-client.so" | tee "$work/patch.txt"
setfattr -n security.selinux -v u:object_r:system_lib_file:s0 \
  "$overlay/upper/lib64/liboplus-uah-client.so"

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
python3 - "$overlay/verify/lib64/liboplus-uah-client.so" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1]).read_bytes()
assert d[0x1e7b4:0x1e7bc] == bytes.fromhex("e0031f2a3d000014")
PY
test "$(getfattr -n security.selinux --only-values \
  "$overlay/verify/lib64/liboplus-uah-client.so")" = u:object_r:system_lib_file:s0
missing=0
while IFS= read -r -d '' item; do
  getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || \
    missing=$((missing + 1))
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

# D: has insufficient room for a third full super. Replace only the verified
# system_ext extent in the already flashed Stage67 package, then rename it on
# the host after hashing. Stage66 remains the rollback image.
dd if="$work/system_ext.img" of="$super" bs=4096 \
  seek=$((ext_offset / 4096)) conv=notrunc,fsync status=none
dd if="$super" of="$work/readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$ext_offset" count="$ext_size" status=none
cmp "$work/system_ext.img" "$work/readback.img"
fsck.erofs "$work/readback.img" > "$work/fsck-readback.txt" 2>&1
sha256sum "$super" | tee "$pkg/SHA256SUMS.txt"
cp "$work/"*.txt "$work/"*.log "$pkg/audit/" 2>/dev/null || true
cat > "$pkg/STATUS.txt" <<'EOF'
Stage69 Android 17 UAH death-recipient compatibility candidate
Base: booted Stage68; system_ext replaced in place because D: lacked space
Changed extent: system_ext only
Data wipe: no

Keeps the resolved URCC Binder reference and skips the incompatible donor
death-recipient registration. Runtime request/vendor-handle/release evidence
is required.
EOF
echo STAGE69_REBUILD_PASSED
