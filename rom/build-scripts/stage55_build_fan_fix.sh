#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery
base=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage53_LABELS_FAN
out=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage55_FAN_EXEC
work=$root/02_Codex完整工作区/wo/stage55_work
overlay=/root/k90_stage55_overlay
ndk=/root/ndk29_tool/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64

# These are the actual extents from the Stage53 super metadata, not
# rounded guesses.  The Stage53 super image is the bootable baseline.
my_product_off=$((4501504 * 512))
my_product_len=$((2223176 * 512))
odm_off=$((20924416 * 512))
odm_len=$((3368224 * 512))
super_len=13421772800

# Assemble directly in the delivery location after staging all immutable
# inputs and checks.  A second 13GiB image is impossible with the current D
# budget, and an in-memory WSL copy is unsafe with a 7.6GiB guest limit.

need_file() { test -s "$1" || { echo "MISSING: $1" >&2; exit 1; }; }
need_file "$base/images/super.img"
need_file "$src/stage44_native_bridge.c"
need_file "$src/stage44_payload/k90-stage44-native.rc"
need_file /root/k90_native_bridge_stage55
test "$(stat -c%s "$base/images/super.img")" -eq "$super_len"

mkdir -p "$work/parts" "$work/merged" "$out/images" "$out/audit"
cleanup() {
  for m in "$overlay/system" "$overlay/my_product" "$overlay/odm" "$overlay/verify"; do
    mountpoint -q "$m" && umount "$m" || true
  done
}
trap cleanup EXIT
rm -rf "$overlay"; mkdir -p "$overlay"/{my_product,odm,verify}
mkdir -p "$overlay"/{my_product.upper,my_product.work,odm.upper,odm.work,my_product.merged,odm.merged}
if [[ -s "$work/my_product.erofs" && "$(stat -c%s "$work/my_product.erofs")" == "$my_product_len" ]] && \
   fsck.erofs "$work/my_product.erofs" > "$work/my_product.fsck-retry.txt" 2>&1; then
  reuse_my_product=1
else
  reuse_my_product=0
fi

# Extract exactly two extents.  A retry may reuse an exact-size, fsck-clean
# extraction from the same immutable Stage53 baseline; extraction and checks
# still both complete before either copy is accepted.
extract_extent() {
  local name=$1 offset=$2 length=$3
  local file="$work/parts/$name.img"
  if [[ -f "$file" && "$(stat -c%s "$file")" == "$length" ]]; then
    if fsck.erofs "$file" > "$work/$name.fsck-base.txt" 2>&1; then
      echo "Reusing verified Stage53 extraction: $name" > "$work/$name.extraction.txt"
      return
    fi
  fi
  dd if="$base/images/super.img" of="$file.tmp" \
    iflag=skip_bytes,count_bytes skip="$offset" count="$length" status=none
  test "$(stat -c%s "$file.tmp")" -eq "$length"
  fsck.erofs "$file.tmp" > "$work/$name.fsck-base.txt" 2>&1
  mv -f "$file.tmp" "$file"
  echo "Extracted from immutable Stage53 baseline: $name" > "$work/$name.extraction.txt"
}

extract_extent my_product "$my_product_off" "$my_product_len"
extract_extent odm "$odm_off" "$odm_len"
test "$(stat -c%s "$work/parts/my_product.img")" -eq "$my_product_len"
test "$(stat -c%s "$work/parts/odm.img")" -eq "$odm_len"
for p in my_product odm; do
  fsck.erofs "$work/parts/$p.img" > "$work/$p.fsck-base.txt" 2>&1
done

# Compile the bridge a second time during the build, so output cannot silently
# reference an older /root artifact.  The 9-case host self-test is also run.
$ndk/bin/clang -O2 -Wall -Wextra -Werror \
  -o "$work/bridge-host" "$src/stage44_native_bridge.c" -ldl
