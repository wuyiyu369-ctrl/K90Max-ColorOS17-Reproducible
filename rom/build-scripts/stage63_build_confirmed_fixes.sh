#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage62_INTEGRATED_POLICY
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage63_CONFIRMED_FIXES
pre=/root/k90_stage63_pre
work=/root/k90_stage63_manifest_work
overlay=/root/k90_stage63_manifest_overlay

super_size=13421772800
my_manifest_offset=$((4499456 * 512))
my_manifest_size=$((1152 * 512))
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
base_hash=2dc50b4fd09422f9be3edadcd71c4dced5369c07c46fdf67dc296453a45b3077

test -s "$base/images/super.img"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
test "$(sha256sum "$base/images/super.img" | cut -d' ' -f1)" = "$base_hash"
test -s "$src/stage62_build_integrated_policy.sh"
test -s "$src/generate_erofs_file_contexts.py"

rm -rf "$pre" "$work" "$overlay" "$out"
mkdir -p "$work/out" "$overlay"/{lower,upper,work,merged,verify} "$out"/{images,audit}

cleanup() {
  for m in odm odm_base vendor product system_ext system; do
    mountpoint -q "$work/policy/$m" && umount "$work/policy/$m" || true
  done
  mountpoint -q "$overlay/verify" && umount "$overlay/verify" || true
  mountpoint -q "$overlay/merged" && umount "$overlay/merged" || true
  mountpoint -q "$overlay/lower" && umount "$overlay/lower" || true
}
trap cleanup EXIT

# Rebuild the Stage62 ODM integration on the actually booted Stage62 image,
# using the additional denials observed after its first boot.
K90_STAGE_BASE="$base" \
K90_STAGE_OUT="$pre" \
K90_STAGE_WORK=/root/k90_stage63_odm_work \
K90_STAGE_OVERLAY=/root/k90_stage63_odm_overlay \
K90_STAGE_BASE_HASH="$base_hash" \
K90_STAGE_BASE_MARKER=/root/k90_stage63_stage62_base_verified \
K90_STAGE_ODM_CACHE=/root/k90_stage63_stage62_odm.base.img \
  bash "$src/stage62_build_integrated_policy.sh"

test -s "$pre/images/super.img"
test "$(stat -c%s "$pre/images/super.img")" -eq "$super_size"
grep -q '^typeattribute vendor_touch_init_shell hal_micharge_client;$' \
  "$pre/audit/policy-patch.txt"
grep -q '^allow vendor_touch_init_shell vendor_data_file:file .*rename unlink' \
  "$pre/audit/policy-patch.txt"

# Stage62 intentionally carries mismatching platform/system_ext markers, so
# Android init compiles the complete split CIL set at boot. Strict-compile the
# booted Stage62 baseline and Stage63 candidate with identical inputs, and
# require that the candidate introduces no additional diagnostic. This mixed
# ColorOS/Xiaomi baseline already has upstream neverallow diagnostics, so a
# false "clean compile" must not be claimed or obtained by disabling checks.
policy="$work/policy"
mkdir -p "$policy"/{system,system_ext,product,vendor,odm,odm_base}
mount -t erofs -o ro,loop,offset=$((2048 * 512)),sizelimit=$((2072528 * 512)) \
  "$pre/images/super.img" "$policy/system"
mount -t erofs -o ro,loop,offset=$((259328 * 4096)),sizelimit=1087639552 \
  "$pre/images/super.img" "$policy/system_ext"
mount -t erofs -o ro,loop,offset=$((525056 * 4096)),sizelimit=152326144 \
  "$pre/images/super.img" "$policy/product"
mount -t erofs -o ro,loop,offset=$((2000640 * 4096)),sizelimit=2517786624 \
  "$pre/images/super.img" "$policy/vendor"
mount -t erofs -o ro,loop,offset="$odm_offset",sizelimit="$odm_size" \
  "$pre/images/super.img" "$policy/odm"
mount -t erofs -o ro,loop,offset="$odm_offset",sizelimit="$odm_size" \
  "$base/images/super.img" "$policy/odm_base"

