#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
root17=$root/01_主工程/K90_A17_PORT_WORK
delivery=$root17/delivery
base=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage49_FAN_SETTING_FIX
stage52=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage52_FAN_AOD_SIM
stage53=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage53_LABELS_FAN
out=$delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage54_FULL
work=$root/02_Codex完整工作区/wo/stage54_work
overlay=/root/k90_stage54_overlay
pmb=$root17/trees/pmb_odm
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py

system_offset=1048576
system_size=1049554944
system_partition_size=1061134336
system_end=$((system_offset + system_partition_size))
product_offset=2150629376
product_size=152326144
odm_offset=10713300992
odm_size=1724530688
my_manifest_offset=$((4499456 * 512))
my_manifest_size=$((1152 * 512))
super_size=13421772800

cleanup() {
  for n in verify system_merged system_lower product_merged product_lower odm_merged odm_lower my_manifest_merged my_manifest_lower; do
    mountpoint -q "$overlay/$n" && umount "$overlay/$n" || true
  done
}
trap cleanup EXIT

test -s "$base/images/super.img"
test -s "$stage52/images/super.img"
test -s "$stage53/images/super.img"
test -x "$avb"
test -s "$pmb/bin/hw/vendor-oplus-hardware-performance-V1-service"
test -s "$pmb/bin/hw/vendor.oplus.hardware.urcc-service"
test -s "$pmb/lib64/vendor.oplus.hardware.performance-V5-ndk.so"
test -s "$pmb/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"
test -s "$pmb/lib64/liburcccore.so"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"

mkdir -p "$work/out" "$out/images" "$out/audit"
mkdir -p "$overlay"/{system_lower,system_upper,system_work,system_merged,product_lower,product_upper,product_work,product_merged,odm_lower,odm_upper,odm_work,odm_merged,my_manifest_lower,my_manifest_upper,my_manifest_work,my_manifest_merged,verify}

# --- system: use Stage52's bounded EROFS/AVB image, never mix a different policy ---
dd if="$stage52/images/super.img" of="$work/out/system.img" bs=1M skip=1 count=1012 status=none
truncate -s "$system_partition_size" "$work/out/system.img"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1
python3 "$avb" verify_image --image "$work/out/system.img" > "$work/out/avb-system.txt"

# --- product: take the label-repaired Stage53 image and make the feature edit
# at the actual runtime consumer (/my_product is an overlay lowerdir). ---
dd if="$stage53/images/super.img" of="$work/out/product.img" \
  bs=16M skip="$product_offset" count="$product_size" \
  iflag=skip_bytes,count_bytes status=none
fsck.erofs "$work/out/product.img" > "$work/out/fsck-product-base.txt" 2>&1

# --- ODM: Stage53 label-repaired image + OPLUS HAL AIDL service closure ---
dd if="$stage53/images/super.img" of="$work/out/odm.img" \
  bs=16M skip="$odm_offset" count="$odm_size" \
  iflag=skip_bytes,count_bytes status=none
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm-base.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/odm_lower"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/odm_lower")" "$overlay/odm_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" \
  "$overlay/odm_merged"

install -d -m 0755 "$overlay/odm_merged/bin/hw" "$overlay/odm_merged/etc/vintf/manifest" "$overlay/odm_merged/etc/init"
install -m 0755 "$pmb/bin/hw/vendor-oplus-hardware-performance-V1-service" \
  "$overlay/odm_merged/bin/hw/vendor-oplus-hardware-performance-V1-service"
install -m 0755 "$pmb/bin/hw/vendor.oplus.hardware.urcc-service" \
  "$overlay/odm_merged/bin/hw/vendor.oplus.hardware.urcc-service"
install -m 0644 "$pmb/lib64/vendor.oplus.hardware.performance-V5-ndk.so" \
  "$overlay/odm_merged/lib64/vendor.oplus.hardware.performance-V5-ndk.so"
install -m 0644 "$pmb/lib64/vendor.oplus.hardware.urcc-V1-ndk.so" \
  "$overlay/odm_merged/lib64/vendor.oplus.hardware.urcc-V1-ndk.so"
install -m 0644 "$pmb/lib64/liburcccore.so" \
  "$overlay/odm_merged/lib64/liburcccore.so"
install -m 0644 "$pmb/etc/vintf/manifest/manifest_performance_aidl.xml" \
  "$overlay/odm_merged/etc/vintf/manifest/manifest_performance_aidl.xml"
install -m 0644 "$pmb/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml" \
  "$overlay/odm_merged/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml"

