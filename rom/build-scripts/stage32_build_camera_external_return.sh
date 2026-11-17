#!/usr/bin/env bash
set -euo pipefail

base=/root/k90_stage31_camera_cachefix/out/my_product.img
work=/root/k90_stage32_camera_external_return
apk=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/camera770_start_compat_test/MiuiCamera.770-start-test.apk
image_size=1138266112
apk_sha=b72e2f4f67065a76deae1da35a431ecded6614f9462abae4172b160f5861211f
image_uuid=d133458d-0e5d-58f3-b521-b1bedbb17daf
apk_mtime='2026-11-05 07:20:00 UTC'

test "$(sha256sum "$apk" | cut -d' ' -f1)" = "$apk_sha"
test "$(stat -c%s "$base")" -eq "$image_size"
test "$(blkid -o value -s UUID "$base")" = "$image_uuid"

cleanup() {
  for mount_dir in "$work/verify" "$work/merged" "$work/base_ro"; do
    mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  done
}
trap cleanup EXIT
cleanup

rm -rf -- "$work"
mkdir -p "$work"/{base_ro,upper,overlay_work,merged,out,verify}
mount -t erofs -o ro,loop "$base" "$work/base_ro"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper"
mount -t overlay overlay -o "lowerdir=$work/base_ro,upperdir=$work/upper,workdir=$work/overlay_work" "$work/merged"

install -d -o 0 -g 0 -m 0755 "$work/merged/priv-app/MiuiCamera"
install -o 0 -g 0 -m 0644 "$apk" "$work/merged/priv-app/MiuiCamera/MiuiCamera.apk"
touch -d "$apk_mtime" "$work/merged/priv-app/MiuiCamera/MiuiCamera.apk"
touch -d "$apk_mtime" "$work/upper/priv-app/MiuiCamera/MiuiCamera.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper/priv-app/MiuiCamera"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$work/upper/priv-app/MiuiCamera/MiuiCamera.apk"

mkfs.erofs -z lz4hc,12 -C 65536 -T 1793863200 -U "$image_uuid" --preserve-mtime \
  "$work/out/my_product.raw.img" "$work/merged" > "$work/out/my_product.mkfs.log" 2>&1
test "$(stat -c%s "$work/out/my_product.raw.img")" -le "$image_size"
cp --sparse=always "$work/out/my_product.raw.img" "$work/out/my_product.img"
truncate -s "$image_size" "$work/out/my_product.img"

fsck.erofs "$work/out/my_product.img" > "$work/out/my_product.fsck.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/my_product.img" "$work/verify"
test "$(blkid -o value -s UUID "$work/out/my_product.img")" = "$image_uuid"
test "$(sha256sum "$work/verify/priv-app/MiuiCamera/MiuiCamera.apk" | cut -d' ' -f1)" = "$apk_sha"
test "$(getfattr -n security.selinux --only-values "$work/verify/priv-app/MiuiCamera/MiuiCamera.apk" 2>/dev/null)" = u:object_r:system_file:s0
sha256sum "$work/out/my_product.img" "$work/verify/priv-app/MiuiCamera/MiuiCamera.apk" > "$work/out/SHA256SUMS.txt"
echo STAGE32_CAMERA_EXTERNAL_RETURN_IMAGE_OK
