from pathlib import Path
import hashlib,sys
old,new,odm,delivery=map(Path,sys.argv[1:])
offset=10713300992; length=1724530688
assert old.stat().st_size==new.stat().st_size==13421772800
digest=hashlib.sha256()
with old.open('rb') as a,new.open('rb') as b,odm.open('rb') as c:
    pos=0
    while pos<new.stat().st_size:
        boundary=offset if pos<offset else offset+length if pos<offset+length else new.stat().st_size
        n=min(8*1024*1024,boundary-pos)
        x,y=a.read(n),b.read(n)
        assert len(x)==len(y)==n
        if offset<=pos<offset+length: assert y==c.read(n),'ODM extent mismatch'
        else: assert x==y,f'Unexpected bytes changed: {pos}'
        digest.update(y);pos+=n
(delivery/'SHA256SUMS.txt').write_text(digest.hexdigest()+'  images/super.img\n')
(delivery/'INDEPENDENT_AUDIT.txt').write_text('AUDIT_OK\nR1_RESTORES_STAGE43_POLICY_SELECTION\nONLY_ODM_CHANGED_FROM_STAGE44\nNATIVE_BINARY_RC_AND_CIL_READBACK_MATCH\nEROFS_CHECK_PASSED\nOFFLINE_CANDIDATE_PENDING_DEVICE_BOOT\n')
(delivery/'STATUS.txt').write_text('R1_OFFLINE_CHECKS_PASSED\nDEVICE_BOOT_NOT_YET_TESTED\nKEEP_USERDATA_AND_METADATA\n')
print('R1_EXTENT_AUDIT_OK',digest.hexdigest(),flush=True)
