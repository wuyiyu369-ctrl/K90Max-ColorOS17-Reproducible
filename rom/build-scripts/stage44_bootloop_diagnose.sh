#!/usr/bin/env bash
set -euo pipefail
cd /mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
mkdir -p stage44_bootloop_diagnosis
./stage44_policy_dump device_policy_20261106/live_policy.bin > stage44_bootloop_diagnosis/previous-live.cil
python3 - <<'PY'
from pathlib import Path
import re
base=Path('stage44_policy/stage43-baseline.bin.cil').read_text()
live=Path('stage44_bootloop_diagnosis/previous-live.cil').read_text()
types=lambda s:set(re.findall(r'^\(type ([^ )]+)\)',s,re.M))
b,l=types(base),types(live)
missing=sorted(l-b)
out=f'IMAGE_PRECOMPILED_TYPES={len(b)}\nPREVIOUS_LIVE_TYPES={len(l)}\nLIVE_TYPES_MISSING_FROM_IMAGE_PRECOMPILED={len(missing)}\n'+'\n'.join(missing)+'\n'
Path('stage44_bootloop_diagnosis/type_comparison.txt').write_text(out)
print(out[:6000])
for token in ['oplus_fingerprint_prop','init_dev_config','hal_uniperf_default','vendor_touch_init_shell']:
 print(token, 'image=',token in b,'previous_live=',token in l)
PY
