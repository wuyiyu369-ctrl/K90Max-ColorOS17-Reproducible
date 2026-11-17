#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_FACTORY_RESET_CANDIDATE_Stage49
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Stage50_CHARGE_FAN_POLICY
work=$root/02_Codex完整工作区/wo/stage50_work
overlay=/root/k90_stage50_overlay_v3
charge=$root/02_Codex完整工作区/wo/build_v1747
avb=$root/02_Codex完整工作区/wo/tools/avb/avbtool.py

product_offset=2150629376
product_size=152326144
odm_offset=10713300992
odm_size=1724530688
super_size=13421772800

mkdir -p "$work/out" "$delivery/images" "$delivery/audit"
mkdir -p "$overlay"/{product_lower,product_upper,product_work,product_merged,odm_lower,odm_upper,odm_work,odm_merged,verify}
cleanup(){
  for m in verify product_merged product_lower odm_merged odm_lower; do
    mountpoint -q "$overlay/$m" && umount "$overlay/$m" || true
  done
}
trap cleanup EXIT

test -s "$base/images/super.img"
test "$(stat -c%s "$base/images/super.img")" -eq "$super_size"
test -x "$src/stage50_policy_patch"
test -x "$charge/bin/vendor.oplus.hardware.charger-V11-service"
test -s "$charge/script/charge_daemon.sh"
grep -q '^BASELINE_AND_CANDIDATE_DIAGNOSTICS_IDENTICAL' "$src/stage44_policy/strict_differential.txt"

if [[ ! -s "$work/out/product.base.img" ]]; then
  dd if="$base/images/super.img" of="$work/out/product.base.img" bs=16M \
    skip="$product_offset" count="$product_size" iflag=skip_bytes,count_bytes status=progress
fi
if [[ ! -s "$work/out/odm.base.img" ]]; then
  dd if="$base/images/super.img" of="$work/out/odm.base.img" bs=16M \
    skip="$odm_offset" count="$odm_size" iflag=skip_bytes,count_bytes status=progress
fi
test "$(stat -c%s "$work/out/product.base.img")" -eq "$product_size"
test "$(stat -c%s "$work/out/odm.base.img")" -eq "$odm_size"
fsck.erofs "$work/out/product.base.img" > "$work/out/fsck-product-base.txt" 2>&1
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.txt" 2>&1
for part in product odm; do
  if python3 "$avb" info_image --image "$work/out/$part.base.img" > "$work/out/avb-$part-base.txt" 2>&1; then
    echo HAS_AVB_FOOTER > "$work/out/avb-$part-state.txt"
  else
    echo NO_STANDALONE_AVB_FOOTER > "$work/out/avb-$part-state.txt"
  fi
done

mount -t erofs -o ro,loop "$work/out/product.base.img" "$overlay/product_lower"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/product_lower" 2>/dev/null)" "$overlay/product_upper"
mount -t overlay overlay -o "lowerdir=$overlay/product_lower,upperdir=$overlay/product_upper,workdir=$overlay/product_work" "$overlay/product_merged"

install -d -m 0755 "$overlay/product_merged/etc/k90"
cat > "$overlay/product_merged/etc/k90/charge-scheduler.conf" <<'EOF'
# Xiaomi charging policy. Hardware PD authentication, JEITA, connector and
# battery protection remain authoritative; no fixed current or fake wattage.
ENABLE=1
MODE=aggressive
SCHEDULE=0
START_TIME=00:00
END_TIME=23:59
HYSTERESIS=2
POLL_SEC=5
EOF
contexts="$overlay/product_merged/etc/selinux/product_service_contexts"
grep -q '^vendor.oplus.hardware.charger.ICharger/default ' "$contexts" || \
  printf '%s\n' 'vendor.oplus.hardware.charger.ICharger/default u:object_r:hal_power_service:s0' >> "$contexts"

for rel in etc/k90/charge-scheduler.conf etc/selinux/product_service_contexts; do
  cp --attributes-only --preserve=all "$overlay/product_lower/$rel" "$overlay/product_upper/$rel" 2>/dev/null || true
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$overlay/product_upper/$rel"
done
chown 0:0 "$overlay/product_upper/etc/k90/charge-scheduler.conf"
chmod 0644 "$overlay/product_upper/etc/k90/charge-scheduler.conf"
chown 0:2000 "$overlay/product_upper/bin"; chmod 0751 "$overlay/product_upper/bin"

