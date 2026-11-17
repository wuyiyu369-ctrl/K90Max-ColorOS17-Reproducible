"""Verify every super byte outside system/ODM and embedded replacement hashes."""
import hashlib
from pathlib import Path
import sys

base,new,out,delivery = map(Path,sys.argv[1:])
ranges=[(256*4096,259066*4096,'system'),(2615552*4096,421028*4096,'odm')]
assert base.stat().st_size == new.stat().st_size == 13421772800
def filehash(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        while b:=f.read(8*1024*1024): h.update(b)
    return h.hexdigest()
with base.open('rb') as left,new.open('rb') as right:
    pos=0
    for start,length,name in ranges:
        left.seek(pos); right.seek(pos)
        while pos<start:
            n=min(8*1024*1024,start-pos)
            assert left.read(n)==right.read(n),f'Unexpected difference at {pos}'
            pos+=n
        right.seek(start); h=hashlib.sha256(); remain=length
        while remain:
            b=right.read(min(8*1024*1024,remain)); assert b
            h.update(b); remain-=len(b)
        assert h.hexdigest()==filehash(out/f'{name}.img'),f'{name} extent mismatch'
        pos=start+length
    left.seek(pos);right.seek(pos)
    while pos<base.stat().st_size:
        n=min(8*1024*1024,base.stat().st_size-pos)
        assert left.read(n)==right.read(n),f'Unexpected suffix difference at {pos}'
        pos+=n
digest=filehash(new)
(delivery/'SHA256SUMS.txt').write_text(f'{digest}  images/super.img\n')
(delivery/'STATUS.txt').write_text('OFFLINE_CANDIDATE_ONLY\nDEVICE_BOOT_AND_FUNCTIONS_NOT_TESTED\nKEEP_USERDATA_AND_METADATA\nONLY_SYSTEM_AND_ODM_CHANGED\n')
# Keep the flash gate closed until all remaining checks have passed separately.
(delivery/'EXTENT_AUDIT.txt').write_text('EXTENT_AUDIT_OK\nSTAGE43_ALL_OTHER_BYTES_IDENTICAL\n'+f'SUPER_SHA256={digest}\n')
print((delivery/'EXTENT_AUDIT.txt').read_text(),flush=True)
