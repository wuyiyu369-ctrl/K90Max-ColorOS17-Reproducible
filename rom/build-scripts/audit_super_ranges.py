from pathlib import Path

base = Path(r"D:/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage35_CAMERA_RETURN_PERF_SAFE_R1/images/super.img")
new = Path(r"D:/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER/images/super.img")
size = 13421772800
ranges = (
    (562688 * 4096, (562688 + 277897) * 4096),
    (2615552 * 4096, (2615552 + 421028) * 4096),
)
assert base.stat().st_size == new.stat().st_size == size
chunk = 8 * 1024 * 1024
pos = 0
bad = 0
allowed = 0
with base.open("rb") as left, new.open("rb") as right:
    while pos < size:
        n = min(chunk, size - pos)
        a = left.read(n)
        b = right.read(n)
        assert len(a) == len(b) == n
        if a != b:
            # The candidate is allowed to differ only in the two logical
            # extents. Compare only bytes outside those extents; this avoids
            # a Python byte-at-a-time walk over the unchanged 12.8 GB file.
            outside = [(0, n)]
            for start, end in ranges:
                rs = max(0, start - pos)
                re = min(n, end - pos)
                if rs >= re:
                    continue
                next_outside = []
                for lo, hi in outside:
                    if hi <= rs or lo >= re:
                        next_outside.append((lo, hi))
                    else:
                        if lo < rs:
                            next_outside.append((lo, rs))
                        if re < hi:
                            next_outside.append((re, hi))
                outside = next_outside
            for lo, hi in outside:
                if a[lo:hi] != b[lo:hi]:
                    bad += 1
                    if bad <= 3:
                        print(f"unexpected mismatch in [{pos + lo}, {pos + hi})")
            allowed += n - sum(hi - lo for lo, hi in outside)
        pos += n
print(f"size={size} allowed_changed_bytes={allowed} unexpected_mismatch_bytes={bad}")
print("AUDIT_OK" if bad == 0 else "AUDIT_FAIL")
