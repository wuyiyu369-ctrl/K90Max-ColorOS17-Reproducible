#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
pkg=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage77_INTEGRATED
super=$pkg/images/super.img
work=/root/k90_stage77_policy_fix
overlay=/root/k90_stage77_policy_fix_overlay
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
super_size=13421772800
old_hash=0ba8841ef39f491577ffe1a916eea3ee48c7a4933f8be832ba86007415e914e4

test -s "$super"
test "$(stat -c%s "$super")" -eq "$super_size"
test "$(sha256sum "$super" | cut -d' ' -f1)" = "$old_hash"
rm -rf "$work" "$overlay"
mkdir -p "$work" "$overlay"/{lower,upper,work,merged,verify}
cleanup() {
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

dd if="$super" of="$work/odm.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
fsck.erofs "$work/odm.base.img" > "$work/fsck-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/odm.base.img" "$overlay/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
mkdir -p "$overlay/upper/etc/selinux" "$overlay/upper/lib64"
for rel in etc etc/selinux lib64; do
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done
cp --preserve=all "$overlay/lower/etc/selinux/odm_sepolicy.cil" \
  "$overlay/upper/etc/selinux/odm_sepolicy.cil"
python3 - "$overlay/upper/etc/selinux/odm_sepolicy.cil" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
old = "(allow oplus_game_service hal_power_service (service_manager (find)))"
new = "(typeattributeset hal_power_client (oplus_game_service))"
if t.count(old) != 1:
    raise SystemExit("unexpected Stage77 game-service rule count")
p.write_text(t.replace(old, new))
PY
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/upper/etc/selinux/odm_sepolicy.cil"

# Preserve the camera-critical library explicitly during the EROFS rebuild.
cp -a "$overlay/lower/lib64/libc++_shared.so" "$overlay/upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/upper/lib64/libc++_shared.so"
mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /odm \
  "$work/file_contexts" \
  --override /odm/etc/selinux/odm_sepolicy.cil=u:object_r:sepolicy_file:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  > "$work/contexts.txt"
uuid=$(blkid -o value -s UUID "$work/odm.base.img")
label=$(blkid -o value -s LABEL "$work/odm.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime \
  --mount-point=/odm --file-contexts="$work/file_contexts")
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/odm.raw.img" "$overlay/merged" \
  > "$work/mkfs.log" 2>&1
test "$(stat -c%s "$work/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/odm.raw.img" "$work/odm.img"
truncate -s "$odm_size" "$work/odm.img"
umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/odm.img" > "$work/fsck.txt" 2>&1

mount -t erofs -o ro,loop "$work/odm.img" "$overlay/verify"
grep -q '^(typeattributeset hal_power_client (oplus_game_service))$' \
  "$overlay/verify/etc/selinux/odm_sepolicy.cil"
! grep -q '^(allow oplus_game_service hal_power_service ' \
  "$overlay/verify/etc/selinux/odm_sepolicy.cil"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++_shared.so")" = \
  u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || missing=$((missing + 1))
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
echo "$missing" > "$work/missing-labels.txt"
test "$missing" -eq 0
umount "$overlay/verify"

# Patch only the ODM extent of the not-yet-flashed Stage77 artifact.
dd if="$work/odm.img" of="$super" bs=4096 seek=$((odm_offset / 4096)) \
  conv=notrunc,fsync status=progress
dd if="$super" of="$work/odm.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/odm.img" "$work/odm.readback.img"
fsck.erofs "$work/odm.readback.img" > "$work/fsck-readback.txt" 2>&1
sha256sum "$super" > "$pkg/SHA256SUMS.txt"
cp "$work/"*.txt "$work/"*.log "$pkg/audit/" 2>/dev/null || true
echo STAGE77_GAME_POLICY_FIX_PASSED
