#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage79_MODEL_SIM_COLOR_PERF
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage80_PERF_POLICY
work=/root/k90_stage80_work
overlay=/root/k90_stage80_overlay
tool=$src/stage44_toolchain_source/selinux-main/secilc/secilc
charge_module=$src/sms_module_inspect_ef1dae3134fc4e2281a3efa36e8ca6af

super_size=13421772800
system_offset=$((2048 * 512))
system_size=$((2072528 * 512))
system_ext_offset=$((259328 * 4096))
system_ext_size=1087639552
product_offset=$((525056 * 4096))
product_size=152326144
product_end=$((product_offset + product_size))
vendor_offset=$((2000640 * 4096))
vendor_size=2517786624
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
odm_end=$((odm_offset + odm_size))
base_hash=c3894b87ec5184eb34927808d0bbdf76f900171703397188c019ade92422453e
charger_hash=52dfae45f6a58932083c998aad75d64b383b02894a531e33dfb864ddb937311c
perf_rule='(allow mtk_hal_power hal_uniperf_default (file (getattr open read)))'
charge_dir_rule='(allow hal_batteryantiaging_default sysfs_ti_battery (dir (getattr search open read)))'
charge_file_rule='(allow hal_batteryantiaging_default sysfs_ti_battery (file (getattr open read)))'
charge_control_rule='(allow vendor_touch_init_shell sysfs_usb_supply (file (getattr open read write)))'

base_super=$base/images/super.img
for tool_name in mkfs.erofs fsck.erofs getfattr setfattr sha256sum cmp blkid; do
  command -v "$tool_name" >/dev/null
done
test -x "$tool"
test -s "$charge_module/bin/vendor.oplus.hardware.charger-V11-service"
test -s "$charge_module/script/charge_daemon.sh"
test "$(stat -c%s "$base_super")" -eq "$super_size"
test "$(sha256sum "$base_super" | cut -d' ' -f1)" = "$base_hash"

rm -rf "$work" "$overlay" "$out"
mkdir -p "$work/out" "$work/policy" \
  "$overlay"/{lower,upper,work,merged,verify,product_lower,product_upper,product_work,product_merged,product_verify} \
  "$out"/{images,audit}

cleanup() {
  for p in "$work/policy"/{odm,odm_base,vendor,product,system_ext,system}; do
    mountpoint -q "$p" && umount "$p" || true
  done
  for p in "$overlay"/{product_verify,product_merged,product_lower,verify,merged,lower}; do
    mountpoint -q "$p" && umount "$p" || true
  done
}
trap cleanup EXIT

dd if="$base_super" of="$work/out/product.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$product_offset" count="$product_size" status=none
dd if="$base_super" of="$work/out/odm.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
fsck.erofs "$work/out/product.base.img" > "$work/out/fsck-product-base.txt" 2>&1
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.txt" 2>&1

# PRODUCT: disable the obsolete /data/adb launcher. Stage80 starts the same
# verified V11 bridge and charge policy natively from ODM after boot completes.
mount -t erofs -o ro,loop "$work/out/product.base.img" "$overlay/product_lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/product_lower")" \
  "$overlay/product_upper"
mkdir -p "$overlay/product_upper/bin"
chmod --reference="$overlay/product_lower/bin" "$overlay/product_upper/bin"
chown --reference="$overlay/product_lower/bin" "$overlay/product_upper/bin"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/product_lower/bin")" \
  "$overlay/product_upper/bin"
launcher=bin/k90-native-charge-launcher.sh
cp --preserve=all "$overlay/product_lower/$launcher" "$overlay/product_upper/$launcher"
printf '%s\n' '#!/system/bin/sh' '# Stage80: native charge services are owned by ODM init.' 'exit 0' \
  > "$overlay/product_upper/$launcher"
chmod 0755 "$overlay/product_upper/$launcher"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/product_upper/$launcher"
mount -t overlay overlay \
  -o "lowerdir=$overlay/product_lower,upperdir=$overlay/product_upper,workdir=$overlay/product_work" \
  "$overlay/product_merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/product_merged" /product \
  "$work/out/product_file_contexts" \
  --override /product/bin/k90-native-charge-launcher.sh=u:object_r:system_file:s0 \
  > "$work/out/product-contexts.txt"
product_uuid=$(blkid -o value -s UUID "$work/out/product.base.img")
product_label=$(blkid -o value -s LABEL "$work/out/product.base.img" || true)
product_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$product_uuid" --preserve-mtime \
  --mount-point=/product --file-contexts="$work/out/product_file_contexts")
