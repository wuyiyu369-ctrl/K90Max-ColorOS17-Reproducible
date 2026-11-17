#!/usr/bin/env bash
set -euo pipefail

img=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage25_perf/final_extract/system_a_a.img
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage25_perf
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py
mnt=/root/k90_stage25_final_verify
test -f "$img"
test -f "$root/framework.stage25.jar"
test -f "$root/oplus-framework.stage25.jar"
ln -f "$img" "$(dirname "$img")/system.img"
if ! grep -q 'Successfully verified sha256 hashtree' "$root/final_extract/avb-verify.txt" 2>/dev/null; then
  python3 "$avb" verify_image --image "$img" > "$root/final_extract/avb-verify.txt"
fi
fsck.erofs "$img" > "$root/final_extract/fsck.txt" 2>&1
! grep -Eqi 'bogus|corruption|error|failed' "$root/final_extract/fsck.txt"
mkdir -p "$mnt"
mountpoint -q "$mnt" && umount "$mnt"
mount -t erofs -o ro,loop "$img" "$mnt"
trap 'umount "$mnt" 2>/dev/null || true' EXIT
test "$(getfattr -n security.selinux --only-values "$mnt" 2>/dev/null)" = 'u:object_r:rootfs:s0'
test "$(blkid -o value -s UUID "$img")" = '212ef468-c526-563b-babf-8465c924ade4'
test "$(sha256sum "$mnt/system/framework/framework.jar" | cut -d' ' -f1)" = "$(sha256sum "$root/framework.stage25.jar" | cut -d' ' -f1)"
test "$(sha256sum "$mnt/system/framework/oplus-framework.jar" | cut -d' ' -f1)" = "$(sha256sum "$root/oplus-framework.stage25.jar" | cut -d' ' -f1)"
test "$(sha256sum "$mnt/system/framework/telephony-common.jar" | cut -d' ' -f1)" = '235f3189ba172e3fce471aeba7c7e9a9cc2f88c19c5986ffb8a459675fea146f'
for file in framework.jar oplus-framework.jar telephony-common.jar; do
  test "$(getfattr -n security.selinux --only-values "$mnt/system/framework/$file" 2>/dev/null)" = 'u:object_r:system_file:s0'
done
echo STAGE25_TRUE_SYSTEM_OK
