"""Compile only the captured Stage43-compatible split policy, with neverallow on."""
from pathlib import Path
import subprocess
import sys

src = Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/policy_inputs_device_exact')
out = Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/stage44_policy')
out.mkdir(exist_ok=True)
names = [
    'system_etc_selinux_plat_sepolicy.cil',
    'system_etc_selinux_mapping_202504.cil',
    'system_etc_selinux_mapping_202504.compat.cil',
    'system_etc_selinux_plat_sepolicy_genfs_202504.cil',
    'system_ext_etc_selinux_system_ext_sepolicy.cil',
    'system_ext_etc_selinux_mapping_202504.cil',
    'system_ext_etc_selinux_mapping_202504.compat.cil',
    'vendor_etc_selinux_plat_pub_versioned.cil',
    'vendor_etc_selinux_vendor_sepolicy.cil',
]
odm = (src / 'odm_etc_selinux_odm_sepolicy.cil').read_text()
extra = '''
; Stage44: native UniPerf client; same service and transport as Xiaomi client.
(typeattributeset hal_uniperf_client (vendor_touch_init_shell))
(typeattributeset halclientdomain (vendor_touch_init_shell))
(allow vendor_touch_init_shell hal_uniperf_service (service_manager (find)))
(allow vendor_touch_init_shell servicemanager_202504 (binder (call transfer)))
(allow vendor_touch_init_shell hal_uniperf_default (binder (call transfer)))
(allow hal_uniperf_default vendor_touch_init_shell (binder (transfer)))
(allow vendor_init_202504 proc_powerhal_cpu_ctrl (file (getattr setattr)))
(allow vendor_touch_init_shell sysfs_battery_supply (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_battery_supply (file (getattr open read)))
(allow vendor_touch_init_shell sysfs_batteryinfo (dir (getattr search open read)))
(allow vendor_touch_init_shell sysfs_batteryinfo (file (getattr open read)))
'''
results = []
for kind, text in [('baseline', odm), ('candidate', odm + extra)]:
    cil = out / (kind + '.cil')
    cil.write_text(text)
    compiler = src.parent / 'stage44_toolchain_source/selinux-main/secilc/secilc'
    result = subprocess.run([str(compiler), '-m', '-M', 'true', '-G', '-c', '33',
                             *[str(src / n) for n in names], str(cil),
                             '-o', str(out / (kind + '.bin')), '-f', '/dev/null'],
                            capture_output=True, text=True)
    (out / (kind + '.log')).write_text(result.stdout + result.stderr)
    print(kind, 'exit=', result.returncode, flush=True)
    results.append(result)
    if result.returncode: print(result.stderr[:1000], flush=True)
# Existing mixed-vendor ROM sources already contain neverallow conflicts.
# Never suppress them. Compare the strict diagnostics before proceeding with
# a separately audited incremental edit of the exact booted binary policy.
assert results[0].returncode == results[1].returncode
assert results[0].stderr.replace('baseline.cil','INPUT.cil') == results[1].stderr.replace('candidate.cil','INPUT.cil'), 'New policy conflict introduced'
(out/'strict_differential.txt').write_text('BASELINE_AND_CANDIDATE_DIAGNOSTICS_IDENTICAL\nFULL_SOURCE_STRICT_COMPILATION_FAILED_IN_BASELINE\nNO_NEVERALLOW_BYPASS_USED\n')
print((out/'strict_differential.txt').read_text())
