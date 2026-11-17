#!/usr/bin/env python3
import hashlib
import pathlib
import sys


EXPECTED = "bb9a8cb489308b32a7df0dad3d725474a5671c055198a9270ee07c527d1de4a9"
OFFSET = 0x1E7B4
BEFORE = bytes.fromhex("1f2003d540c20210")
# The Binder was already resolved and stored globally. Android 17 rejects the
# donor's legacy death cookie, so return success without registering it.
AFTER = bytes.fromhex("e0031f2a3d000014")  # mov w0,wzr; b 0x1e8ac


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} LIB64_UAH")
    path = pathlib.Path(sys.argv[1])
    data = bytearray(path.read_bytes())
    actual = sha256(data)
    if actual != EXPECTED:
        raise SystemExit(f"unexpected input hash: {actual}")
    if data[OFFSET:OFFSET + len(BEFORE)] != BEFORE:
        raise SystemExit("unexpected control-flow bytes")
    data[OFFSET:OFFSET + len(AFTER)] = AFTER
    path.write_bytes(data)
    print(f"patched offset=0x{OFFSET:x} sha256={sha256(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
