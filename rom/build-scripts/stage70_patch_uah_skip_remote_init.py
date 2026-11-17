#!/usr/bin/env python3
import hashlib
import pathlib
import sys


PATCHES = {
    "lib64/liboplus-uah-client.so": {
        "sha256": "4052fcf3e29ce32706f63083468762fdd135c5f6fb18bfefcd6c329fa3c02d28",
        "offset": 0x1E4BC,
        "before": bytes.fromhex("400100341f2003d5"),
        # Preserve the helper result in w19. A zero result means that the
        # Binder reference is already stored globally, so return immediately
        # instead of issuing the incompatible remote urccInit transaction.
        "after": bytes.fromhex("f303002a800a0034"),
    },
    "lib/liboplus-uah-client.so": {
        "sha256": "b51f58a8f898c8dd00814638af8ac6b4e184384d8d5916188914198096bf3f61",
        # Thumb VA 0x13a18 maps to file offset 0x12a18.
        "offset": 0x12A18,
        "before": bytes.fromhex("58b14a494a4a06204ff0ff334ff0ff34"),
        # mov r4,r0; cmp r0,#0; beq.w epilogue; mov.w r4,#-1; b.w epilogue
        "after": bytes.fromhex("0446002800f06e804ff0ff3400f06ab8"),
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
        print(f"patched {relative} offset=0x{start:x} sha256={digest(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