"$work/bridge-host" --self-test
$ndk/bin/aarch64-linux-android34-clang -O2 -Wall -Wextra -Werror \
  -fPIE -pie -D__ANDROID__ \
  -o "$work/k90_native_bridge_stage55" \
  "$src/stage44_native_bridge.c" -llog -ldl
cmp "$work/k90_native_bridge_stage55" /root/k90_native_bridge_stage55
$ndk/bin/llvm-readelf -h "$work/k90_native_bridge_stage55" > "$work/bridge.readelf-header.txt"
$ndk/bin/llvm-readelf -d "$work/k90_native_bridge_stage55" > "$work/bridge.readelf-dynamic.txt"
grep -q 'Machine:.*AArch64' "$work/bridge.readelf-header.txt"
grep -q 'Shared library: \[liblog.so\]' "$work/bridge.readelf-dynamic.txt"
grep -q 'Shared library: \[libdl.so\]' "$work/bridge.readelf-dynamic.txt"

if (( reuse_my_product == 0 )); then
# my_product: real runtime feature file.  This is the location read by the
# ColorOS feature service; /product is only a lowerdir and is not the answer.
mount -t erofs -o ro,loop "$work/parts/my_product.img" "$overlay/my_product"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/my_product" 2>/dev/null)" "$overlay/my_product.upper"
# Give every directory created in this overlay the same root context.
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/my_product.upper"
mkdir -p "$overlay/my_product.upper/etc/permissions"
setfattr -n security.selinux -v u:object_r:system_file:s0 \
  "$overlay/my_product.upper/etc" \
  "$overlay/my_product.upper/etc/permissions"
cp -p "$overlay/my_product/etc/permissions/oplus.feature.android.xml" "$overlay/my_product.upper/etc/permissions/oplus.feature.android.xml"
feature="$overlay/my_product.upper/etc/permissions/oplus.feature.android.xml"
if ! grep -q 'oplus.misc.fan.extra_v2.support' "$feature"; then
  sed -i 's#</oplus-config>#    <oplus-feature name="oplus.misc.fan.extra_v2.support" />\n</oplus-config>#' "$feature"
fi
grep -q 'oplus.misc.fan.support' "$feature"
grep -q 'oplus.misc.fan.extra_v2.support' "$feature"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$feature"
mkdir -p "$overlay/my_product.merged"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/my_product.merged"
mount -t overlay overlay -o "lowerdir=$overlay/my_product,upperdir=$overlay/my_product.upper,workdir=$overlay/my_product.work" "$overlay/my_product.merged"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/my_product.merged/etc/fan_configs"

m_uuid=$(blkid -o value -s UUID "$work/parts/my_product.img")
m_label=$(blkid -o value -s LABEL "$work/parts/my_product.img" || true)
# Stage40's proven my_product build used 64KiB compression clusters.  The
# larger cluster is required to keep the richly themed 1.06GiB partition
# within its original capacity while preserving Chinese filenames.
m_args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$m_uuid" --preserve-mtime)
[[ -z "$m_label" ]] || m_args+=(-L "$m_label")
# erofs-utils 1.7.1 rejects non-ASCII names in a file-contexts file, while
# this partition legitimately contains Chinese theme filenames.  All existing
# entries carry their original SELinux xattr and only the prepared upper
# objects changed, so native xattr preservation is the correct path here.
rm -f "$work/my_product.file-contexts" "$work/my_product.contexts.log"
mkfs.erofs "${m_args[@]}" "$work/my_product.erofs.raw" "$overlay/my_product.merged" > "$work/my_product.mkfs.log" 2>&1
test "$(stat -c%s "$work/my_product.erofs.raw")" -le "$my_product_len"
cp --sparse=always "$work/my_product.erofs.raw" "$work/my_product.erofs"
truncate -s "$my_product_len" "$work/my_product.erofs"
umount "$overlay/my_product.merged"; umount "$overlay/my_product"
else
  echo "Reusing fsck-clean rebuilt my_product: $work/my_product.erofs" > "$work/my_product.reuse.txt"
