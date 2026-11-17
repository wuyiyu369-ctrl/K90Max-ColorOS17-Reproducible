#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
pkg=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage69_UAH_SKIP_DEATH_FIXED
work=/root/k90_stage70_work
overlay=/root/k90_stage70_overlay
super="$pkg/images/super.img"
ext_offset=1062207488
ext_size=1087639552
super_size=13421772800

test -s "$super"
test "$(stat -c%s "$super")" -eq "$super_size"
test "$(sha256sum "$super" | cut -d' ' -f1)" = \
  d49c323e30acd9ed9fa20be144746847f051196609d84fe293571601eb4dbb46
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
python3 "$src/stage70_patch_uah_skip_remote_init.py" "$overlay/upper" \
  | tee "$work/patch.txt"

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
python3 - "$overlay/verify" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
checks = {
    "lib64/liboplus-uah-client.so": (0x1E4BC, "f303002a800a0034"),
    "lib/liboplus-uah-client.so": (0x12A18, "0446002800f06e804ff0ff3400f06ab8"),
}
for relative, (offset, expected_hex) in checks.items():
    data = (root / relative).read_bytes()
    expected = bytes.fromhex(expected_hex)
    assert data[offset:offset + len(expected)] == expected
    print(relative, hashlib.sha256(data).hexdigest())
PY
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
sha256sum "$super" | tee "$pkg/SHA256SUMS.txt"
cp "$work/"*.txt "$work/"*.log "$pkg/audit/" 2>/dev/null || true
cat > "$pkg/STATUS.txt" <<'EOF'
Stage70 UAH remote-init compatibility candidate
Base: booted Stage69; system_ext replaced in place to preserve disk space
Changed extent: system_ext only; both 32-bit and 64-bit UAH client libraries
Data wipe: no

Keeps the resolved URCC Binder reference and bypasses the donor urccInit
transaction whose reply is incompatible with the custom Android 17 service.
Runtime request/vendor-handle/release evidence is required.
EOF
echo STAGE70_REBUILD_PASSED
