#!/usr/bin/env bash
set -euo pipefail
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
work=$root/02_Codex完整工作区/wo/stage44_final_work/out
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
mounts=/root/k90_stage44_metadata_audit
mkdir -p "$mounts"/{old_system,new_system,old_odm,new_odm}
cleanup(){ for n in old_system new_system old_odm new_odm; do mountpoint -q "$mounts/$n" && umount "$mounts/$n" || true; done; }
trap cleanup EXIT
mount -t erofs -o ro,loop "$root/02_Codex完整工作区/wo/stage43_services_repair_work/out/system.img" "$mounts/old_system"
mount -t erofs -o ro,loop "$work/system.img" "$mounts/new_system"
mount -t erofs -o ro,loop "$work/draft-odm.base.img" "$mounts/old_odm"
mount -t erofs -o ro,loop "$work/odm.img" "$mounts/new_odm"
for n in system odm; do
  test "$(stat -c %u:%g:%a "$mounts/old_$n")" = "$(stat -c %u:%g:%a "$mounts/new_$n")"
  test "$(getfattr -n security.selinux --only-values "$mounts/old_$n" 2>/dev/null)" = "$(getfattr -n security.selinux --only-values "$mounts/new_$n" 2>/dev/null)"
done
cmp -s "$src/stage44_native_bridge" "$mounts/new_odm/bin/k90_native_bridge"
cmp -s "$src/stage44_payload/k90-stage44-native.rc" "$mounts/new_odm/etc/init/k90-stage44-native.rc"
cmp -s "$src/stage44_services/services.stage44.jar" "$mounts/new_system/system/framework/services.jar"
test "$(stat -c %a "$mounts/new_odm/bin/k90_native_bridge")" = 755
# Existing Stage43 bridge, profiles, settings integration and camera payloads
# must remain. No superseded draft shell fan daemon is installed.
cmp -s "$mounts/old_odm/etc/init/k90-native-services.rc" "$mounts/new_odm/etc/init/k90-native-services.rc"
cmp -s "$mounts/old_odm/etc/performance/game_profiles" "$mounts/new_odm/etc/performance/game_profiles"
test ! -e "$mounts/new_odm/etc/init/k90-stage44-fan.rc"
test ! -e "$mounts/new_odm/bin/k90_fan_daemon.sh"
echo 'FILESYSTEM_METADATA_AUDIT_OK'
echo 'ROOT_OWNER_MODE_AND_SELINUX_MATCH_STAGE43'
echo 'NATIVE_BINARY_RC_JAR_READBACK_MATCH'
echo 'STAGE43_EXISTING_PERFORMANCE_FILES_PRESERVED'
