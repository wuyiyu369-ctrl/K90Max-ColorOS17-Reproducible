#!/usr/bin/env python3
import hashlib
import pathlib
import sys


PATCHES = {
    "lib64/liboplus-uah-client.so": {
        "sha256": "6df0ea018d11729ec6493f641a3bb252feefc376f8324e4e07e1a207a37a66cf",
        "offset": 0x1E810,
        "before": bytes.fromhex("e0040034"),  # cbz w0, success
        "after": bytes.fromhex("27000014"),   # b success
    },
    "lib/liboplus-uah-client.so": {
        "sha256": "fb23560a31ab3b1ec88299967cb40c1e09e9a1a789f1b21048fc0f9a565515aa",
        # The 32-bit executable LOAD segment maps file offset 0x8f68 to
        # virtual address 0x9f68, so VA 0x13c6c is file offset 0x12c6c.
        "offset": 0x12C6C,
        "before": bytes.fromhex("0146"),      # mov r1, r0
        "after": bytes.fromhex("0021"),       # movs r1, #0
    },
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} SYSTEM_EXT_ROOT")
    root = pathlib.Path(sys.argv[1])
    for relative, spec in PATCHES.items():
        path = root / relative
        data = bytearray(path.read_bytes())
        actual = digest(data)
        if actual != spec["sha256"]:
            raise SystemExit(f"unexpected input hash for {relative}: {actual}")
        start = spec["offset"]
        end = start + len(spec["before"])
        if data[start:end] != spec["before"]:
            raise SystemExit(
                f"unexpected instruction at {relative}+0x{start:x}: "
                f"{data[start:end].hex()}"
            )
        data[start:end] = spec["after"]
        path.write_bytes(data)
        print(
            f"patched {relative} offset=0x{start:x} "
            f"sha256={digest(data)}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
