#!/usr/bin/env bash
set -euo pipefail
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
deliveries=$root/01_主工程/K90_A17_PORT_WORK/delivery
old=$deliveries/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_FANPERF
base=$deliveries/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR
new=$deliveries/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_R1_FANPERF_BOOTFIX
work=$root/02_Codex完整工作区/wo/stage44_r1_work
mountroot=/root/k90_stage44_r1
cache=$root/02_Codex完整工作区/wo/stage44_final_work/out
mkdir -p "$mountroot"/{old,baseline,upper,work,merged,verify} "$work/out" "$new/images" "$new/audit"
cleanup(){ for n in verify merged old baseline; do mountpoint -q "$mountroot/$n" && umount "$mountroot/$n" || true; done; }
trap cleanup EXIT
mount -t erofs -o ro,loop "$cache/odm.img" "$mountroot/old"
mount -t erofs -o ro,loop "$cache/draft-odm.base.img" "$mountroot/baseline"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$mountroot/upper"
mount -t overlay overlay -o "lowerdir=$mountroot/old,upperdir=$mountroot/upper,workdir=$mountroot/work" "$mountroot/merged"
# Restore the exact known-booted selection, not a different policy binary.
# Keep new narrow CIL rules: Android init assembles the complete matching split
# sources on the same path used by Stage43. Never force the stale precompiled
# policy to be selected by relabeling its hash markers.
for name in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 precompiled_sepolicy.product_sepolicy_and_mapping.sha256; do
  if [[ -f "$mountroot/baseline/etc/selinux/$name" ]]; then
    cp --preserve=all "$mountroot/baseline/etc/selinux/$name" "$mountroot/merged/etc/selinux/$name"
  else
    [[ ! -e "$mountroot/merged/etc/selinux/$name" ]] || rm -- "$mountroot/merged/etc/selinux/$name"
  fi
done
cmp -s "$src/stage44_policy/candidate.cil" "$mountroot/merged/etc/selinux/odm_sepolicy.cil"
for name in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256; do
 cmp -s "$mountroot/baseline/etc/selinux/$name" "$mountroot/merged/etc/selinux/$name"
done
# All context types absent from the stale binary must exist in complete
# split source declarations. This is an additional source-coverage check;
# it does not replace compile/boot tests.
python3 - "$src" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]); inp=s/'policy_inputs_device_exact'
alltext='\n'.join(p.read_text() for p in inp.glob('*.cil'))
types=set(re.findall(r'\(type\s+([^\s)]+)',alltext))
required=set(re.findall(r'u:(?:object_r|r):([^:\s]+):s0',(s/'stage44_bootloop_diagnosis/missing_contexts.txt').read_text()))
missing=required-types
# Optional Qualcomm context from the original Xiaomi vendor has no consumer
# on MTK; retain baseline unchanged and report it rather than hiding it.
report=f'COMPLETE_SOURCE_TYPES={len(types)}\nCHECKED_PREVIOUSLY_MISSING_CONTEXT_TYPES={len(required)}\nMISSING_FROM_FULL_SOURCE={sorted(missing)}\n'
(s/'stage44_bootloop_diagnosis/r1_context_source_coverage.txt').write_text(report)
print(report,flush=True)
assert missing <= {'vendor_hal_vnddisplayconfig_service'}
PY
args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$(blkid -o value -s UUID "$cache/draft-odm.base.img")" --preserve-mtime)
label=$(blkid -o value -s LABEL "$cache/draft-odm.base.img" || true)
[[ -z "$label" ]] || args+=(-L "$label")
mkfs.erofs "${args[@]}" "$work/out/odm.raw.img" "$mountroot/merged" > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le 1724530688
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s 1724530688 "$work/out/odm.img"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/odm.img" "$mountroot/verify"
for name in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256; do
 cmp -s "$mountroot/baseline/etc/selinux/$name" "$mountroot/verify/etc/selinux/$name"
 test "$(getfattr -n security.selinux --only-values "$mountroot/baseline/etc/selinux/$name" 2>/dev/null)" = "$(getfattr -n security.selinux --only-values "$mountroot/verify/etc/selinux/$name" 2>/dev/null)"
done
cmp -s "$src/stage44_policy/candidate.cil" "$mountroot/verify/etc/selinux/odm_sepolicy.cil"
cmp -s "$src/stage44_native_bridge" "$mountroot/verify/bin/k90_native_bridge"
cmp -s "$src/stage44_payload/k90-stage44-native.rc" "$mountroot/verify/etc/init/k90-stage44-native.rc"
test "$(stat -c %u:%g:%a "$mountroot/verify")" = "$(stat -c %u:%g:%a "$mountroot/baseline")"
test "$(getfattr -n security.selinux --only-values "$mountroot/verify" 2>/dev/null)" = u:object_r:vendor_file:s0
umount "$mountroot/verify"
cp --sparse=always "$old/images/super.img" "$new/images/super.img.building"
dd if="$work/out/odm.img" of="$new/images/super.img.building" bs=1M seek=10217 conv=notrunc,fsync status=progress
mv "$new/images/super.img.building" "$new/images/super.img"
cp -a "$old/platform-tools" "$new/"
cp "$old/FLASH_KEEP_DATA.ps1" "$old/START_UPDATE.cmd" "$new/"
python3 "$src/stage44_r1_verify.py" "$old/images/super.img" "$new/images/super.img" "$work/out/odm.img" "$new"
cp "$work/out/fsck-odm.txt" "$new/audit/"
cp "$src/stage44_bootloop_diagnosis/r1_context_source_coverage.txt" "$new/audit/"
echo "R1_BUILD_AND_READBACK_PASSED=$new"