[[ -z "$product_label" ]] || product_args+=(-L "$product_label")
mkfs.erofs "${product_args[@]}" "$work/out/product.raw.img" "$overlay/product_merged" \
  > "$work/out/mkfs-product.log" 2>&1
test "$(stat -c%s "$work/out/product.raw.img")" -le "$product_size"
cp --sparse=always "$work/out/product.raw.img" "$work/out/product.img"
truncate -s "$product_size" "$work/out/product.img"
umount "$overlay/product_merged"
umount "$overlay/product_lower"
fsck.erofs "$work/out/product.img" > "$work/out/fsck-product.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/lower"
test "$(getfattr -n security.selinux --only-values "$overlay/lower/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
base_cil="$overlay/lower/etc/selinux/odm_sepolicy.cil"
test -s "$base_cil"
for rule in "$perf_rule" "$charge_dir_rule" "$charge_file_rule" "$charge_control_rule"; do
  ! grep -Fqx "$rule" "$base_cil"
done

setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/lower")" \
  "$overlay/upper"
mkdir -p "$overlay/upper/etc/selinux"
for rel in etc etc/selinux; do
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done
cp --preserve=all "$base_cil" "$overlay/upper/etc/selinux/odm_sepolicy.cil"
printf '\n%s\n%s\n%s\n%s\n' "$perf_rule" "$charge_dir_rule" "$charge_file_rule" "$charge_control_rule" \
  >> "$overlay/upper/etc/selinux/odm_sepolicy.cil"
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/upper/etc/selinux/odm_sepolicy.cil"
for rule in "$perf_rule" "$charge_dir_rule" "$charge_file_rule" "$charge_control_rule"; do
  test "$(grep -Fxc "$rule" "$overlay/upper/etc/selinux/odm_sepolicy.cil")" -eq 1
done

# Compile the exact Stage79 split policy once with the unmodified ODM CIL and
# once with the candidate. The candidate must compile successfully and may not
# introduce a different diagnostic set.
mkdir -p "$work/policy"/{system,system_ext,product,vendor,odm,odm_base}
mount -t erofs -o ro,loop,offset="$system_offset",sizelimit="$system_size" \
  "$base_super" "$work/policy/system"
mount -t erofs -o ro,loop,offset="$system_ext_offset",sizelimit="$system_ext_size" \
  "$base_super" "$work/policy/system_ext"
mount -t erofs -o ro,loop,offset="$product_offset",sizelimit="$product_size" \
  "$base_super" "$work/policy/product"
mount -t erofs -o ro,loop,offset="$vendor_offset",sizelimit="$vendor_size" \
  "$base_super" "$work/policy/vendor"
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$work/policy/odm_base"
vers=$(cat "$work/policy/vendor/etc/selinux/plat_sepolicy_vers.txt")
test "$vers" = 202504
test "$(sha256sum "$work/policy/product/bin/vendor.oplus.hardware.charger-V11-service" | cut -d' ' -f1)" = "$charger_hash"
inputs=(
  "$work/policy/system/system/etc/selinux/plat_sepolicy.cil"
  "$work/policy/system/system/etc/selinux/mapping/$vers.cil"
  "$work/policy/system_ext/etc/selinux/system_ext_sepolicy.cil"
  "$work/policy/system_ext/etc/selinux/mapping/$vers.cil"
  "$work/policy/product/etc/selinux/product_sepolicy.cil"
  "$work/policy/product/etc/selinux/mapping/$vers.cil"
  "$work/policy/vendor/etc/selinux/plat_pub_versioned.cil"
  "$work/policy/vendor/etc/selinux/vendor_sepolicy.cil"
)
for optional in \
  "$work/policy/system/system/etc/selinux/mapping/$vers.compat.cil" \
  "$work/policy/system/system/etc/selinux/plat_sepolicy_genfs_202504.cil" \
  "$work/policy/system_ext/etc/selinux/mapping/$vers.compat.cil"; do
  [[ -f "$optional" ]] && inputs+=("$optional")
done
printf '%s\n' "${inputs[@]}" > "$work/out/policy-inputs.txt"

set +e
"$tool" -m -M true -G -c 33 "${inputs[@]}" "$base_cil" \
  -o "$work/out/base-policy.bin" -f /dev/null 2> "$work/out/base-policy.log"
base_status=$?
"$tool" -m -M true -G -c 33 "${inputs[@]}" \
  "$overlay/upper/etc/selinux/odm_sepolicy.cil" \
  -o "$work/out/candidate-policy.bin" -f /dev/null 2> "$work/out/candidate-policy.log"
