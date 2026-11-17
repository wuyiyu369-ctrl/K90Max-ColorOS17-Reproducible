#!/usr/bin/env bash
set -euo pipefail
w=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/stage51_work/out
b=/tmp/s51base
n=/tmp/s51new
mkdir -p "$b/product" "$b/odm" "$n/product" "$n/odm"
cleanup() {
  for m in "$b/product" "$b/odm" "$n/product" "$n/odm"; do
    mountpoint -q "$m" && umount "$m" || true
  done
}
trap cleanup EXIT
cleanup
mount -t erofs -o ro,loop "$w/product.base.img" "$b/product"
mount -t erofs -o ro,loop "$w/odm.base.img" "$b/odm"
mount -t erofs -o ro,loop "$w/product.img" "$n/product"
mount -t erofs -o ro,loop "$w/odm.img" "$n/odm"

echo PRODUCT_LABELS
for p in / /bin /etc /etc/build.prop /etc/init /etc/init/k90-user-names.rc; do
  echo "==$p"
  stat -c 'base %U:%G %a %C' "$b/product$p" 2>&1 || true
  stat -c 'new  %U:%G %a %C' "$n/product$p" 2>&1 || true
done

echo ODM_LABELS
for p in / /bin /bin/k90_native_bridge /bin/vendor.oplus.hardware.charger-V11-service /lib64/libc++_shared.so /etc/init/k90-native-charge.rc /etc/selinux/precompiled_sepolicy; do
  echo "==$p"
  stat -c 'base %U:%G %a %C' "$b/odm$p" 2>&1 || true
  stat -c 'new  %U:%G %a %C' "$n/odm$p" 2>&1 || true
done

echo PRODUCT_PROPS
grep -nE 'ro.product.(model|marketname)|ro.product.product.model|ro.product.system.model|ro.product.system_ext.model|ro.config.bt_name|wifi_ap_ssid' "$n/product/etc/build.prop" || true
echo DUPLICATE_PRODUCT_KEYS
cut -d= -f1 "$n/product/etc/build.prop" | sort | uniq -d | grep -E 'ro.product|ro.config' || true