vers=$(cat "$policy/vendor/etc/selinux/plat_sepolicy_vers.txt")
test "$vers" = 202504
inputs=(
  "$policy/system/system/etc/selinux/plat_sepolicy.cil"
  "$policy/system/system/etc/selinux/mapping/$vers.cil"
)
for candidate in \
  "$policy/system/system/etc/selinux/mapping/$vers.compat.cil" \
  "$policy/system/system/etc/selinux/plat_sepolicy_genfs_202504.cil" \
  "$policy/system_ext/system_ext/etc/selinux/system_ext_sepolicy.cil" \
  "$policy/system_ext/system_ext/etc/selinux/mapping/$vers.cil" \
  "$policy/system_ext/system_ext/etc/selinux/mapping/$vers.compat.cil" \
  "$policy/product/product/etc/selinux/product_sepolicy.cil" \
  "$policy/product/product/etc/selinux/mapping/$vers.cil" \
  "$policy/vendor/etc/selinux/plat_pub_versioned.cil" \
  "$policy/vendor/etc/selinux/vendor_sepolicy.cil"; do
  [[ -f "$candidate" ]] && inputs+=("$candidate")
done
grep -q '^(typeattributeset hal_micharge_client (vendor_touch_init_shell))$' \
  "$policy/odm/etc/selinux/odm_sepolicy.cil"
! grep -q '^(allow zygote oplus_fingerprint_prop ' \
  "$policy/odm/etc/selinux/odm_sepolicy.cil"

secilc_bin=${K90_SECILC:-$src/stage44_toolchain_source/selinux-main/secilc/secilc}
test -x "$secilc_bin"
set +e
"$secilc_bin" -m -M true -G -c 33 "${inputs[@]}" \
  "$policy/odm_base/etc/selinux/odm_sepolicy.cil" \
  -o "$work/out/policy-baseline.bin" -f /dev/null \
  2> "$work/out/secilc-baseline.log"
baseline_status=$?
"$secilc_bin" -m -M true -G -c 33 "${inputs[@]}" \
  "$policy/odm/etc/selinux/odm_sepolicy.cil" \
  -o "$work/out/policy-candidate.bin" -f /dev/null \
  2> "$work/out/secilc-candidate.log"
candidate_status=$?
set -e
test "$baseline_status" -eq "$candidate_status"
sed -e 's#odm/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#odm_base/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
  "$work/out/secilc-baseline.log" > "$work/out/secilc-baseline.normalized.log"
sed -e 's#odm/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#odm_base/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
  "$work/out/secilc-candidate.log" > "$work/out/secilc-candidate.normalized.log"
cmp "$work/out/secilc-baseline.normalized.log" \
  "$work/out/secilc-candidate.normalized.log"
for m in odm odm_base vendor product system_ext system; do umount "$policy/$m"; done

# Rebuild only my_manifest for application-facing identity. Vendor and ODM
# identities remain Redmi/prague and are outside this tiny extent.
dd if="$pre/images/super.img" of="$work/out/my_manifest.base.img" \
  iflag=skip_bytes,count_bytes skip="$my_manifest_offset" count="$my_manifest_size" status=none
fsck.erofs "$work/out/my_manifest.base.img" > "$work/out/fsck-my_manifest-base.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/my_manifest.base.img" "$overlay/lower"

root_label=$(getfattr -n security.selinux --only-values "$overlay/lower")
setfattr -n security.selinux -v "$root_label" "$overlay/upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"

manifest_prop="$overlay/merged/build.prop"
test -f "$manifest_prop"
sed -i \
  -e 's/^ro\.vendor\.oplus\.market\.name=.*/ro.vendor.oplus.market.name=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.model=.*/ro.product.model=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.marketname=.*/ro.product.marketname=一加 Ace 6 至尊版/' \
  -e 's/^ro\.product\.bootimage\.model=.*/ro.product.bootimage.model=一加 Ace 6 至尊版/' \
  "$manifest_prop"
for key in ro.config.bt_name ro.config.wifi_ap_ssid; do
  if grep -q "^$key=" "$manifest_prop"; then
    sed -i "s/^$key=.*/$key=一加 Ace 6 至尊版/" "$manifest_prop"
  else
    printf '%s\n' "$key=一加 Ace 6 至尊版" >> "$manifest_prop"
  fi
done

mkdir -p "$overlay/upper"
cp --attributes-only --preserve=all "$overlay/lower/build.prop" "$overlay/upper/build.prop"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/upper/build.prop"

python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/merged" /my_manifest "$work/out/my_manifest_file_contexts.generated" \
  --override /my_manifest/build.prop=u:object_r:vendor_file:s0 \
  > "$work/out/my_manifest-file-contexts-generation.txt"

uuid=$(blkid -o value -s UUID "$work/out/my_manifest.base.img")
label=$(blkid -o value -s LABEL "$work/out/my_manifest.base.img" || true)
args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || args+=(-L "$label")
args+=(--mount-point=/my_manifest --file-contexts="$work/out/my_manifest_file_contexts.generated")
mkfs.erofs "${args[@]}" "$work/out/my_manifest.raw.img" "$overlay/merged" \
  > "$work/out/mkfs-my_manifest.log" 2>&1