cand_status=$?
set -e
printf 'BASE_STATUS=%s\nCAND_STATUS=%s\n' "$base_status" "$cand_status" \
  > "$work/out/policy-status.txt"
test "$base_status" -eq "$cand_status"
normalize_policy_log() {
  sed -E \
    -e 's#/root/k90_stage80_work/policy/odm_base/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#/root/k90_stage80_overlay/lower/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#/root/k90_stage80_overlay/upper/etc/selinux/odm_sepolicy\.cil#ODM_POLICY#g' \
    -e 's#/root/k90_stage80_work/#POLICY_ROOT/#g' \
    "$1" > "$2"
}
normalize_policy_log "$work/out/base-policy.log" "$work/out/base-policy.normalized.log"
normalize_policy_log "$work/out/candidate-policy.log" "$work/out/candidate-policy.normalized.log"
cmp "$work/out/base-policy.normalized.log" "$work/out/candidate-policy.normalized.log"

# Replace the stale native charge runtime with the module-proven V11 bridge and
# an ODM-owned, no-root temperature policy. It starts only after boot_completed.
for rel in bin etc/init; do
  mkdir -p "$overlay/upper/$rel"
  chmod --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  chown --reference="$overlay/lower/$rel" "$overlay/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/lower/$rel")" \
    "$overlay/upper/$rel"
done
mkdir -p "$overlay/upper/etc/k90"
chmod 0755 "$overlay/upper/etc/k90"
chown 0:0 "$overlay/upper/etc/k90"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$overlay/upper/etc/k90"

charger_rel=bin/vendor.oplus.hardware.charger-V11-service
install -m 0755 "$charge_module/bin/vendor.oplus.hardware.charger-V11-service" \
  "$overlay/upper/$charger_rel"
chown 0:0 "$overlay/upper/$charger_rel"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/upper/$charger_rel"
test "$(sha256sum "$overlay/upper/$charger_rel" | cut -d' ' -f1)" = "$charger_hash"

daemon_rel=bin/k90-charge-daemon.sh
sed \
  -e 's#/data/adb/k90max#/data/vendor/k90max#g' \
  -e 's/MODE=balanced/MODE=aggressive/g' \
  "$charge_module/script/charge_daemon.sh" > "$overlay/upper/$daemon_rel"
chmod 0755 "$overlay/upper/$daemon_rel"
chown 0:0 "$overlay/upper/$daemon_rel"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/upper/$daemon_rel"
grep -q '^MARK=/data/vendor/k90max$' "$overlay/upper/$daemon_rel"
grep -q 'MODE=aggressive' "$overlay/upper/$daemon_rel"
grep -q 'THERMAL_REMOVE=/sys/class/power_supply/usb/thermal_remove' "$overlay/upper/$daemon_rel"

cat > "$overlay/upper/etc/k90/charge-scheduler.conf" <<'EOF'
# Dynamic Xiaomi charge policy. Kernel JEITA and electrical protections remain authoritative.
ENABLE=1
MODE=aggressive
SCHEDULE=0
START_TIME=00:00
END_TIME=23:59
HYSTERESIS=2
POLL_SEC=5
EOF
chmod 0644 "$overlay/upper/etc/k90/charge-scheduler.conf"
chown 0:0 "$overlay/upper/etc/k90/charge-scheduler.conf"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/upper/etc/k90/charge-scheduler.conf"

cat > "$overlay/upper/etc/init/k90-native-charge.rc" <<'EOF'
service k90-oplus-charger /odm/bin/vendor.oplus.hardware.charger-V11-service
    class late_start
    user system
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0
    disabled

service k90-charge-daemon /system/vendor/bin/sh /odm/bin/k90-charge-daemon.sh
    class late_start
    user system
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0
    disabled

on post-fs-data
    mkdir /data/vendor/k90max 0770 system system

on property:sys.boot_completed=1
    start k90-oplus-charger
    start k90-charge-daemon
EOF
chmod 0644 "$overlay/upper/etc/init/k90-native-charge.rc"
chown 0:0 "$overlay/upper/etc/init/k90-native-charge.rc"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 \
  "$overlay/upper/etc/init/k90-native-charge.rc"

