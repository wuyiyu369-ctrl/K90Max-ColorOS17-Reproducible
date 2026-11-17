#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage62_INTEGRATED_POLICY
pre=/root/k90_stage63_pre
work=/root/k90_stage63_manifest_work
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage63_CONFIRMED_FIXES

super_size=13421772800
manifest_offset=$((4499456 * 512))
manifest_size=$((1152 * 512))
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))

test -s "$pre/images/super.img"
test "$(stat -c%s "$pre/images/super.img")" -eq "$super_size"
test -s "$work/out/my_manifest.img"
test "$(stat -c%s "$work/out/my_manifest.img")" -eq "$manifest_size"
cmp "$work/out/secilc-baseline.normalized.log" \
  "$work/out/secilc-candidate.normalized.log"
grep -q '^POLICY_READBACK_OK ' "$pre/audit/policy-patch.txt"
grep -q '^typeattribute vendor_touch_init_shell hal_micharge_client;$' \
  "$pre/audit/policy-patch.txt"

rm -rf "$out"
mkdir -p "$out/images" "$out/audit"
cp --sparse=always "$pre/images/super.img" "$out/images/super.img.building"
dd if="$work/out/my_manifest.img" of="$out/images/super.img.building" \
  bs=4096 seek=$((manifest_offset / 4096)) conv=notrunc,fsync status=progress
test "$(stat -c%s "$out/images/super.img.building")" -eq "$super_size"
mv "$out/images/super.img.building" "$out/images/super.img"

# Final image differs from the validated ODM preimage only in my_manifest.
cmp -n "$manifest_offset" "$pre/images/super.img" "$out/images/super.img"
tail_start=$((manifest_offset + manifest_size))
cmp -n "$((super_size - tail_start))" -i "$tail_start:$tail_start" \
  "$pre/images/super.img" "$out/images/super.img"
test "$(dd if="$out/images/super.img" iflag=skip_bytes,count_bytes \
  skip="$manifest_offset" count="$manifest_size" status=none | sha256sum | cut -d' ' -f1)" = \
  "$(sha256sum "$work/out/my_manifest.img" | cut -d' ' -f1)"
test "$(dd if="$out/images/super.img" iflag=skip_bytes,count_bytes \
  skip="$odm_offset" count="$odm_size" status=none | sha256sum | cut -d' ' -f1)" = \
  "$(dd if="$pre/images/super.img" iflag=skip_bytes,count_bytes \
  skip="$odm_offset" count="$odm_size" status=none | sha256sum | cut -d' ' -f1)"

cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$pre/audit/"* "$out/audit/" 2>/dev/null || true
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$work/out/my_manifest.img" > "$out/audit/my-manifest-sha256.txt"

cat > "$out/STATUS.txt" <<'EOF'
Stage63 confirmed-fixes integration candidate
Base: device-booted Stage62
Changed partitions: ODM and my_manifest only
Data wipe: no

Implemented in this candidate:
- Keeps the booted Stage62 IOplusMisc fan Binder integration and fan mapping.
- Adds the native bridge to Xiaomi's existing hal_micharge_client attribute,
  reusing the vendor-approved discovery/Binder rules. No wattage is fabricated.
- Adds atomic rename/unlink access for existing performance/charging state files.
- Rebuilds the real my_manifest properties for the Chinese model name,
  Bluetooth default and hotspot default while preserving prague hardware IDs.
- Removes the ineffective cross-partition zygote fingerprint-property rule.

Offline checks:
- Native fan mapping self-test passed.
- ODM EROFS fsck, read-back and complete SELinux xattr scan passed.
- Standalone ODM policy binary read-back preserved version/type/class/permissive maps.
- Full split-policy strict baseline/candidate diagnostics are identical; no
  neverallow check was disabled or bypassed.
- my_manifest EROFS fsck/read-back/xattr checks passed.
- Final image equals the validated ODM preimage outside my_manifest.

Not claimed until live testing:
- Physical fan airflow and all Ace7 smart fan modes.
- Charging protocol read-back or real-time power UI.
- Full Oplus IPerformance/URCC/UAH translation.
- Fingerprint enrollment UI, automatic brightness, color/PWM, full-screen AOD,
  haptic mapping or camera performance.
EOF

echo STAGE63_OFFLINE_BUILD_PASSED
