#!/usr/bin/env python3
"""Generate exact SELinux file-context entries from a prepared image tree."""

import argparse
import os
import re
from pathlib import Path


def iter_paths(root: Path):
    yield root
    for current, directories, files in os.walk(root, followlinks=False):
        base = Path(current)
        for name in sorted(directories + files):
            yield base / name


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("mount_point")
    parser.add_argument("output", type=Path)
    parser.add_argument("--override", action="append", default=[])
    args = parser.parse_args()

    root = args.root.resolve()
    mount_point = "/" + args.mount_point.strip("/")
    overrides = {}
    for item in args.override:
        path, label = item.split("=", 1)
        overrides["/" + path.strip("/")] = label

    entries = []
    missing = []
    for path in iter_paths(root):
        relative = path.relative_to(root)
        image_path = mount_point
        if relative.parts:
            image_path += "/" + relative.as_posix()
        label = overrides.get(image_path)
        if label is None:
            try:
                label = os.getxattr(path, "security.selinux", follow_symlinks=False)
                label = label.decode().rstrip("\0")
            except OSError:
                missing.append(image_path)
                continue
        entries.append((image_path, label))

    if missing:
        raise SystemExit("Missing SELinux labels:\n" + "\n".join(missing[:100]))

    with args.output.open("w", encoding="utf-8", newline="\n") as stream:
        for image_path, label in sorted(entries, key=lambda item: item[0]):
            # mkfs.erofs expects SELinux contexts syntax, whose left side is
            # already a regular expression. Escape every path metacharacter:
            # notably '+' in libc++_shared.so otherwise fails to match, leaving
            # that real ODM file unlabeled in the rebuilt filesystem.
            stream.write(f"{re.escape(image_path)} {label}\n")

    print(f"FILE_CONTEXTS_OK entries={len(entries)} overrides={len(overrides)}")


if __name__ == "__main__":
    main()
