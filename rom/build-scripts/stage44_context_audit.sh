#!/usr/bin/env bash
set -euo pipefail
src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
base=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR/images/super.img
mountroot=/root/k90_stage44_boot_context_audit
mkdir -p "$mountroot"/{system,system_ext,product,vendor,odm}
cleanup(){ for part in system system_ext product vendor odm; do mountpoint -q "$mountroot/$part" && umount "$mountroot/$part" || true; done; }
trap cleanup EXIT
mount -t erofs -o ro,loop,offset=1048576,sizelimit=1061134336 "$base" "$mountroot/system"
mount -t erofs -o ro,loop,offset=1062207488,sizelimit=1087639552 "$base" "$mountroot/system_ext"
mount -t erofs -o ro,loop,offset=2150629376,sizelimit=152326144 "$base" "$mountroot/product"
mount -t erofs -o ro,loop,offset=8194621440,sizelimit=2517786624 "$base" "$mountroot/vendor"
mount -t erofs -o ro,loop,offset=10713300992,sizelimit=1724530688 "$base" "$mountroot/odm"
python3 - <<'PY'
from pathlib import Path
import re,hashlib
src=Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo')
root=Path('/root/k90_stage44_boot_context_audit')
types=set(re.findall(r'^\(type ([^ )]+)\)',(src/'stage44_policy/stage43-baseline.bin.cil').read_text(),re.M))
rows=[]
for p in root.rglob('*contexts'):
 if not p.is_file(): continue
 for line in p.read_text(errors='replace').splitlines():
  if line.lstrip().startswith('#'): continue
  for typ in re.findall(r'u:(?:object_r|r):([^:\s]+):s0',line):
   if typ not in types: rows.append(f'{p.relative_to(root)}: {line}')
out='MISSING_TYPE_CONTEXT_LINES='+str(len(rows))+'\n'+'\n'.join(rows)+'\n'
(src/'stage44_bootloop_diagnosis/missing_contexts.txt').write_text(out)
print(out[:9000])
print('BASELINE_PRECOMPILED_HASH_MARKER_MATCH:')
for name,inside,marker in [('system','system/etc/selinux','plat'),('system_ext','etc/selinux','system_ext'),('product','etc/selinux','product')]:
 a=root/name/inside/f'{marker}_sepolicy_and_mapping.sha256'
 b=root/'odm/etc/selinux'/f'precompiled_sepolicy.{marker}_sepolicy_and_mapping.sha256'
 print(name, 'MATCH' if a.exists() and b.exists() and a.read_bytes()==b.read_bytes() else 'MISMATCH_OR_ABSENT')
PY
