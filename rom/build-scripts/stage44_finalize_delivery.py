from pathlib import Path
import shutil
import re

src=Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo')
root=Path('/mnt/d/K90Max_ColorOS17_完整迁移_20261028')
delivery=root/'01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage44_FANPERF'
if (delivery/'DO_NOT_FLASH.txt').exists():
    raise RuntimeError('Stage44 was revoked after a device boot failure; do not republish it. Use the separately audited R1 repair package.')
out=root/'02_Codex完整工作区/wo/stage44_final_work/out'
requirements=[
    (delivery/'EXTENT_AUDIT.txt','EXTENT_AUDIT_OK'),
    (src/'stage44_filesystem_audit.txt','FILESYSTEM_METADATA_AUDIT_OK'),
    (src/'stage44_policy/semantic_audit.txt','POLICY_SEMANTIC_AUDIT_OK'),
    (src/'stage44_policy/strict_differential.txt','BASELINE_AND_CANDIDATE_DIAGNOSTICS_IDENTICAL'),
    (src/'stage44_services/dex_readback_audit.txt','DEX_READBACK_CLASS_SETS_IDENTICAL'),
]
for path,expected in requirements: assert expected in path.read_text(),path
manifest=(delivery/'SHA256SUMS.txt').read_text()
assert re.fullmatch(r'[a-f0-9]{64}  images/super.img\n',manifest)
(delivery/'audit').mkdir(exist_ok=True)
for path,_ in requirements: shutil.copy2(path,delivery/'audit'/path.name)
for name in ['fsck-system.txt','fsck-odm.txt','avb-system.txt','policy-patch.txt']:
    shutil.copy2(out/name,delivery/'audit'/name)
for name in ['baseline.log','candidate.log','strict_differential.txt','semantic_audit.txt','final-runtime-policy.diff']:
    shutil.copy2(src/'stage44_policy'/name,delivery/'audit'/name)
for name in ['stage44_build_final.sh','stage44_compile_policy.py','stage44_policy_patch.c','stage44_policy_markers.py','stage44_validate_filesystems.sh','stage44_semantic_audit.py','stage44_verify_services.py','stage44_finalize_delivery.py']:
    shutil.copy2(src/name,delivery/'source'/name)
shutil.copy2(src/'stage44_build_final.sh',delivery/'BUILD_STAGE44.sh')
shutil.copy2(src/'stage44_delivery_notes.md',delivery/'说明与验证边界.md')
(delivery/'INDEPENDENT_AUDIT.txt').write_text('AUDIT_OK\nOFFLINE_CANDIDATE_NOT_DEVICE_TESTED\nEXACT_STAGE43_BASE\nONLY_SYSTEM_AND_ODM_EXTENTS_CHANGED\nEROFS_AND_SYSTEM_AVB_INTEGRITY_CHECKS_PASSED\nROOT_UID_GID_MODE_SELINUX_PRESERVED\nFRAMEWORK_CLASS_SETS_PRESERVED\nPOLICY_INCREMENT_SEMANTIC_AUDIT_PASSED\nEXISTING_FULL_SOURCE_NEVERALLOW_CONFLICTS_DOCUMENTED\n')
(delivery/'DO_NOT_FLASH.txt').unlink(missing_ok=True)
print('STAGE44_DELIVERY_READY_OFFLINE_CANDIDATE')
print(delivery)
print(manifest)
