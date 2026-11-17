#!/usr/bin/env bash
set -euo pipefail

root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery
base="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1"
out="$root/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_BOOTFIX_R2"
super="$out/images/super.img"

product_offset=2150629376
product_size=152326144
my_offset=2304770048
my_size=1138266112
odm_offset=10713300992
odm_size=1724530688
super_size=13421772800

my=/root/k90_stage33_merge/images/my_product31.img
product=/root/k90_stage33_native_build/out/product.img
odm=/root/k90_stage33_native_build/out/odm.img

test ! -e "$out"
for file in "$base/images/super.img" "$product" "$my" "$odm"; do test -f "$file"; done
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
test "$(stat -c%s "$product")" -eq "$product_size"
test "$(stat -c%s "$my")" -eq "$my_size"
test "$(stat -c%s "$odm")" -eq "$odm_size"

mkdir -p "$out"/{images,audit}
cp --sparse=always "$base/images/super.img" "$super"

# Stage31 remains the complete base. Only three independently rebuilt extents
# are replaced: product AOD/charging integration, the unchanged Stage31
# my_product extent, and the current ODM MTK PowerHAL trigger.
dd if="$product" of="$super" bs=16M seek="$product_offset" oflag=seek_bytes \
  conv=notrunc status=progress
dd if="$my" of="$super" bs=16M seek="$my_offset" oflag=seek_bytes \
  conv=notrunc status=progress
dd if="$odm" of="$super" bs=16M seek="$odm_offset" oflag=seek_bytes \
  conv=notrunc,fsync status=progress

hash_extent() {
  local image=$1 offset=$2 length=$3
  dd if="$image" bs=16M skip="$offset" count="$length" \
    iflag=skip_bytes,count_bytes status=none | sha256sum | cut -d' ' -f1
}

prefix_base=$(dd if="$base/images/super.img" bs=1M count=1 status=none | sha256sum | cut -d' ' -f1)
prefix_new=$(dd if="$super" bs=1M count=1 status=none | sha256sum | cut -d' ' -f1)
test "$prefix_base" = "$prefix_new"
tail_base=$(tail -c 1048576 "$base/images/super.img" | sha256sum | cut -d' ' -f1)
tail_new=$(tail -c 1048576 "$super" | sha256sum | cut -d' ' -f1)
test "$tail_base" = "$tail_new"

product_source=$(sha256sum "$product" | cut -d' ' -f1)
product_new=$(hash_extent "$super" "$product_offset" "$product_size")
my_source=$(sha256sum "$my" | cut -d' ' -f1)
my_new=$(hash_extent "$super" "$my_offset" "$my_size")
odm_source=$(sha256sum "$odm" | cut -d' ' -f1)
odm_new=$(hash_extent "$super" "$odm_offset" "$odm_size")
test "$product_source" = "$product_new"
test "$my_source" = "$my_new"
test "$odm_source" = "$odm_new"

# LP primary and backup metadata are outside the replaced extents. Comparing
# both 1 MiB ends byte-for-byte is stronger than parsing them with a missing
# host-side lpdump binary.
cp "$base/audit/base-lpdump.txt" "$out/audit/base-lpdump.txt" 2>/dev/null || true

cp -a "$base/platform-tools" "$out/"
cp "$base/START_UPDATE.cmd" "$base/FLASH_KEEP_DATA.ps1" "$out/"
sha256sum "$super" > "$out/SHA256SUMS.txt"
cat > "$out/audit/STAGE33_EXTENT_VERIFY.txt" <<EOF
base=Stage31_MI_CAMERA_CACHEFIX_R1
system_source=Stage31_UNCHANGED
product_source=Stage34_NATIVE_AOD_CHARGE
product_sha256=$product_new
my_product_source=Stage31_BASELINE_REEXTRACTED
my_product_sha256=$my_new
odm_source=Stage34_PLUS_MTKPOWER_SERVICE_TRIGGER
odm_sha256=$odm_new
metadata_prefix_sha256=$prefix_new
metadata_tail_sha256=$tail_new
lp_metadata_unchanged=yes
EOF
cat > "$out/audit/MODULE_NATIVE_COVERAGE.txt" <<EOF
KSU_LSP_SOURCE=build_v1747
AI_BATTERY_ENTRY=native_product_rc
CHARGE_TELEMETRY=native_product_bins_and_rc
CHARGE_DEFAULT=aggressive_with_hardware_guards
CAMERA_EXTERNAL_RETURN=not_included_stage32_artifact_unverified
FINGERPRINT_PROPS=depends_on_selected_base_not_added_by_merge_script
FACE_JAVA_HOOK=not_native
LSP_SETTINGS_IDENTITY=not_native
LSP_CAMERA_JAVA_HOOKS=not_native
URCC_PERFORMANCE_DONOR_PRESENT=build_v1747_odm
URCC_PERFORMANCE_NATIVE=not_included_unverified_selinux_vintf_abi
PERFSERV_PERMISSION_TRIGGER=stage34_odm_input
NFC_TEE_WALLET=not_reproducible
EOF
echo STAGE34_CHARGE_CAMERA_AOD_SUPER_OK