uuid=$(blkid -o value -s UUID "$work/out/product.base.img")
label=$(blkid -o value -s LABEL "$work/out/product.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/out/product.raw.img" "$overlay/product_merged" > "$work/out/mkfs-product.log" 2>&1
test "$(stat -c%s "$work/out/product.raw.img")" -le "$product_size"
cp --sparse=always "$work/out/product.raw.img" "$work/out/product.img"; truncate -s "$product_size" "$work/out/product.img"
umount "$overlay/product_merged"; umount "$overlay/product_lower"

mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/odm_lower"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$overlay/odm_lower" 2>/dev/null)" "$overlay/odm_upper"
mount -t overlay overlay -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" "$overlay/odm_merged"
install -d -m 0755 "$overlay/odm_merged/bin" "$overlay/odm_merged/etc/init"
install -m 0755 "$charge/bin/vendor.oplus.hardware.charger-V11-service" "$overlay/odm_merged/bin/vendor.oplus.hardware.charger-V11-service"
sed 's#/data/adb/k90max#/data/vendor/k90max#g' "$charge/script/charge_daemon.sh" > "$overlay/odm_merged/bin/k90-charge-daemon.sh"
chmod 0755 "$overlay/odm_merged/bin/k90-charge-daemon.sh"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm_merged/bin/vendor.oplus.hardware.charger-V11-service"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm_merged/bin/k90-charge-daemon.sh"
cat > "$overlay/odm_merged/etc/init/k90-native-charge.rc" <<'EOF'
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
    copy /product/etc/k90/charge-scheduler.conf /data/vendor/k90max/charge-scheduler.conf
    chown system system /data/vendor/k90max/charge-scheduler.conf
    chmod 0640 /data/vendor/k90max/charge-scheduler.conf

on property:sys.boot_completed=1
    start k90-oplus-charger
    start k90-charge-daemon
EOF
odm_fc="$overlay/odm_merged/etc/selinux/odm_file_contexts"
grep -q '/odm/bin/vendor.oplus.hardware.charger-V11-service' "$odm_fc" || \
  printf '%s\n' '/odm/bin/vendor.oplus.hardware.charger-V11-service u:object_r:vendor_touch_init_shell_exec:s0' >> "$odm_fc"
grep -q '/odm/bin/k90-charge-daemon.sh' "$odm_fc" || \
  printf '%s\n' '/odm/bin/k90-charge-daemon.sh u:object_r:vendor_touch_init_shell_exec:s0' >> "$odm_fc"
grep -q '/odm/etc/init/k90-native-charge.rc' "$odm_fc" || \
  printf '%s\n' '/odm/etc/init/k90-native-charge.rc u:object_r:vendor_configs_file:s0' >> "$odm_fc"
odm_sc="$overlay/odm_merged/etc/selinux/odm_service_contexts"
grep -q '^vendor.oplus.hardware.charger.ICharger/default ' "$odm_sc" || \
  printf '%s\n' 'vendor.oplus.hardware.charger.ICharger/default u:object_r:hal_power_service:s0' >> "$odm_sc"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm_merged/etc/init/k90-native-charge.rc"
