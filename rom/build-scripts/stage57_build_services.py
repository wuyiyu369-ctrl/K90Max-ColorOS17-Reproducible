"""Patch live Stage56 services.jar for the Dynamic Island fan controls."""

from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import zipfile


ROOT = Path("/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo")
WORK = ROOT / "_fan_live_services_stage57"
BASE_JAR = WORK / "services.jar"
LIVE_SMALI = WORK / "live_smali"
EDITED_SMALI = WORK / "patched_smali"
VERIFY_SMALI = WORK / "verify_smali"
OUTPUT_DEX = WORK / "classes4.stage57.dex"
OUTPUT_JAR = WORK / "services.stage57.jar"
AUDIT = WORK / "stage57_services_audit.txt"
TOOLS = Path("/mnt/d/k90tools")
JAVA = "/usr/bin/java"
EXPECTED_DEX_SHA256 = (
    "27d7dbb73a704748d28c49b8b244ebde1905432d9887d67accc347d688afc3a3"
)
EXPECTED_CHANGES = {
    "com/android/server/wm/ActivityTaskManagerService$SettingObserver.smali",
    "com/android/server/wm/K90ThermalBridge.smali",
}


def digest_tree(root: Path) -> dict[str, str]:
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in root.rglob("*.smali")
    }


classpath = os.pathsep.join(str(path) for path in sorted(TOOLS.glob("*.jar")))
if not classpath:
    raise RuntimeError(f"No smali toolchain found in {TOOLS}")
if not Path(JAVA).is_file():
    raise RuntimeError(f"Java missing: {JAVA}")

with zipfile.ZipFile(BASE_JAR) as archive:
    baseline_dex = archive.read("classes4.dex")
if hashlib.sha256(baseline_dex).hexdigest() != EXPECTED_DEX_SHA256:
    raise RuntimeError("Live Stage56 classes4.dex hash mismatch")

baseline_path = WORK / "classes4.live.stage57.dex"
baseline_path.write_bytes(baseline_dex)

if VERIFY_SMALI.exists():
    shutil.rmtree(VERIFY_SMALI)
VERIFY_SMALI.mkdir()
subprocess.run(
    [
        JAVA,
        "-cp",
        classpath,
        "com.android.tools.smali.baksmali.Main",
        "d",
        "--api",
        "34",
        str(baseline_path),
        "-o",
        str(VERIFY_SMALI),
    ],
    check=True,
)

changed = set()
for name in sorted(EXPECTED_CHANGES):
    baseline_file = VERIFY_SMALI / name
    edited_file = EDITED_SMALI / name
    if not baseline_file.is_file() or not edited_file.is_file():
        raise RuntimeError(f"Expected patch class missing: {name}")
    if baseline_file.read_bytes() != edited_file.read_bytes():
        changed.add(name)
if changed != EXPECTED_CHANGES:
    raise RuntimeError(f"Expected patch classes were not changed: {sorted(changed)}")

OUTPUT_DEX.unlink(missing_ok=True)
subprocess.run(
    [
        JAVA,
        "-cp",
        classpath,
        "com.android.tools.smali.smali.Main",
        "assemble",
        "--api",
        "34",
        str(EDITED_SMALI),
        "-o",
        str(OUTPUT_DEX),
    ],
    check=True,
)

OUTPUT_JAR.unlink(missing_ok=True)
with zipfile.ZipFile(BASE_JAR) as source, zipfile.ZipFile(
    OUTPUT_JAR, "w", zipfile.ZIP_DEFLATED
) as target:
    for info in source.infolist():
        payload = (
            OUTPUT_DEX.read_bytes()
            if info.filename == "classes4.dex"
            else source.read(info.filename)
        )
        target.writestr(info, payload)

with zipfile.ZipFile(BASE_JAR) as source, zipfile.ZipFile(OUTPUT_JAR) as target:
    if source.namelist() != target.namelist():
        raise RuntimeError("JAR member order changed")
    if target.testzip() is not None:
        raise RuntimeError("Output JAR failed CRC validation")
    for name in source.namelist():
        if name != "classes4.dex" and source.read(name) != target.read(name):
            raise RuntimeError(f"Unexpected JAR member change: {name}")

