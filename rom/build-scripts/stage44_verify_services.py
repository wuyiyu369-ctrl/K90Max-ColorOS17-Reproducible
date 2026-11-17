from pathlib import Path
import subprocess
import zipfile

root=Path('/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo')
tools=Path('/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/smali3')
cp=':'.join(map(str,tools.glob('*.jar')))
work=root/'stage44_services'
def classes(p):
    return set(subprocess.check_output(['java','-cp',cp,'com.android.tools.smali.baksmali.Main','list','classes',str(p)],text=True).splitlines())
before=classes(work/'classes4.base.dex'); after=classes(work/'classes4.dex')
assert before==after
assert len(after)==6867
with zipfile.ZipFile(root/'device_policy_20261106/jar_repair/services_stage43_fixed.jar') as old, zipfile.ZipFile(work/'services.stage44.jar') as new:
    assert old.namelist()==new.namelist()
    assert new.testzip() is None
    for name in old.namelist():
        if name!='classes4.dex': assert old.read(name)==new.read(name),name
(work/'dex_readback_audit.txt').write_text('DEX_READBACK_CLASS_SETS_IDENTICAL\nCLASSES4_CLASS_COUNT=6867\nJAR_MEMBERS_AND_OTHER_DEX_BYTES_IDENTICAL\n')
print((work/'dex_readback_audit.txt').read_text())