# Keep the service definitions narrow. Do not copy the Qualcomm-only node chmods.
cat > "$overlay/odm_merged/etc/init/k90-oplus-performance.rc" <<'EOF'
service k90-oplus-performance /odm/bin/hw/vendor-oplus-hardware-performance-V1-service
    class hal
    user root
    group system readproc
    interface aidl vendor.oplus.hardware.performance.IPerformance/default

service k90-oplus-urcc /odm/bin/hw/vendor.oplus.hardware.urcc-service
    class hal
    user root
    group system readproc
    interface aidl vendor.oplus.hardware.urcc.IUrcc/default

on post-fs-data
    mkdir /data/vendor/urcc 0770 system system
    mkdir /data/vendor/uah 0770 system system
EOF

# The service context names must be declared before the HAL is exposed.
svc_ctx="$overlay/odm_merged/etc/selinux/odm_service_contexts"
grep -q '^vendor.oplus.hardware.performance.IPerformance/default ' "$svc_ctx" || \
  printf '%s\n' 'vendor.oplus.hardware.performance.IPerformance/default u:object_r:hal_oplus_performance_service:s0' >> "$svc_ctx"
grep -q '^vendor.oplus.hardware.urcc.IUrcc/default ' "$svc_ctx" || \
  printf '%s\n' 'vendor.oplus.hardware.urcc.IUrcc/default u:object_r:hal_urcc_service:s0' >> "$svc_ctx"

# The root failure was libc++_shared.so in the ODM lower tree being unlabeled.
# Add an explicit match for every new and repaired ODM executable/library.
fc="$overlay/odm_merged/etc/selinux/odm_file_contexts"
grep -q '^/odm/lib64/libc++_shared\.so ' "$fc" || \
  printf '%s\n' '/odm/lib64/libc++_shared.so u:object_r:vendor_file:s0' >> "$fc"
for rel in \
  bin/hw/vendor-oplus-hardware-performance-V1-service \
  bin/hw/vendor.oplus.hardware.urcc-service \
  lib64/vendor.oplus.hardware.performance-V5-ndk.so \
  lib64/vendor.oplus.hardware.urcc-V1-ndk.so \
  lib64/liburcccore.so \
  etc/init/k90-oplus-performance.rc \
  etc/vintf/manifest/manifest_performance_aidl.xml \
  etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml; do
  case "$rel" in
    bin/hw/*) label=u:object_r:vendor_file:s0 ;;
    lib64/*) label=u:object_r:vendor_file:s0 ;;
    etc/init/*) label=u:object_r:vendor_configs_file:s0 ;;
    *) label=u:object_r:vendor_configs_file:s0 ;;
  esac
  grep -q "^/odm/$rel " "$fc" || printf '%s\n' "/odm/$rel $label" >> "$fc"
done

python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/odm_merged" /odm "$work/out/odm_file_contexts.generated" \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/bin/hw/vendor-oplus-hardware-performance-V1-service=u:object_r:vendor_file:s0 \
  --override /odm/bin/hw/vendor.oplus.hardware.urcc-service=u:object_r:vendor_file:s0 \
  --override /odm/lib64/vendor.oplus.hardware.performance-V5-ndk.so=u:object_r:vendor_file:s0 \
  --override /odm/lib64/vendor.oplus.hardware.urcc-V1-ndk.so=u:object_r:vendor_file:s0 \
  --override /odm/lib64/liburcccore.so=u:object_r:vendor_file:s0 \
  --override /odm/etc/init/k90-oplus-performance.rc=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/vintf/manifest/manifest_performance_aidl.xml=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/vintf/manifest/vendor.oplus.hardware.urcc-service.xml=u:object_r:vendor_configs_file:s0 \
  > "$work/out/odm-file-contexts-generation.txt"

odm_uuid=$(blkid -o value -s UUID "$work/out/odm.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime)
[[ -z "$odm_label" ]] || odm_args+=(-L "$odm_label")
odm_args+=(--mount-point=/odm --file-contexts="$work/out/odm_file_contexts.generated")
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" "$overlay/odm_merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/odm_merged"
umount "$overlay/odm_lower"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1

# --- my_manifest: edit the original source prop; append-only product props
# cannot override an already-initialised read-only property.
if [[ ! -s "$work/out/my_manifest.base.img" ]]; then
  dd if="$base/images/super.img" of="$work/out/my_manifest.base.img" \
    bs=512 skip=4499456 count=1152 status=none
fi
fsck.erofs "$work/out/my_manifest.base.img" > "$work/out/fsck-my_manifest-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/my_manifest.base.img" "$overlay/my_manifest_lower"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/my_manifest_lower")" "$overlay/my_manifest_upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/my_manifest_lower,upperdir=$overlay/my_manifest_upper,workdir=$overlay/my_manifest_work" \
  "$overlay/my_manifest_merged"
manifest_prop="$overlay/my_manifest_merged/build.prop"
sed -i \
  -e 's/^ro\.vendor\.oplus\.market\.name=.*/ro.vendor.oplus.market.name=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.model=.*/ro.product.model=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.marketname=.*/ro.product.marketname=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.bootimage\.model=.*/ro.product.bootimage.model=一加 Ace 6 至尊版/' \
  "$manifest_prop"
