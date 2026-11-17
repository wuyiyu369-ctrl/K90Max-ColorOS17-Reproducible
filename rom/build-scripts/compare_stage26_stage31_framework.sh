#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage33_merge
mkdir -p "$work/m26" "$work/m31"
cleanup() {
  mountpoint -q "$work/m26" && umount "$work/m26" || true
  mountpoint -q "$work/m31" && umount "$work/m31" || true
}
trap cleanup EXIT
cleanup
mount -t erofs -o ro,loop "$work/images/system26.img" "$work/m26"
mount -t erofs -o ro,loop "$work/images/system31.img" "$work/m31"

for dex in classes.dex classes2.dex classes3.dex classes4.dex; do
  for stage in 26 31; do
    jar="$work/m${stage}/system/framework/framework.jar"
    hash=$(unzip -p "$jar" "$dex" | sha256sum | cut -d' ' -f1)
    printf 'stage%s %s %s\n' "$stage" "$dex" "$hash"
  done
done
