from pathlib import Path
import hashlib, sys
base, delivery, parts = map(Path, sys.argv[1:])
image = delivery/'images/super.img'
ranges = [(2304770048, 1138266112, 'my_product'), (10713300992, 1724530688, 'odm')]
assert base.stat().st_size == image.stat().st_size == 13421772800
h = hashlib.sha256()
with base.open('rb') as a, image.open('rb') as b:
    pos = 0
    for offset, size, name in ranges + [(image.stat().st_size, 0, '')]:
        while pos < offset:
            n = min(8*1024*1024, offset-pos)
            x,y = a.read(n), b.read(n)
            assert len(x)==len(y)==n and x==y, ('unexpected extent change',pos)
            h.update(y); pos += n
        if not size: break
        with (parts/(name+'.img')).open('rb') as p:
            while pos < offset+size:
                n=min(8*1024*1024, offset+size-pos)
                x,y=b.read(n),p.read(n)
                assert len(x)==len(y)==n and x==y
                h.update(x); a.seek(n,1); pos+=n
(delivery/'SHA256SUMS.txt').write_text(h.hexdigest()+'  images/super.img\n')
(delivery/'STATUS.txt').write_text('OFFLINE_CHECKS_PASSED\nDEVICE_BOOT_NOT_YET_TESTED\nKEEP_USERDATA_AND_METADATA\nNO_NEW_BINARY_POLICY_OR_HASH_MARKERS\n')
(delivery/'audit/extent_verification.txt').write_text('Only ODM and my_product extents differ from booted Stage44 R1.\n'+str(ranges)+'\n')
print('STAGE45_EXTENT_AUDIT_PASSED',h.hexdigest(),flush=True)
