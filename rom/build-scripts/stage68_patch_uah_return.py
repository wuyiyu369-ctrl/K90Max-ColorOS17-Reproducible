#!/usr/bin/env python3
import hashlib
import pathlib
import sys


EXPECTED = "de45bdd6fba3c159fde3afdb94c5a6f9f48da904f400d6b8969f87e8e17f0e39"
OFFSET = 0x1E810
BEFORE = bytes.fromhex("27000014f30640f9")
# mov w0, wzr; b 0x1e8ac
AFTER = bytes.fromhex("e0031f2a26000014")


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
        raise SystemExit(
            f"unexpected instruction bytes: "
            f"{data[OFFSET:OFFSET + len(BEFORE)].hex()}"
        )
    data[OFFSET:OFFSET + len(AFTER)] = AFTER
    path.write_bytes(data)
    print(f"patched offset=0x{OFFSET:x} sha256={sha256(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