before_classes = set(
    subprocess.check_output(
        [
            JAVA,
            "-cp",
            classpath,
            "com.android.tools.smali.baksmali.Main",
            "list",
            "classes",
            str(baseline_path),
        ],
        text=True,
    ).splitlines()
)
after_classes = set(
    subprocess.check_output(
        [
            JAVA,
            "-cp",
            classpath,
            "com.android.tools.smali.baksmali.Main",
            "list",
            "classes",
            str(OUTPUT_DEX),
        ],
        text=True,
    ).splitlines()
)
if before_classes != after_classes or len(after_classes) != 6867:
    raise RuntimeError("DEX class-set validation failed")

verify_output = WORK / "verify_output_smali"
if verify_output.exists():
    shutil.rmtree(verify_output)
verify_output.mkdir()
subprocess.run(
    [
        JAVA,
        "-cp",
        classpath,
        "com.android.tools.smali.baksmali.Main",
        "d",
        "--api",
        "34",
        str(OUTPUT_DEX),
        "-o",
        str(verify_output),
    ],
    check=True,
)
for name in sorted(EXPECTED_CHANGES):
    assembled = verify_output / name
    edited = EDITED_SMALI / name
    if not assembled.is_file():
        raise RuntimeError(f"Assembled patch class missing: {name}")
    # Strip source/line and synthetic outer comment noise, but retain every
    # instruction, catch handler, field and method descriptor.
    def semantic(path: Path) -> list[str]:
        result = []
        for line in path.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith(".line "):
                continue
            if s.startswith(".source "):
                continue
            if s.startswith(".local ") and s.endswith(";") and "=" not in s:
                continue
            if s.startswith(":"):
                continue
            # The assembler is free to renumber labels after adding fields and
            # instructions. Compare the actual opcodes and operands while
            # canonicalising only label identifiers.
            s = re.sub(r":(?!LBL\b)[A-Za-z_][A-Za-z0-9_]*", ":LBL", s)
            result.append(s)
        return result

    assembled_semantic = semantic(assembled)
    edited_semantic = semantic(edited)
    if len(assembled_semantic) != len(edited_semantic):
        raise RuntimeError(
            f"Assembled patch class line count differs: {name} "
            f"{len(edited_semantic)} -> {len(assembled_semantic)}"
        )
    # Smali emits fields in descriptor order, which can differ from the
    # hand-edited source order. The class contract is the multiset of fields
    # plus the method/instruction order; compare both explicitly.
    edited_fields = sorted(x for x in edited_semantic if x.startswith(".field "))
    assembled_fields = sorted(x for x in assembled_semantic if x.startswith(".field "))
    edited_body = [x for x in edited_semantic if not x.startswith(".field ")]
    assembled_body = [x for x in assembled_semantic if not x.startswith(".field ")]
    if edited_fields != assembled_fields:
        raise RuntimeError(f"Assembled patch class fields differ: {name}")
    if edited_body != assembled_body:
        first = next(
            i
            for i, (left, right) in enumerate(
                zip(edited_body, assembled_body, strict=True)
            )
            if left != right
        )
        raise RuntimeError(
            f"Assembled patch class changed semantically: {name} "
            f"at normalized body line {first + 1}: "
            f"{edited_body[first]!r} != {assembled_body[first]!r}"
        )

AUDIT.write_text(
    "STAGE57_SERVICES_BUILD_PASSED\n"
    "BASELINE=STAGE56_LIVE_SERVICES_JAR\n"
    "CHANGED_SMALI_CLASSES=2\n"
    + "\n".join(f"CHANGED={name}" for name in sorted(changed))
    + "\nCLASSES4_CLASS_COUNT=6867\n"
    f"OUTPUT_CLASSES4_SHA256={hashlib.sha256(OUTPUT_DEX.read_bytes()).hexdigest()}\n"
    "OTHER_JAR_MEMBERS_IDENTICAL\n",
    encoding="ascii",
)
print(AUDIT.read_text(encoding="ascii"), end="")
