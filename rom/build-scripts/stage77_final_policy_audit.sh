#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage76_NANDSWAP_CARRIER/images/super.img
cand=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage77_INTEGRATED/images/super.img
audit=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage77_INTEGRATED/audit
work=/root/k90_stage77_final_policy_audit
tool=$src/stage44_toolchain_source/selinux-main/secilc/secilc

system_offset=$((2048 * 512))
system_size=$((2072528 * 512))
system_ext_offset=$((259328 * 4096))
system_ext_size=1087639552
product_offset=$((525056 * 4096))
product_size=152326144
vendor_offset=$((2000640 * 4096))
vendor_size=2517786624
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))

test -s "$base"
test -s "$cand"
test -x "$tool"
rm -rf "$work"
mkdir -p "$work"/{system,system_ext,product,vendor,odm_base,odm_cand,out}

cleanup() {
  for part in odm_cand odm_base vendor product system_ext system; do
    mountpoint -q "$work/$part" && umount "$work/$part" || true
  done
}
trap cleanup EXIT

mount -t erofs -o ro,loop,offset="$system_offset",sizelimit="$system_size" "$cand" "$work/system"
mount -t erofs -o ro,loop,offset="$system_ext_offset",sizelimit="$system_ext_size" "$cand" "$work/system_ext"
mount -t erofs -o ro,loop,offset="$product_offset",sizelimit="$product_size" "$cand" "$work/product"
mount -t erofs -o ro,loop,offset="$vendor_offset",sizelimit="$vendor_size" "$cand" "$work/vendor"
mount -t erofs -o ro,loop,offset="$odm_offset",sizelimit="$odm_size" "$base" "$work/odm_base"
mount -t erofs -o ro,loop,offset="$odm_offset",sizelimit="$odm_size" "$cand" "$work/odm_cand"

vers=$(cat "$work/vendor/etc/selinux/plat_sepolicy_vers.txt")
test "$vers" = 202504
inputs=(
  "$work/system/system/etc/selinux/plat_sepolicy.cil"
  "$work/system/system/etc/selinux/mapping/$vers.cil"
  "$work/system_ext/etc/selinux/system_ext_sepolicy.cil"
  "$work/system_ext/etc/selinux/mapping/$vers.cil"
  "$work/product/etc/selinux/product_sepolicy.cil"
  "$work/product/etc/selinux/mapping/$vers.cil"
  "$work/vendor/etc/selinux/plat_pub_versioned.cil"
  "$work/vendor/etc/selinux/vendor_sepolicy.cil"
)
for optional in \
  "$work/system/system/etc/selinux/mapping/$vers.compat.cil" \
  "$work/system/system/etc/selinux/plat_sepolicy_genfs_202504.cil" \
  "$work/system_ext/etc/selinux/mapping/$vers.compat.cil"; do
  [[ -f "$optional" ]] && inputs+=("$optional")
done
for input in "${inputs[@]}"; do test -f "$input"; done
printf '%s\n' "${inputs[@]}" > "$work/out/final-policy-inputs.txt"

base_policy=$work/odm_base/etc/selinux/odm_sepolicy.cil
cand_policy=$work/odm_cand/etc/selinux/odm_sepolicy.cil
grep -q '^(typeattributeset hal_power_client (oplus_game_service))$' "$cand_policy"
grep -q '^(allow oplus_game_service vendor_touch_init_shell (binder (call transfer)))$' "$cand_policy"
grep -q '^(allow vendor_touch_init_shell oplus_game_service (binder (transfer)))$' "$cand_policy"
! grep -q '^(allow oplus_game_service hal_power_service (service_manager (find)))$' "$cand_policy"

set +e
"$tool" -m -M true -G -c 33 "${inputs[@]}" "$base_policy" \
  -o "$work/out/base.bin" -f /dev/null 2> "$work/out/final-base.log"
base_status=$?
"$tool" -m -M true -G -c 33 "${inputs[@]}" "$cand_policy" \
  -o "$work/out/candidate.bin" -f /dev/null 2> "$work/out/final-candidate.log"
cand_status=$?
set -e

normalize() {
  sed -E \
    -e 's#/root/k90_stage77_final_policy_audit/odm_(base|cand)/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#/root/k90_stage77_final_policy_audit/#POLICY_ROOT/#g' \
    "$1" > "$2"
}
normalize "$work/out/final-base.log" "$work/out/final-base.normalized.log"
normalize "$work/out/final-candidate.log" "$work/out/final-candidate.normalized.log"
printf 'BASE_STATUS=%s\nCAND_STATUS=%s\n' "$base_status" "$cand_status" \
  > "$work/out/final-policy-status.txt"
test "$base_status" -eq "$cand_status"
cmp "$work/out/final-base.normalized.log" "$work/out/final-candidate.normalized.log"

cp "$work/out/"*.txt "$work/out/"*.log "$audit/"
echo STAGE77_FINAL_POLICY_AUDIT_PASSED
