#!/usr/bin/env bash
set -euo pipefail

work=/root/k90_stage32_camera_external_return
base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage31_MI_CAMERA_CACHEFIX_R1/images/super.img
delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage32_MI_CAMERA_EXTERNAL_RETURN_R1
super="$delivery/images/super.img"
my="$work/out/my_product.img"
my_offset=2304770048
my_size=1138266112

for file in "$base" "$super" "$my"; do test -f "$file"; done
test "$(stat -c%s "$base")" -eq 13421772800
test "$(stat -c%s "$super")" -eq 13421772800
test "$(stat -c%s "$my")" -eq "$my_size"

mkdir -p "$delivery/audit"
base_prefix=$(dd if="$base" bs=1M count=1 status=none | sha256sum | cut -d' ' -f1)
test "$base_prefix" = "$(dd if="$super" bs=1M count=1 status=none | sha256sum | cut -d' ' -f1)"
dd if="$my" of="$super" bs=16M seek="$my_offset" oflag=seek_bytes conv=notrunc,fsync status=progress

my_sha=$(sha256sum "$my" | cut -d' ' -f1)
extent_sha=$(dd if="$super" bs=16M skip="$my_offset" count="$my_size" iflag=skip_bytes,count_bytes status=none | sha256sum | cut -d' ' -f1)
test "$my_sha" = "$extent_sha"
test "$base_prefix" = "$(dd if="$super" bs=1M count=1 status=none | sha256sum | cut -d' ' -f1)"

cp "$work/out/"{SHA256SUMS.txt,my_product.fsck.txt} "$delivery/audit/"
sha256sum "$super" > "$delivery/SHA256SUMS.txt"
cat > "$delivery/audit/STAGE32_SUPER_VERIFY.txt" <<EOF
base_stage=Stage31_MI_CAMERA_CACHEFIX_R1
base_metadata_prefix_sha256=$base_prefix
my_product_image_sha256=$my_sha
my_product_extent_sha256=$extent_sha
my_product_offset_bytes=$my_offset
my_product_length_bytes=$my_size
metadata_prefix_unchanged=yes
camera_apk_sha256=b72e2f4f67065a76deae1da35a431ecded6614f9462abae4172b160f5861211f
camera_external_output_test_bytes=265567
camera_external_output_jpeg_header=FFD8FFE1
camera_external_output_jpeg_footer=FFD9
EOF
echo STAGE32_CAMERA_EXTERNAL_RETURN_SUPER_OK