for key in ro.config.bt_name ro.config.wifi_ap_ssid; do
  grep -q "^$key=" "$manifest_prop" || printf '%s\n' "$key=一加 Ace 6 至尊版" >> "$manifest_prop"
done
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/my_manifest_upper/build.prop" 2>/dev/null || true
my_uuid=$(blkid -o value -s UUID "$work/out/my_manifest.base.img")
my_label=$(blkid -o value -s LABEL "$work/out/my_manifest.base.img" || true)
my_args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$my_uuid" --preserve-mtime)
[[ -z "$my_label" ]] || my_args+=(-L "$my_label")
python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/my_manifest_merged" /my_manifest "$work/out/my_manifest_file_contexts.generated" \
  --override /my_manifest/build.prop=u:object_r:vendor_file:s0 \
  > "$work/out/my_manifest-file-contexts-generation.txt"
my_args+=(--mount-point=/my_manifest --file-contexts="$work/out/my_manifest_file_contexts.generated")
mkfs.erofs "${my_args[@]}" "$work/out/my_manifest.raw.img" "$overlay/my_manifest_merged" > "$work/out/mkfs-my_manifest.log" 2>&1
test "$(stat -c%s "$work/out/my_manifest.raw.img")" -le "$my_manifest_size"
cp --sparse=always "$work/out/my_manifest.raw.img" "$work/out/my_manifest.img"
truncate -s "$my_manifest_size" "$work/out/my_manifest.img"
umount "$overlay/my_manifest_merged"
umount "$overlay/my_manifest_lower"
fsck.erofs "$work/out/my_manifest.img" > "$work/out/fsck-my_manifest.txt" 2>&1

# --- assemble super from the Stage49 baseline, replacing only four extents ---
cp --sparse=always "$base/images/super.img" "$work/out/super.building"
dd if="$work/out/system.img" of="$work/out/super.building" bs=1M seek=1 conv=notrunc,fsync status=none
dd if="$work/out/product.img" of="$work/out/super.building" bs=16M seek="$product_offset" \
  oflag=seek_bytes conv=notrunc,fsync status=none
dd if="$work/out/my_manifest.img" of="$work/out/super.building" bs=16M seek="$my_manifest_offset" \
  oflag=seek_bytes conv=notrunc,fsync status=none
dd if="$work/out/odm.img" of="$work/out/super.building" bs=16M seek="$odm_offset" \
  oflag=seek_bytes conv=notrunc,fsync status=none
mv "$work/out/super.building" "$work/out/super.img"

# Read back each changed extent and compare byte-for-byte.
dd if="$work/out/super.img" of="$work/out/system.readback.img" bs=1M skip=1 count=1012 status=none
dd if="$work/out/super.img" of="$work/out/product.readback.img" bs=16M skip="$product_offset" count="$product_size" iflag=skip_bytes,count_bytes status=none
dd if="$work/out/super.img" of="$work/out/my_manifest.readback.img" bs=16M skip="$my_manifest_offset" count="$my_manifest_size" iflag=skip_bytes,count_bytes status=none
dd if="$work/out/super.img" of="$work/out/odm.readback.img" bs=16M skip="$odm_offset" count="$odm_size" iflag=skip_bytes,count_bytes status=none
cmp "$work/out/system.img" "$work/out/system.readback.img"
cmp "$work/out/product.img" "$work/out/product.readback.img"
cmp "$work/out/my_manifest.img" "$work/out/my_manifest.readback.img"
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
for f in system product my_manifest odm; do fsck.erofs "$work/out/$f.readback.img" > "$work/out/fsck-$f-readback.txt" 2>&1; done
python3 "$avb" verify_image --image "$work/out/system.readback.img" > "$work/out/avb-system-readback.txt"

echo 'STAGE54_OFFLINE_BUILD_PASSED'