test "$(stat -c%s "$work/out/my_manifest.raw.img")" -le "$my_manifest_size"
cp --sparse=always "$work/out/my_manifest.raw.img" "$work/out/my_manifest.img"
truncate -s "$my_manifest_size" "$work/out/my_manifest.img"
umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/out/my_manifest.img" > "$work/out/fsck-my_manifest.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/my_manifest.img" "$overlay/verify"
grep -q '^ro.vendor.oplus.market.name=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
grep -q '^ro.product.model=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
grep -q '^ro.product.marketname=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
grep -q '^ro.config.bt_name=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
grep -q '^ro.config.wifi_ap_ssid=一加 Ace 6 至尊版$' "$overlay/verify/build.prop"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/build.prop")" = \
  u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || missing=$((missing + 1))
done < <(find "$overlay/verify" -xdev \( -type f -o -type d \) -print0)
test "$missing" -eq 0
umount "$overlay/verify"

building="$work/out/super.img.building"
cp --sparse=always "$pre/images/super.img" "$building"
dd if="$work/out/my_manifest.img" of="$building" bs=4096 \
  seek=$((my_manifest_offset / 4096)) conv=notrunc,fsync status=none
test "$(stat -c%s "$building")" -eq "$super_size"

dd if="$building" of="$work/out/my_manifest.readback.img" \
  iflag=skip_bytes,count_bytes skip="$my_manifest_offset" count="$my_manifest_size" status=none
dd if="$building" of="$work/out/odm.readback.img" \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/out/my_manifest.img" "$work/out/my_manifest.readback.img"
fsck.erofs "$work/out/my_manifest.readback.img" > "$work/out/fsck-my_manifest-readback.txt" 2>&1
fsck.erofs "$work/out/odm.readback.img" > "$work/out/fsck-odm-readback.txt" 2>&1

# Only my_manifest and ODM may differ from the booted Stage62 baseline.
cmp -n "$my_manifest_offset" "$base/images/super.img" "$building"
middle_start=$((my_manifest_offset + my_manifest_size))
cmp -n "$((odm_offset - middle_start))" -i "$middle_start:$middle_start" \
  "$base/images/super.img" "$building"
odm_tail=$((odm_offset + odm_size))
cmp -n "$((super_size - odm_tail))" -i "$odm_tail:$odm_tail" \
  "$base/images/super.img" "$building"

cp --sparse=always "$building" "$out/images/super.img.building"
mv "$out/images/super.img.building" "$out/images/super.img"
cp -a "$base/platform-tools" "$out/"
cp "$pre/audit/"* "$out/audit/" 2>/dev/null || true
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/out/my_manifest.img" "$work/out/odm.readback.img" \
  > "$out/audit/component-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage63 confirmed-fixes integration candidate
Base: device-booted Stage62
Changed partitions: ODM and my_manifest only
Data wipe: no

Implemented in this candidate:
- Keeps the Stage62 IOplusMisc fan service and exact system_app Binder access.
- Adds the built-in bridge to Xiaomi's existing hal_micharge_client attribute,
  inheriting the vendor-approved discovery/Binder path; no wattage is fabricated.
- Adds atomic rename/unlink access for the existing performance and charging
  state files after matching Stage62 denials.
- Keeps read-only MTK GPU/DDR/UFS observation access and PowerHAL perfserv
  access from Stage62.
- Rebuilds the real my_manifest source properties for the application-facing
  Chinese model, Bluetooth default and hotspot default while leaving the
  vendor/ODM Redmi prague hardware identity untouched.

Inherited unchanged from Stage62:
- System, system_ext, product, vendor and all camera/framework content.
- Existing brightness, AOD, camera, signal and charging compatibility content
  already present in the booted baseline.

Not claimed:
- Physical fan airflow still requires a real UI write and hardware check.
- Full Oplus IPerformance/URCC/UAH translation is not yet implemented.
- Fingerprint enrollment UI, automatic brightness, color/PWM, full-screen AOD,
  haptic mapping and camera performance are not proven by these policy changes.
- No TEE/private key, unsupported 90 Hz mode or absent hardware is fabricated.

Offline checks:
- EROFS fsck passed for rebuilt and read-back images.
- Every rebuilt file and directory has a SELinux xattr.
- ODM policy binary read-back passed with unchanged version/type/class/permissive maps.
- Full split-policy strict baseline/candidate diagnostics are identical; no
  neverallow check was disabled or bypassed.
- Every byte outside the my_manifest and ODM extents matches Stage62.
EOF

echo STAGE63_OFFLINE_BUILD_PASSED