# Overlayfs may expose xattrs from the lower layer on the merged path. Write
# the executable/config labels to the actual upper files as well, so mkfs.erofs
# preserves the runtime entrypoint labels instead of falling back to vendor_file.
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm_upper/bin/vendor.oplus.hardware.charger-V11-service"
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$overlay/odm_upper/bin/k90-charge-daemon.sh"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm_upper/etc/init/k90-native-charge.rc"
"$src/stage50_policy_patch" "$overlay/odm_lower/etc/selinux/precompiled_sepolicy" "$overlay/odm_merged/etc/selinux/precompiled_sepolicy" > "$work/out/policy-patch.txt"
cat >> "$overlay/odm_merged/etc/selinux/odm_sepolicy.cil" <<'EOF'
; Stage50 exact runtime denials and charger bridge registration.
(allow vendor_touch_init_shell sysfs_batteryinfo (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_batteryinfo (file (getattr open read)))
(allow vendor_touch_init_shell hal_power_service (service_manager (add find)))
(allow vendor_touch_init_shell system_server (binder (call transfer)))
(allow system_server vendor_touch_init_shell (binder (call transfer)))
EOF
for rel in etc/selinux/precompiled_sepolicy etc/selinux/odm_sepolicy.cil; do
  cp --attributes-only --preserve=all "$overlay/odm_lower/$rel" "$overlay/odm_upper/$rel"
done
uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$uuid" --preserve-mtime)
[[ -z "$label" ]] || args+=(-L "$label")
python3 "$src/generate_erofs_file_contexts.py" \
  "$overlay/odm_merged" /odm "$work/out/odm_file_contexts.generated" \
  --override /odm/bin/vendor.oplus.hardware.charger-V11-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/bin/k90-charge-daemon.sh=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/etc/init/k90-native-charge.rc=u:object_r:vendor_configs_file:s0 \
  > "$work/out/odm-file-contexts-generation.txt"
args+=(--mount-point=/odm --file-contexts="$work/out/odm_file_contexts.generated")
mkfs.erofs "${args[@]}" "$work/out/odm.raw.img" "$overlay/odm_merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"; truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/odm_merged"; umount "$overlay/odm_lower"

for part in product odm; do
  fsck.erofs "$work/out/$part.img" > "$work/out/fsck-$part.txt" 2>&1
done
mount -t erofs -o ro,loop "$work/out/product.img" "$overlay/verify"
grep -q '^vendor.oplus.hardware.charger.ICharger/default u:object_r:hal_power_service:s0$' "$overlay/verify/etc/selinux/product_service_contexts"
umount "$overlay/verify"
mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
grep -q '/data/vendor/k90max' "$overlay/verify/bin/k90-charge-daemon.sh"
! grep -q 'thermal_remove' "$overlay/verify/bin/k90-charge-daemon.sh"
grep -q '^service k90-oplus-charger ' "$overlay/verify/etc/init/k90-native-charge.rc"
test "$(stat -c %u:%g:%a "$overlay/verify/bin/vendor.oplus.hardware.charger-V11-service")" = 0:0:755
test "$(stat -c %u:%g:%a "$overlay/verify/bin/k90-charge-daemon.sh")" = 0:0:755
test "$(stat -c %u:%g:%a "$overlay/verify/etc/init/k90-native-charge.rc")" = 0:0:644
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/vendor.oplus.hardware.charger-V11-service" 2>/dev/null)" = u:object_r:vendor_touch_init_shell_exec:s0
test "$(getfattr -n security.selinux --only-values "$overlay/verify/bin/k90-charge-daemon.sh" 2>/dev/null)" = u:object_r:vendor_touch_init_shell_exec:s0
grep -q '/odm/bin/vendor.oplus.hardware.charger-V11-service u:object_r:vendor_touch_init_shell_exec:s0' "$overlay/verify/etc/selinux/odm_file_contexts"
grep -q '/odm/bin/k90-charge-daemon.sh u:object_r:vendor_touch_init_shell_exec:s0' "$overlay/verify/etc/selinux/odm_file_contexts"
grep -q '^vendor.oplus.hardware.charger.ICharger/default u:object_r:hal_power_service:s0$' "$overlay/verify/etc/selinux/odm_service_contexts"
umount "$overlay/verify"
mount -t erofs -o ro,loop "$work/out/product.img" "$overlay/verify"
test "$(stat -c %u:%g:%a "$overlay/verify/etc/k90/charge-scheduler.conf")" = 0:0:644
for rel in etc/k90/charge-scheduler.conf etc/selinux/product_service_contexts; do
  test "$(getfattr -n security.selinux --only-values "$overlay/verify/$rel" 2>/dev/null)" = u:object_r:system_file:s0
done
umount "$overlay/verify"
mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
grep -q 'sysfs_batteryinfo' "$overlay/verify/etc/selinux/odm_sepolicy.cil"
test "$(getfattr -n security.selinux --only-values "$overlay/verify/etc/selinux/precompiled_sepolicy" 2>/dev/null)" = u:object_r:sepolicy_file:s0
umount "$overlay/verify"
grep -q '^POLICY_READBACK_OK ' "$work/out/policy-patch.txt"

mkdir -p "$delivery/images"
rm -f "$delivery/images/super.img.building"
cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
dd if="$work/out/product.img" of="$delivery/images/super.img.building" bs=16M seek="$product_offset" oflag=seek_bytes conv=notrunc status=progress
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=16M seek="$odm_offset" oflag=seek_bytes conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$delivery/images/super.img"

dd if="$delivery/images/super.img" of="$work/out/product.readback.img" bs=16M skip="$product_offset" count="$product_size" iflag=skip_bytes,count_bytes status=none
dd if="$delivery/images/super.img" of="$work/out/odm.readback.img" bs=16M skip="$odm_offset" count="$odm_size" iflag=skip_bytes,count_bytes status=none
cmp "$work/out/product.img" "$work/out/product.readback.img"
cmp "$work/out/odm.img" "$work/out/odm.readback.img"
product_end=$((product_offset + product_size))
odm_end=$((odm_offset + odm_size))
cmp -n "$product_offset" "$base/images/super.img" "$delivery/images/super.img"
cmp -n $((odm_offset - product_end)) -i "$product_end:$product_end" "$base/images/super.img" "$delivery/images/super.img"
cmp -i "$odm_end:$odm_end" "$base/images/super.img" "$delivery/images/super.img"

cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"
cp "$work/out/"fsck-*.txt "$work/out/"mkfs-*.log "$work/out/"avb-*.txt "$work/out/policy-patch.txt" "$delivery/audit/"
sha256sum "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"
sha256sum "$work/out/product.img" "$work/out/odm.img" > "$delivery/audit/partition-sha256.txt"
cat > "$delivery/STATUS.txt" <<'EOF'
Stage50 charging/fan policy candidate
Base: Stage49 known bootable
Changed partitions: product, odm
Data wipe: no
Runtime validation: pending; do not publish before device boot and charging tests
Charging safety: Xiaomi MiCharge/PD/JEITA remain authoritative; no thermal voter bypass
EOF
echo STAGE50_OFFLINE_BUILD_PASSED
