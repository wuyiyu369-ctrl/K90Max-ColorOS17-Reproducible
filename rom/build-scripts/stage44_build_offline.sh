#!/usr/bin/env bash
set -euo pipefail

base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR/images/super.img
base_delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
work=/root/k90_stage44_fanperf
delivery=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_FANPERF
avbtool=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

super_size=13421772800
odm_size=1724530688
odm_seek=2615552
odm_count=421028
base_sha=6afd22e81b29e985e251190d995109b819bdee77d9ef0f1d8d9eecba3ecbcb4c

for t in mkfs.erofs fsck.erofs getfattr setfattr; do command -v "$t" >/dev/null || exit 2; done
test -s "$base"; test "$(stat -c%s "$base")" -eq "$super_size"
test "$(sha256sum "$base" | awk '{print $1}')" = "$base_sha"
test ! -e "$work"; test ! -e "$delivery"
mkdir -p "$work"/{out,lower,upper,work,merged,verify}
mkdir -p "$delivery/images"
cleanup(){ for d in "$work/verify" "$work/merged" "$work/lower"; do mountpoint -q "$d" && umount "$d" || true; done; }
trap cleanup EXIT

dd if="$base" of="$work/out/odm.base.img" bs=4096 skip="$odm_seek" count="$odm_count" status=progress
test "$(stat -c%s "$work/out/odm.base.img")" -eq "$odm_size"
fsck.erofs "$work/out/odm.base.img" > "$work/out/fsck-odm-base.log" 2>&1

mount -t erofs -o ro,loop "$work/out/odm.base.img" "$work/lower"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$work/upper"
mount -t overlay overlay -o "lowerdir=$work/lower,upperdir=$work/upper,workdir=$work/work" "$work/merged"
install -m 0755 "$src/stage44_fan_daemon.sh" "$work/merged/bin/k90_fan_daemon.sh"
mkdir -p "$work/upper/etc/init"
cat > "$work/upper/etc/init/k90-stage44-fan.rc" <<'EOF'
# Stage44: run fan control in the vendor shell domain, not system_server.
service k90-stage44-fan /system/vendor/bin/sh /odm/bin/k90_fan_daemon.sh
    class late_start
    user system
    group system readproc
    seclabel u:r:vendor_touch_init_shell:s0

on post-fs-data
    mkdir /data/vendor/k90max 0770 system system
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chown system system /sys/devices/platform/odm/odm:xiaomi_fan/target_level
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/pwm_duty
    chmod 0660 /sys/devices/platform/odm/odm:xiaomi_fan/target_level
EOF
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 "$work/upper/bin/k90_fan_daemon.sh"
setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 "$work/upper/etc/init/k90-stage44-fan.rc"

policy="$work/merged/etc/selinux/odm_sepolicy.cil"
grep -q 'vendor_touch_init_shell vendor_sysfs_xm_power' "$policy" || cat >> "$policy" <<'EOF'

(allow vendor_touch_init_shell vendor_sysfs_xm_power (dir (getattr open read search)))
(allow vendor_touch_init_shell vendor_sysfs_xm_power (file (getattr open read write append)))
EOF
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 "$policy"

odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime)
[[ -n "$odm_label" ]] && args+=(-L "$odm_label")
mkfs.erofs "${args[@]}" "$work/out/odm.raw.img" "$work/merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.log" 2>&1
umount "$work/merged"; umount "$work/lower"

mount -t erofs -o ro,loop "$work/out/odm.img" "$work/verify"
cmp -s "$src/stage44_fan_daemon.sh" "$work/verify/bin/k90_fan_daemon.sh"
grep -q 'vendor_touch_init_shell vendor_sysfs_xm_power' "$work/verify/etc/selinux/odm_sepolicy.cil"
test "$(getfattr -n security.selinux --only-values "$work/verify/bin/k90_fan_daemon.sh" 2>/dev/null)" = u:object_r:vendor_touch_init_shell_exec:s0
umount "$work/verify"

cp --sparse=always "$base" "$delivery/images/super.img"
dd if="$work/out/odm.img" of="$delivery/images/super.img" bs=4096 seek="$odm_seek" count="$odm_count" conv=notrunc,fsync status=progress
test "$(stat -c%s "$delivery/images/super.img")" -eq "$super_size"
test "$(dd if="$delivery/images/super.img" bs=4096 skip="$odm_seek" count="$odm_count" status=none | sha256sum | awk '{print $1}')" = "$(sha256sum "$work/out/odm.img" | awk '{print $1}')"

cp "$base_delivery/FLASH_KEEP_DATA.ps1" "$delivery/"
cp "$base_delivery/START_UPDATE.cmd" "$delivery/" 2>/dev/null || true
cp -a "$base_delivery/platform-tools" "$delivery/"
sha256sum "$work/out/odm.img" "$delivery/images/super.img" > "$delivery/SHA256SUMS.txt"
cat > "$delivery/STATUS.txt" <<EOF
OFFLINE_CHECKS_PASSED
BASE_STAGE43_SHA256=$base_sha
ONLY_ODM_EXTENT_CHANGED_FROM_STAGE43
SYSTEM_EXTENT_UNCHANGED_FROM_STAGE43
NO_USERDATA_METADATA_MODEM_PERSIST_CHANGES
DEVICE_BOOT_AND_FAN_TEST_NOT_YET_RUN
EOF
cat > "$delivery/CHANGES_STAGE44.txt" <<'EOF'
Stage44 candidate:
- Keeps the Stage43 system extent byte-identical, including its boot-repair services.jar.
- Adds a vendor-domain fan daemon with temperature/game/charging policy.
- Moves fan sysfs writes out of system_server; daemon hands back duty=0 on exit.
- Keeps Xiaomi thermal safety; does not write CPU/GPU/DDR/UFS frequency nodes.
- Does not claim real UniPerf/MiPower CPU/GPU/DDR/UFS boost until native Binder
  arguments are verified on-device.
EOF
cp "$src/stage44_build_offline.sh" "$delivery/BUILD_STAGE44.sh"
echo "STAGE44_BUILD_DONE=$delivery"