fi

# ODM: keep the proven Stage53 SELinux policy bytes and all vendor services;
# replace only the bridge and its init rule.  This avoids touching power/audio
# namespace and charger policy while fixing the fan execution path.
mount -t erofs -o ro,loop "$work/parts/odm.img" "$overlay/odm"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/odm" 2>/dev/null)" "$overlay/odm.upper"
mkdir -p "$overlay/odm.upper/bin" "$overlay/odm.upper/etc/init" \
  "$overlay/odm.upper/lib64"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm.upper/bin"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm.upper/lib64"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/odm.upper/etc" \
  "$overlay/odm.upper/etc/init"
install -m 0755 "$work/k90_native_bridge_stage55" "$overlay/odm.upper/bin/k90_native_bridge"
install -m 0644 "$src/stage44_payload/k90-stage44-native.rc" "$overlay/odm.upper/etc/init/k90-stage44-native.rc"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm.upper/bin/k90_native_bridge"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$overlay/odm.upper/etc/init/k90-stage44-native.rc"
mkdir -p "$overlay/odm.merged"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm.merged"
mount -t overlay overlay -o "lowerdir=$overlay/odm,upperdir=$overlay/odm.upper,workdir=$overlay/odm.work" "$overlay/odm.merged"
# The original ODM contains this file without an embedded SELinux xattr.
# mkfs.erofs 1.7.1 does not synthesize one from a literal file-contexts
# entry, so copy it into the writable overlay and label that inode explicitly.
cp -p "$overlay/odm/lib64/libc++_shared.so" \
  "$overlay/odm.upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm.upper/lib64/libc++_shared.so"

o_uuid=$(blkid -o value -s UUID "$work/parts/odm.img")
o_label=$(blkid -o value -s LABEL "$work/parts/odm.img" || true)
o_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$o_uuid" --preserve-mtime)
[[ -z "$o_label" ]] || o_args+=(-L "$o_label")
python3 "$src/generate_erofs_file_contexts.py" "$overlay/odm.merged" /odm \
  "$work/odm.file-contexts" \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/bin/k90_native_bridge=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/etc/init/k90-stage44-native.rc=u:object_r:vendor_configs_file:s0 \
  > "$work/odm.contexts.log"
o_args+=(--mount-point=/odm --file-contexts="$work/odm.file-contexts")
mkfs.erofs "${o_args[@]}" "$work/odm.erofs.raw" "$overlay/odm.merged" > "$work/odm.mkfs.log" 2>&1
test "$(stat -c%s "$work/odm.erofs.raw")" -le "$odm_len"
cp --sparse=always "$work/odm.erofs.raw" "$work/odm.erofs"
truncate -s "$odm_len" "$work/odm.erofs"
umount "$overlay/odm.merged"; umount "$overlay/odm"

# Verify every rebuilt partition before assembling a new super image.
fsck.erofs "$work/my_product.erofs" > "$work/my_product.fsck.txt" 2>&1
fsck.erofs "$work/odm.erofs" > "$work/odm.fsck.txt" 2>&1
mount -t erofs -o ro,loop "$work/my_product.erofs" "$overlay/verify"
grep -q 'oplus.misc.fan.extra_v2.support' "$overlay/verify/etc/permissions/oplus.feature.android.xml"
umount "$overlay/verify"
mount -t erofs -o ro,loop "$work/odm.erofs" "$overlay/verify"
cmp "$work/k90_native_bridge_stage55" "$overlay/verify/bin/k90_native_bridge"
grep -q 'user root' "$overlay/verify/etc/init/k90-stage44-native.rc"
grep -q 'start k90-stage44-native' "$overlay/verify/etc/init/k90-stage44-native.rc"
strings -a "$overlay/verify/bin/k90_native_bridge" | grep -q 'fan-request-read'
strings -a "$overlay/verify/bin/k90_native_bridge" | grep -q 'fan-write-failed'
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_native_bridge")" = u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
umount "$overlay/verify"

