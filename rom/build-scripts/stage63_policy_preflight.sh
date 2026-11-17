#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
input="$src/policy_inputs_device_exact"
work=/root/stage63_policy_preflight

rm -rf "$work"
mkdir -p "$work"
cp "$input"/* "$work/"
cp "$work/odm_etc_selinux_odm_sepolicy.cil" "$work/odm-candidate.cil"
cat >> "$work/odm-candidate.cil" <<'EOF'
(typeattributeset hal_micharge_client (vendor_touch_init_shell))
(allow vendor_touch_init_shell vendor_data_file (dir (getattr search open write add_name remove_name)))
(allow vendor_touch_init_shell vendor_data_file (file (getattr create open read write append rename unlink)))
EOF

inputs=(
  "$work/system_etc_selinux_plat_sepolicy.cil" \
  "$work/system_etc_selinux_mapping_202504.cil" \
  "$work/system_etc_selinux_mapping_202504.compat.cil" \
  "$work/system_etc_selinux_plat_sepolicy_genfs_202504.cil" \
  "$work/system_ext_etc_selinux_system_ext_sepolicy.cil" \
  "$work/system_ext_etc_selinux_mapping_202504.cil" \
  "$work/system_ext_etc_selinux_mapping_202504.compat.cil" \
  "$work/vendor_etc_selinux_plat_pub_versioned.cil" \
  "$work/vendor_etc_selinux_vendor_sepolicy.cil"
)
tool="$src/stage44_toolchain_source/selinux-main/secilc/secilc"
set +e
"$tool" -m -M true -G -c 33 "${inputs[@]}" \
  "$work/odm_etc_selinux_odm_sepolicy.cil" \
  -o "$work/baseline.bin" -f /dev/null 2> "$work/baseline.log"
baseline_status=$?
"$tool" -m -M true -G -c 33 "${inputs[@]}" "$work/odm-candidate.cil" \
  -o "$work/candidate.bin" -f /dev/null 2> "$work/candidate.log"
candidate_status=$?
set -e
test "$baseline_status" -eq "$candidate_status"
sed 's#odm-candidate\.cil#odm_etc_selinux_odm_sepolicy.cil#g' \
  "$work/candidate.log" > "$work/candidate.normalized.log"
cmp "$work/baseline.log" "$work/candidate.normalized.log"
! grep -q 'allow at .*odm-candidate.cil' "$work/candidate.log"
echo POLICY_PREFLIGHT_PASSED
printf 'STRICT_BASELINE_STATUS=%s\nSTRICT_CANDIDATE_STATUS=%s\n' \
  "$baseline_status" "$candidate_status"