mount -t overlay overlay \
  -o "lowerdir=$overlay/lower,upperdir=$overlay/upper,workdir=$overlay/work" \
  "$overlay/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/merged" /odm \
  "$work/out/odm_file_contexts" \
  --override /odm/bin/vendor.oplus.hardware.charger-V11-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/bin/k90-charge-daemon.sh=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/etc/k90=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/k90/charge-scheduler.conf=u:object_r:vendor_configs_file:s0 \
  --override /odm/etc/init/k90-native-charge.rc=u:object_r:vendor_configs_file:s0 \
  --override /odm/lib/modules=u:object_r:vendor_file:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/etc/selinux/odm_sepolicy.cil=u:object_r:sepolicy_file:s0 \
  > "$work/out/odm-contexts.txt"
odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime \
  --mount-point=/odm --file-contexts="$work/out/odm_file_contexts")
[[ -z "$odm_label" ]] || odm_args+=(-L "$odm_label")
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" "$overlay/merged" \
  > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/merged"
umount "$overlay/lower"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
for rule in "$perf_rule" "$charge_dir_rule" "$charge_file_rule" "$charge_control_rule"; do
  test "$(grep -Fxc "$rule" "$overlay/verify/etc/selinux/odm_sepolicy.cil")" -eq 1
done
test "$(sha256sum "$overlay/verify/$charger_rel" | cut -d' ' -f1)" = "$charger_hash"
grep -q '^MARK=/data/vendor/k90max$' "$overlay/verify/$daemon_rel"
grep -q 'MODE=aggressive' "$overlay/verify/$daemon_rel"
! grep -q '/data/adb/' "$overlay/verify/$daemon_rel"
grep -q '^service k90-charge-daemon ' "$overlay/verify/etc/init/k90-native-charge.rc"
! grep -q '^    copy /product/' "$overlay/verify/etc/init/k90-native-charge.rc"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/selinux/odm_sepolicy.cil")" = u:object_r:sepolicy_file:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -h -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-labels-odm.txt"
    missing=$((missing + 1))
  fi
done < <(find "$overlay/verify" -xdev -print0)
test "$missing" -eq 0
umount "$overlay/verify"

mount -t erofs -o ro,loop "$work/out/product.img" "$overlay/product_verify"
grep -q '^# Stage80: native charge services are owned by ODM init\.$' \
  "$overlay/product_verify/bin/k90-native-charge-launcher.sh"
product_missing=0
while IFS= read -r -d '' item; do
  if ! getfattr -h -n security.selinux --only-values "$item" >/dev/null 2>&1; then
    printf '%s\n' "$item" >> "$work/out/missing-labels-product.txt"
    product_missing=$((product_missing + 1))
  fi
done < <(find "$overlay/product_verify" -xdev -print0)
test "$product_missing" -eq 0
umount "$overlay/product_verify"

building="$out/images/super.img.building"
cp --reflink=auto --sparse=always "$base_super" "$building"
dd if="$work/out/product.img" of="$building" bs=4096 \
  seek=$((product_offset / 4096)) conv=notrunc,fsync status=progress
dd if="$work/out/odm.img" of="$building" bs=4096 \
  seek=$((odm_offset / 4096)) conv=notrunc,fsync status=progress
test "$(stat -c%s "$building")" -eq "$super_size"
cmp -n "$product_offset" "$base_super" "$building"
cmp -n $((odm_offset - product_end)) -i "$product_end:$product_end" "$base_super" "$building"
cmp -n $((super_size - odm_end)) -i "$odm_end:$odm_end" "$base_super" "$building"
dd if="$building" of="$work/out/product.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$product_offset" count="$product_size" status=none
dd if="$building" of="$work/out/odm.readback.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
cmp "$work/out/product.img" "$work/out/product.readback.img"
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
fsck.erofs "$work/out/product.readback.img" > "$work/out/fsck-product-readback.txt" 2>&1
fsck.erofs "$work/out/odm.readback.img" > "$work/out/fsck-odm-readback.txt" 2>&1

mv "$building" "$out/images/super.img"
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/"
cat > "$out/STATUS.txt" <<EOF
Stage80 performance-policy update built from bootable Stage79.
Only the product and ODM extents changed.
Added exact split-CIL permission:
$perf_rule
$charge_dir_rule
$charge_file_rule
$charge_control_rule
Preserved and verified the module-proven V11 Xiaomi MiCharge to ColorOS ICharger bridge.
Replaced the stale /data/adb charge launcher with an ODM-owned /data/vendor dynamic thermal policy.
No boot/init_boot/vendor_boot/dtbo/vbmeta/radio partition was changed.
Data-preserving super-only flash intended.
EOF
echo STAGE80_BUILD_OK
