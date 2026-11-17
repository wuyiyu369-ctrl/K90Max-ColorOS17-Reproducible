#!/usr/bin/env bash
set -euo pipefail

product=/tmp/k90-r2-product
odm=/tmp/k90-r2-odm
product_img=/root/k90_stage33_native_build/out/product.img
odm_img=/root/k90_stage33_native_build/out/odm.img
aod=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage33_aod_overlay/dist/K90MaxAodNativeOverlay.apk

mkdir -p "$product" "$odm"
mountpoint -q "$product" || mount -t erofs -o ro,loop "$product_img" "$product"
mountpoint -q "$odm" || mount -t erofs -o ro,loop "$odm_img" "$odm"

test "$(stat -c '%a:%u:%g' "$product/bin")" = 751:0:2000
test "$(getfattr -n security.selinux --only-values "$product/bin" 2>/dev/null)" = u:object_r:system_file:s0
test "$(getfattr -n security.selinux --only-values "$odm/etc" 2>/dev/null)" = u:object_r:vendor_configs_file:s0
test "$(getfattr -n security.selinux --only-values "$odm/etc/init" 2>/dev/null)" = u:object_r:vendor_configs_file:s0
test "$(getfattr -n security.selinux --only-values "$odm/etc/init/k90-power-permissions.rc" 2>/dev/null)" = u:object_r:vendor_configs_file:s0
grep -q '^MODE=aggressive$' "$product/etc/k90/charge-scheduler.conf"
grep -q 'vendor.xiaomi.hardware.micharge.IMiCharge/default' "$product/bin/k90-native-charge-launcher.sh"
grep -q 'oplus_battery_agent_debug_force_entry 1' "$product/etc/init/k90-native-settings.rc"
fsck.erofs "$product_img"
fsck.erofs "$odm_img"
sha256sum "$product_img" "$odm_img" "$aod" > /root/k90_stage33_native_build/out/SHA256SUMS.txt
umount "$product"
umount "$odm"
echo R2_PARTITIONS_VALIDATED
