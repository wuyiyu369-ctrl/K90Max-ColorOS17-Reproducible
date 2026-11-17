"""Preserve all Stage43 dex members; rebuild only classes4 with one class edit."""
from pathlib import Path
import hashlib
import shutil
import subprocess
import zipfile

root = Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo')
jar = root / 'device_policy_20261106/jar_repair/services_stage43_fixed.jar'
work = root / 'stage44_services'
work.mkdir(exist_ok=True)
tools = Path('/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/smali3')
cp = ':'.join(map(str, tools.glob('*.jar')))
with zipfile.ZipFile(jar) as z:
    dex = z.read('classes4.dex')
(work / 'classes4.base.dex').write_bytes(dex)
subprocess.run(['java','-cp',cp,'com.android.tools.smali.baksmali.Main','d',
                '--api','34',str(work/'classes4.base.dex'),'-o',str(work/'smali')],check=True)
before = {str(p.relative_to(work/'smali')): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (work/'smali').rglob('*.smali')}
target = 'com/android/server/wm/K90ThermalBridge.smali'
assert target in before
shutil.copyfile(root/'stage44_payload/K90ThermalBridge.smali',work/'smali'/target)
after = {str(p.relative_to(work/'smali')): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in (work/'smali').rglob('*.smali')}
assert before.keys() == after.keys()
assert [p for p in before if before[p] != after[p]] == [target]
subprocess.run(['java','-cp',cp,'com.android.tools.smali.smali.Main','a',
                '--api','34',str(work/'smali'),'-o',str(work/'classes4.dex')],check=True)
with zipfile.ZipFile(jar) as old, zipfile.ZipFile(work/'services.stage44.jar','w',zipfile.ZIP_DEFLATED) as new:
    for info in old.infolist():
        new.writestr(info,(work/'classes4.dex').read_bytes() if info.filename == 'classes4.dex' else old.read(info.filename))
with zipfile.ZipFile(jar) as old, zipfile.ZipFile(work/'services.stage44.jar') as new:
    assert old.namelist() == new.namelist()
    assert new.testzip() is None
    for name in old.namelist():
        if name != 'classes4.dex': assert old.read(name) == new.read(name), name
(work/'source_audit.txt').write_text(f'ONLY_ONE_SMALI_CLASS_CHANGED\nORIGINAL_CLASS_COUNT={len(before)}\nUNCHANGED_OTHER_JAR_MEMBERS\n')
print((work/'source_audit.txt').read_text())
