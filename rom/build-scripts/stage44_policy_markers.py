"""Read exact Stage43 split-policy bytes and hash markers from EROFS mounts."""
from pathlib import Path
import subprocess
import sys

base = sys.argv[1]
dest = Path(sys.argv[2])
captured = Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/policy_inputs_device_exact')
parts = [('system',256,259066,'system/etc/selinux'),
         ('system_ext',259328,265537,'etc/selinux'),
         ('product',525056,37189,'etc/selinux'),
         ('vendor',2000640,614694,'etc/selinux')]
mounts = []
try:
    for name, start, count, inside in parts:
        mount = Path('/root/k90_stage44_policy_verify') / name
        mount.mkdir(parents=True,exist_ok=True)
        subprocess.run(['mount','-t','erofs','-o',f'ro,loop,offset={start*4096},sizelimit={count*4096}',base,str(mount)],check=True)
        mounts.append(mount)
        policy_dir = mount / inside
        if name == 'vendor':
            audited = Path('/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/work_patched/vendor_a_rw/lib64/libuniperf_client_vendor.so')
            assert (mount/'lib64/libuniperf_client_vendor.so').read_bytes() == audited.read_bytes(), 'Uniperf ABI audit used a different vendor library'
        for f in policy_dir.glob('*.cil'):
            old = captured / f'{name}_etc_selinux_{f.name}'
            if old.exists():
                assert old.read_bytes() == f.read_bytes(), f'POLICY_INPUT_MISMATCH: {f}'
        for mapping in ['202504.cil','202504.compat.cil']:
            f = policy_dir / 'mapping' / mapping
            old = captured / f'{name}_etc_selinux_mapping_{mapping}'
            if old.exists(): assert f.read_bytes() == old.read_bytes(), f'MAPPING_MISMATCH: {f}'
        marker_name = {'system':'plat','system_ext':'system_ext','product':'product'}.get(name)
        if marker_name:
            f = policy_dir / f'{marker_name}_sepolicy_and_mapping.sha256'
            if f.exists():
                data = f.read_bytes()
                assert len(data.strip()) == 64
                (dest / f'precompiled_sepolicy.{marker_name}_sepolicy_and_mapping.sha256').write_bytes(data)
        print('verified Stage43 policy partition:',name,flush=True)
finally:
    for mount in reversed(mounts): subprocess.run(['umount',str(mount)],check=True)
