$ErrorActionPreference = 'Stop'
$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
if (-not $archiveRoot) { throw 'K90 archive root not found' }
$jarRoot = (Get-ChildItem $archiveRoot -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
if (-not $jarRoot) { throw 'tool jar directory not found' }
$cp = @(
    (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $jarRoot 'jars\antlr.jar'),
    (Join-Path $jarRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'
$root = Join-Path $PSScriptRoot 'sms_native_r2'
$inputJar = Join-Path $root 'telephony-common.stage24.jar'
$smali = Join-Path $root 'smali'
$dex = Join-Path $root 'classes.patched.dex'
$outputJar = Join-Path $root 'telephony-common.native-sms-r2.jar'
if (-not (Test-Path $inputJar)) { throw 'Current Stage24 telephony JAR is missing' }
foreach ($p in @($smali, $dex, $outputJar)) { if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force } }

& $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 $inputJar -o $smali
if ($LASTEXITCODE -ne 0) { throw "baksmali failed: $LASTEXITCODE" }

$targets = @(
    (Join-Path $smali 'com\android\internal\telephony\gsm\GsmInboundSmsHandler.smali'),
    (Join-Path $smali 'com\android\internal\telephony\cdma\CdmaInboundSmsHandler.smali')
)
foreach ($target in $targets) {
    $text = [IO.File]::ReadAllText($target)
    $needle = '    invoke-virtual {v0}, Lcom/android/internal/telephony/StateMachine;->start()V'
    $replacement = $needle + "`r`n`r`n    const/4 v1, 0x6`r`n`r`n    invoke-virtual {v0, v1}, Lcom/android/internal/telephony/StateMachine;->sendMessage(I)V"
    $count = ([regex]::Matches($text, [regex]::Escape($needle))).Count
    if ($count -ne 1) { throw "Unexpected start() match count $count in $target" }
    [IO.File]::WriteAllText($target, $text.Replace($needle, $replacement), [Text.UTF8Encoding]::new($false))
}

& $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $smali -o $dex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }

@'
from pathlib import Path
import zipfile
root = Path(__file__).resolve().parent / "sms_native_r2"
src = root / "telephony-common.stage24.jar"
dex = root / "classes.patched.dex"
out = root / "telephony-common.native-sms-r2.jar"
with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(out, "w") as zout:
    for info in zin.infolist():
        data = dex.read_bytes() if info.filename == "classes.dex" else zin.read(info.filename)
        clone = zipfile.ZipInfo(info.filename, info.date_time)
        for attr in ("compress_type", "comment", "extra", "internal_attr", "external_attr", "create_system", "create_version", "extract_version"):
            setattr(clone, attr, getattr(info, attr))
        zout.writestr(clone, data)
'@ | & py -3 -
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outputJar)) { throw 'JAR packaging failed' }
Get-FileHash $inputJar, $outputJar -Algorithm SHA256
