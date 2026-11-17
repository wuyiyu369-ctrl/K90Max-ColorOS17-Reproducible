#!/usr/bin/env bash
set -euo pipefail

base=/root/k90_stage33_merge/images
cand=/root/k90_stage33_native_build/out
work=$(mktemp -d /tmp/k90-stage34-audit.XXXXXX)

cleanup() {
  for path in "$work"/mnt/*; do
    mountpoint -q "$path" && umount "$path" || true
  done
  rm -rf -- "$work"
}
trap cleanup EXIT

mkdir -p "$work"/mnt/{product31,product34,odm31,odm34} "$work"/out
mount -t erofs -o ro,loop "$base/product31.img" "$work/mnt/product31"
mount -t erofs -o ro,loop "$cand/product.img" "$work/mnt/product34"
mount -t erofs -o ro,loop "$base/odm31.img" "$work/mnt/odm31"
mount -t erofs -o ro,loop "$cand/odm.img" "$work/mnt/odm34"

snapshot() {
  local root=$1 out=$2
  (
    cd "$root"
    find . -xdev -printf '%P|%y|%m|%u|%g|%s|%l\n' | LC_ALL=C sort
  ) > "$out.meta"
  getfattr -R -d -m - --absolute-names "$root" 2>/dev/null \
    | sed "s#${root}#ROOT#g" > "$out.xattr" || true
  (
    cd "$root"
    find . -xdev -type f -print0 | LC_ALL=C sort -z \
      | xargs -0 -r sha256sum
  ) > "$out.sha256"
}

for name in product31 product34 odm31 odm34; do
  snapshot "$work/mnt/$name" "$work/out/$name"
done

for pair in 'product31 product34' 'odm31 odm34'; do
  read -r old new <<< "$pair"
  for kind in meta xattr sha256; do
    diff -u "$work/out/$old.$kind" "$work/out/$new.$kind" \
      > "/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage34_${old}_${new}_${kind}.diff" || true
  done
done

for img in "$base/product31.img" "$cand/product.img" "$base/odm31.img" "$cand/odm.img"; do
  echo "=== $img"
  fsck.erofs "$img"
  dump.erofs -s "$img"
done > /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage34_erofs_summary.txt 2>&1

echo AUDIT_COMPLETE
