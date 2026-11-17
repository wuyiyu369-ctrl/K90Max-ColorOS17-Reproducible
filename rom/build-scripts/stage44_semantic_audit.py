from pathlib import Path
import re
import subprocess
import difflib

root=Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo')
pol=root/'stage44_policy'
def dump(name):
    s=subprocess.check_output([str(root/'stage44_policy_dump'),str(pol/name)],text=True)
    (pol/(name+'.cil')).write_text(s)
    return s
old=dump('stage43-baseline.bin'); new=dump('candidate.bin')
allowed={
    ('vendor_touch_init_shell','vendor_sysfs_xm_power','dir'),
    ('vendor_touch_init_shell','vendor_sysfs_xm_power','file'),
    ('vendor_touch_init_shell','sysfs_therm','dir'),
    ('vendor_touch_init_shell','sysfs_therm','file'),
    ('vendor_touch_init_shell','sysfs_battery_supply','dir'),
    ('vendor_touch_init_shell','sysfs_battery_supply','file'),
    ('vendor_touch_init_shell','system_data_file','dir'),
    ('vendor_touch_init_shell','system_data_file','file'),
    ('vendor_touch_init_shell','hal_uniperf_service','service_manager'),
    ('vendor_touch_init_shell','servicemanager','binder'),
    ('vendor_touch_init_shell','hal_uniperf_default','binder'),
    ('hal_uniperf_default','vendor_touch_init_shell','binder'),
    ('vendor_init','proc_powerhal_cpu_ctrl','file'),
    ('mtk_hal_power','proc_powerhal_cpu_ctrl','dir'),
    ('mtk_hal_power','proc_powerhal_cpu_ctrl','file'),
    ('system_server','sysfs_therm','file'),
    ('vendor_touch_init_shell','vendor_data_file','dir'),
    ('vendor_touch_init_shell','vendor_data_file','file'),
}
removed=set(old.splitlines())-set(new.splitlines())
added=set(new.splitlines())-set(old.splitlines())
for line in removed|added:
    if line.startswith('(typeattributeset hal_uniperf_client '): continue
    m=re.match(r'\(allow (\S+) (\S+) \((\S+) ',line)
    assert m and m.groups() in allowed, f'Unexpected policy change: {line}'
# No permissions disappear for an existing rule; no classes/types/permissive
# entries, constraints, transitions or other declarations may change.
def av(lines):
    result={}
    for line in lines:
        m=re.fullmatch(r'\(allow (\S+) (\S+) \((\S+) \(([^)]+)\)\)\)',line)
        if m: result[m.group(1,2,3)]=set(m.group(4).split())
    return result
oa,na=av(old.splitlines()),av(new.splitlines())
for key,value in oa.items(): assert value <= na.get(key,set()), f'Permissions lost: {key}'
(pol/'final-runtime-policy.diff').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='Stage43',tofile='Stage44')))
(pol/'semantic_audit.txt').write_text(f'POLICY_SEMANTIC_AUDIT_OK\nREMOVED_LINES={len(removed)}\nADDED_LINES={len(added)}\nONLY_ENUMERATED_ALLOW_RULES_AND_UNIPERF_CLIENT_MEMBERSHIP_CHANGED\nNO_PERMISSIVE_OR_CONSTRAINT_OR_TRANSITION_CHANGES\n')
print((pol/'semantic_audit.txt').read_text())
