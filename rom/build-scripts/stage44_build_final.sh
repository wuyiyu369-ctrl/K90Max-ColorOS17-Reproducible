#!/usr/bin/env bash
set -euo pipefail
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
build=$root/02_Codex完整工作区/wo/stage44_final_work
overlay=/root/k90_stage44_final_overlay_r2
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR/images/super.img
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_FANPERF
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py
jar=$src/stage44_services/services.stage44.jar
system_base=$root/02_Codex完整工作区/wo/stage43_services_repair_work/out/system.img

test -s "$src/stage44_policy/strict_differential.txt"
grep -q '^BASELINE_AND_CANDIDATE_DIAGNOSTICS_IDENTICAL' "$src/stage44_policy/strict_differential.txt"
test -s "$jar"; test -s "$src/stage44_native_bridge"
test "$(sha256sum "$system_base" | cut -d' ' -f1)" = f5592e0e9492f06d0ac380ceab32139386266bb4bbaf5b626620f36e828f2293
mkdir -p "$build/out" "$overlay"/{system_lower,system_upper,system_work,system_merged,odm_lower,odm_upper,odm_work,odm_merged,verify}
cleanup(){ for m in verify system_merged system_lower odm_merged odm_lower; do mountpoint -q "$overlay/$m" && umount "$overlay/$m" || true; done; }
trap cleanup EXIT

# Reuse the exact Stage43 ODM extracted earlier; move this run's own images
# out of the full Linux VHD. No old extraction tree or baseline is deleted.
for n in odm.base.img odm.raw.img odm.img; do
  if [[ -f /root/k90_stage44_fanperf/out/$n && ! -e "$build/out/draft-$n" ]]; then
    mv "/root/k90_stage44_fanperf/out/$n" "$build/out/draft-$n"
  fi
done
odm_base=$build/out/draft-odm.base.img
test "$(stat -c%s "$odm_base")" -eq 1724530688

if [[ -s "$build/out/avb-system.txt" && -s "$build/out/system.img" ]]; then
  mount -t erofs -o ro,loop "$build/out/system.img" "$overlay/verify"
  cmp -s "$jar" "$overlay/verify/system/framework/services.jar"
  umount "$overlay/verify"
else
mount -t erofs -o ro,loop "$system_base" "$overlay/system_lower"
setfattr -n security.selinux -v u:object_r:rootfs:s0 "$overlay/system_upper"
mount -t overlay overlay -o "lowerdir=$overlay/system_lower,upperdir=$overlay/system_upper,workdir=$overlay/system_work" "$overlay/system_merged"
install -m 0644 "$jar" "$overlay/system_merged/system/framework/services.jar"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/system_upper/system/framework/services.jar"
args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$(blkid -o value -s UUID "$system_base")" --preserve-mtime)
label=$(blkid -o value -s LABEL "$system_base" || true); [[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$build/out/system.raw.img" "$overlay/system_merged" > "$build/out/mkfs-system.log" 2>&1
test "$(stat -c%s "$build/out/system.raw.img")" -le 1049554944
cp --sparse=always "$build/out/system.raw.img" "$build/out/system.img"
truncate -s 1049554944 "$build/out/system.img"
python3 "$avb" add_hashtree_footer --image "$build/out/system.img" --partition_size 1061134336 \
 --partition_name system --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
 --block_size 4096 --do_not_generate_fec --algorithm NONE \
 --prop com.android.build.oplus_custom_images.os_version:11 \
 --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$build/out/system.img" > "$build/out/avb-system.txt"
fsck.erofs "$build/out/system.img" > "$build/out/fsck-system.txt" 2>&1
umount "$overlay/system_merged"; umount "$overlay/system_lower"
fi

mount -t erofs -o ro,loop "$odm_base" "$overlay/odm_lower"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm_upper"
mount -t overlay overlay -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" "$overlay/odm_merged"
cp "$overlay/odm_lower/etc/selinux/precompiled_sepolicy" "$src/stage44_policy/stage43-baseline.bin"
"$src/stage44_policy_patch" "$overlay/odm_lower/etc/selinux/precompiled_sepolicy" "$src/stage44_policy/candidate.bin" > "$build/out/policy-patch.txt"
install -m 0755 "$src/stage44_native_bridge" "$overlay/odm_merged/bin/k90_native_bridge"
install -m 0644 "$src/stage44_payload/k90-stage44-native.rc" "$overlay/odm_merged/etc/init/k90-stage44-native.rc"
install -m 0644 "$src/stage44_policy/candidate.cil" "$overlay/odm_merged/etc/selinux/odm_sepolicy.cil"
install -m 0644 "$src/stage44_policy/candidate.bin" "$overlay/odm_merged/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm_upper/bin/k90_native_bridge"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$overlay/odm_upper/etc/init/k90-stage44-native.rc"
for n in odm_sepolicy.cil precompiled_sepolicy; do setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 "$overlay/odm_upper/etc/selinux/$n"; done
# Verify the captured source bytes against Stage43 and select the incremental
# binary with matching image markers. All runtime types come from Stage43's
# own precompiled policy, never a reference-ROM or Stage42 binary.
python3 "$src/stage44_policy_markers.py" "$base" "$overlay/odm_merged/etc/selinux"
for f in "$overlay/odm_upper/etc/selinux/"*.sha256; do setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$f"; done
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$(blkid -o value -s UUID "$odm_base")" --preserve-mtime)
label=$(blkid -o value -s LABEL "$odm_base" || true); [[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$build/out/odm.raw.img" "$overlay/odm_merged" > "$build/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$build/out/odm.raw.img")" -le 1724530688
cp --sparse=always "$build/out/odm.raw.img" "$build/out/odm.img"; truncate -s 1724530688 "$build/out/odm.img"
fsck.erofs "$build/out/odm.img" > "$build/out/fsck-odm.txt" 2>&1
umount "$overlay/odm_merged"; umount "$overlay/odm_lower"

mount -t erofs -o ro,loop "$build/out/system.img" "$overlay/verify"
cmp -s "$jar" "$overlay/verify/system/framework/services.jar"
test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = u:object_r:rootfs:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/system/framework/services.jar" 2>/dev/null)" = u:object_r:system_file:s0
umount "$overlay/verify"
mount -t erofs -o ro,loop "$build/out/odm.img" "$overlay/verify"
cmp -s "$src/stage44_policy/candidate.bin" "$overlay/verify/etc/selinux/precompiled_sepolicy"
cmp -s "$src/stage44_native_bridge" "$overlay/verify/bin/k90_native_bridge"
test "$(getfattr -n security.selinux --only-values "$overlay/verify" 2>/dev/null)" = u:object_r:vendor_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90_native_bridge" 2>/dev/null)" = u:object_r:vendor_touch_init_shell_exec:s0
umount "$overlay/verify"

# The unpublished draft already contains a full copy of Stage43. Only its
# two replacement extents are updated, avoiding another 12.5 GiB allocation.
super=$delivery/images/super.img
test "$(stat -c%s "$super")" -eq 13421772800
dd if="$build/out/system.img" of="$super" bs=1M seek=1 conv=notrunc,fsync status=progress
dd if="$build/out/odm.img" of="$super" bs=1M seek=10217 conv=notrunc,fsync status=progress
python3 "$src/stage44_audit_final.py" "$base" "$super" "$build/out" "$delivery"
echo "STAGE44_FINAL_OFFLINE_CANDIDATE=$delivery"
