"""Build the Stage49 services.jar while preserving the Stage48 baseline."""

from pathlib import Path
import hashlib
import shutil
import subprocess
import zipfile


ROOT = Path("/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo")
WORK = ROOT / "stage44_services"
BASE_JAR = WORK / "services.stage44.jar"
EDITED_SMALI = WORK / "smali"
VERIFY_SMALI = ROOT / "stage49_services_verify"
OUTPUT_DEX = ROOT / "stage49_services_classes4.dex"
OUTPUT_JAR = ROOT / "stage49_services.jar"
AUDIT = ROOT / "stage49_services_audit.txt"
TOOLS = Path(
    "/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/smali3"
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


classpath = ":".join(str(path) for path in sorted(TOOLS.glob("*.jar")))
if not classpath:
    raise RuntimeError(f"No smali toolchain found in {TOOLS}")

with zipfile.ZipFile(BASE_JAR) as archive:
    baseline_dex = archive.read("classes4.dex")

if VERIFY_SMALI.exists():
    shutil.rmtree(VERIFY_SMALI)
VERIFY_SMALI.mkdir(parents=True)
baseline_path = ROOT / "stage49_services_classes4.baseline.dex"
baseline_path.write_bytes(baseline_dex)

subprocess.run(
    [
        "java",
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

baseline_hashes = digest_tree(VERIFY_SMALI)
edited_hashes = digest_tree(EDITED_SMALI)
if baseline_hashes.keys() != edited_hashes.keys():
    missing = sorted(baseline_hashes.keys() - edited_hashes.keys())
    added = sorted(edited_hashes.keys() - baseline_hashes.keys())
    raise RuntimeError(f"Class set changed: missing={missing[:5]} added={added[:5]}")

changed = {
    name for name in baseline_hashes if baseline_hashes[name] != edited_hashes[name]
}
if changed != EXPECTED_CHANGES:
    raise RuntimeError(f"Unexpected smali changes: {sorted(changed)}")

if OUTPUT_DEX.exists():
    OUTPUT_DEX.unlink()
subprocess.run(
    [
        "java",
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

if OUTPUT_JAR.exists():
    OUTPUT_JAR.unlink()
with zipfile.ZipFile(BASE_JAR) as source, zipfile.ZipFile(
    OUTPUT_JAR, "w", zipfile.ZIP_DEFLATED
) as target:
    for info in source.infolist():
        payload = OUTPUT_DEX.read_bytes() if info.filename == "classes4.dex" else source.read(info.filename)
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
            "java",
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
            "java",
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

AUDIT.write_text(
    "STAGE49_SERVICES_BUILD_PASSED\n"
    "BASELINE=STAGE48_SERVICES_JAR\n"
    "CHANGED_SMALI_CLASSES=2\n"
    + "\n".join(f"CHANGED={name}" for name in sorted(changed))
    + "\nCLASSES4_CLASS_COUNT=6867\n"
    "OTHER_JAR_MEMBERS_IDENTICAL\n",
    encoding="ascii",
)
print(AUDIT.read_text(encoding="ascii"), end="")
