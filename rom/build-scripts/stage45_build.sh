#!/bin/bash
set -euo pipefail
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN
work=$root/02_Codex完整工作区/wo/stage45_work
overlay=/root/k90_stage45_overlay
odm_base=$root/02_Codex完整工作区/wo/stage44_r1_work/out/odm.img
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py
mkdir -p "$work/out" "$delivery/images" "$delivery/audit" "$overlay"/{odm_lower,odm_upper,odm_work,odm_merged,my_product_lower,my_product_upper,my_product_work,my_product_merged,verify}
cleanup(){ for n in verify odm_merged odm_lower my_product_merged my_product_lower; do mountpoint -q "$overlay/$n" && umount "$overlay/$n" || true; done; }
trap cleanup EXIT
test ! -e "$delivery/images/super.img"
if [[ ! -s "$work/out/my_product.base.img" ]]; then
 dd if="$base/images/super.img" of="$work/out/my_product.base.img" bs=1M skip=2198 count=1086 status=progress
 truncate -s 1138266112 "$work/out/my_product.base.img"
fi
for n in odm my_product; do
 partbase=$odm_base; [[ $n != my_product ]] || partbase=$work/out/my_product.base.img
 mount -t erofs -o ro,loop "$partbase" "$overlay/${n}_lower"
 label=$(getfattr -n security.selinux --only-values "$overlay/${n}_lower" 2>/dev/null)
 setfattr -n security.selinux -v "$label" "$overlay/${n}_upper"
 mount -t overlay overlay -o "lowerdir=$overlay/${n}_lower,upperdir=$overlay/${n}_upper,workdir=$overlay/${n}_work" "$overlay/${n}_merged"
done
python3 "$src/stage45_diagnosis/patch_generated.py" "$overlay/odm_merged" "$overlay/my_product_merged"
for item in etc/build.prop etc/selinux/odm_property_contexts etc/init/k90-stage44-native.rc; do
 cp --attributes-only --preserve=all "$overlay/odm_lower/$item" "$overlay/odm_upper/$item"
done
cp --attributes-only --preserve=all "$overlay/my_product_lower/etc/permissions/oplus.feature.android.xml" "$overlay/my_product_upper/etc/permissions/oplus.feature.android.xml"
for n in odm my_product; do
 partbase=$odm_base; size=1724530688
 if [[ $n == my_product ]]; then partbase=$work/out/my_product.base.img; size=1138266112; fi
 cluster=16384; [[ $n != my_product ]] || cluster=65536
 args=(-z lz4hc,12 -C "$cluster" -T 1791306550 -U "$(blkid -o value -s UUID "$partbase")" --preserve-mtime)
 label=$(blkid -o value -s LABEL "$partbase" || true); [[ -z $label ]] || args+=(-L "$label")
 mkfs.erofs "${args[@]}" "$work/out/$n.raw.img" "$overlay/${n}_merged" > "$work/out/mkfs-$n.log" 2>&1
 actual=$(stat -c%s "$work/out/$n.raw.img"); test "$actual" -le "$size"
 cp --sparse=always "$work/out/$n.raw.img" "$work/out/$n.img"
 # Preserve whether the source partition has AVB; do not add/remove a footer.
 if python3 "$avb" info_image --image "$partbase" > "$work/out/avb-$n-base.txt" 2>&1; then
   echo "SOURCE_HAS_AVB_REQUIRES_EXACT_FOOTER_REBUILD: $n"; exit 12
 fi
 truncate -s "$size" "$work/out/$n.img"
 fsck.erofs "$work/out/$n.img" > "$work/out/fsck-$n.txt" 2>&1
 mount -t erofs -o ro,loop "$work/out/$n.img" "$overlay/verify"
 test "$(stat -c %u:%g:%a "$overlay/verify")" = "$(stat -c %u:%g:%a "$overlay/${n}_lower")"
 test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = "$(getfattr -n security.selinux --only-values "$overlay/${n}_lower" 2>/dev/null)"
 if [[ $n == odm ]]; then
   for item in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 odm_sepolicy.cil; do
     cmp "$overlay/odm_lower/etc/selinux/$item" "$overlay/verify/etc/selinux/$item"
   done
   for item in etc/build.prop etc/selinux/odm_property_contexts etc/init/k90-stage44-native.rc; do cmp "$overlay/odm_merged/$item" "$overlay/verify/$item"; done
 else cmp "$overlay/my_product_merged/etc/permissions/oplus.feature.android.xml" "$overlay/verify/etc/permissions/oplus.feature.android.xml"; fi
 umount "$overlay/verify"
done
cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
dd if="$work/out/my_product.img" of="$delivery/images/super.img.building" bs=1M seek=2198 conv=notrunc,fsync status=progress
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=1M seek=10217 conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$delivery/images/super.img"
cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
python3 "$src/stage45_verify.py" "$base/images/super.img" "$delivery" "$work/out"
cp "$work/out/"fsck-*.txt "$delivery/audit/"
echo STAGE45_OFFLINE_BUILD_PASSED