# Assemble as a single new super image in the output directory.  It is never
# named super.img until all size, readback and byte-boundary checks pass.
building="$out/images/super.img.building"
rm -f "$building"
cp --sparse=always "$base/images/super.img" "$building"
dd if="$work/my_product.erofs" of="$building" bs=4096 seek=$((my_product_off / 4096)) conv=notrunc,fsync status=none
dd if="$work/odm.erofs" of="$building" bs=4096 seek=$((odm_off / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_len"

# Read back the exact three extents from the assembled image.
dd if="$building" of="$work/my_product.readback" iflag=skip_bytes,count_bytes skip="$my_product_off" count="$my_product_len" status=none
dd if="$building" of="$work/odm.readback" iflag=skip_bytes,count_bytes skip="$odm_off" count="$odm_len" status=none
cmp "$work/my_product.erofs" "$work/my_product.readback"
cmp "$work/odm.erofs" "$work/odm.readback"

# Compare the bytes outside the replaced extents on both sides.  These samples
# prove the critical metadata-containing head and tail were not moved.
head_cmp_len=$((my_product_off - 4194304))
cmp -n "$head_cmp_len" "$base/images/super.img" "$building"
head_cmp_end=$((my_product_off + my_product_len))
head_cmp_tail=$((odm_off - head_cmp_end))
cmp -n "$head_cmp_tail" -i "$head_cmp_end:$head_cmp_end" "$base/images/super.img" "$building"
tail_off=$((odm_off + odm_len))
tail_len=$((super_len - tail_off))
cmp -n "$tail_len" -i "$tail_off:$tail_off" "$base/images/super.img" "$building"

# Publish only after all checks.  Preserve the existing Chinese flash entry
# and platform-tools from Stage53; it performs keep-data fastbootd flashing.
mv "$building" "$out/images/super.img"
cp -a "$base/platform-tools" "$out/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$out/"
cp "$work/"*.fsck.txt "$work/"*.mkfs.log "$work/"*.readelf-* "$work/"*.contexts.log "$out/audit/"
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/my_product.erofs" "$work/odm.erofs" "$work/k90_native_bridge_stage55" > "$out/audit/partition-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage55 fan execution candidate
Base: Stage53 bootable image
Changed extents: my_product, odm
Data wipe: no
Native bridge self-test: 9/9 passed
Feature readback: oplus.misc.fan.extra_v2.support present in my_product
Bridge readback: new AArch64 binary and init rule present
Missing vendor label repaired: odm/lib64/libc++_shared.so = vendor_file
Key SELinux labels verified from rebuilt EROFS mount
Runtime fan/PWM validation: must be performed on device after keep-data flash
The script refuses non-prague and requires unlocked bootloader; it does not
touch boot, init_boot, modem, persist, nvdata, nvcfg, protect*, or preloader.
EOF

cat > "$out/audit/CHANGES.txt" <<'EOF'
1. Bridge accepts five- and six-field fan requests; the five-field consumer
   no longer silently disables the fan when system and ODM are upgraded apart.
2. Manual full-speed/custom modes no longer depend on screen state or a
   readable temperature sensor.
3. Every request/read/write/PWM-readback failure has an observable log event.
4. Fan PWM sysfs ownership is repaired after boot_completed as well as at
   post-fs-data.
5. V2 fan feature is written to the actual my_product feature file rather than
   /product, and is read back from the rebuilt EROFS.
6. Only my_product and odm are changed; system and all other super extents are kept.
7. Repairs the source ODM's missing libc++_shared.so label before rebuild and
   verifies it from the mounted rebuilt EROFS.
EOF

echo STAGE55_OFFLINE_BUILD_PASSED
